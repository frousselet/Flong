//
//  GoogleReaderClient.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Which account an import is reading, without the secret that opens it.
///
/// This is the part that may be written down : an address and a name. The API
/// password stays in the keychain, keyed by the job, and is read back only when
/// a session has to be opened again.
nonisolated struct ServiceAccount: Hashable, Sendable, Codable {
    /// Where the API is, already resolved by ``GoogleReader/base(of:)``.
    var endpoint: URL
    var username: String

    /// What the reader recognizes their own server by, which is its host and
    /// not the script at the end of the path.
    var host: String { endpoint.host() ?? endpoint.absoluteString }
}

/// Reads an account held by a service that speaks the Google Reader API.
///
/// **It only ever reads.** Flong is not a client for any service : section 19 of
/// the specification makes a remote account a one-shot import source and keeps
/// no link with it afterwards, so nothing here writes a state back, marks
/// anything read or unsubscribes from anything. The write endpoints exist and
/// are deliberately not called.
///
/// A session is a token the server hands out and does not expire on its own.
/// Signing in again is cheap, so a resumed import opens a fresh one rather than
/// keeping one across launches.
nonisolated struct GoogleReaderClient: Sendable {
    /// How many articles a page asks for.
    ///
    /// The server defaults to twenty and sets no maximum of its own, so this is
    /// entirely Flong's choice : large enough that an import of a thousand
    /// articles is ten requests rather than fifty, small enough that a page of
    /// bodies is a few megabytes rather than a hundred.
    static let pageSize = 100

    let account: ServiceAccount
    private let token: String
    private let session: URLSession
    private let userAgent: String

    /// The session the import runs in.
    ///
    /// Ephemeral and cookieless, exactly as the fetcher's : the token is the
    /// whole of the authentication, and a cookie jar surviving an import would
    /// be a link with the service that section 19 says there is not.
    static func defaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    // MARK: - Signing in

    /// Opens a session with the name and the API password.
    ///
    /// **The API password, which is not the web password.** FreshRSS asks for a
    /// second one under Profile, and refuses the first here ; the screen says so
    /// because nothing else will.
    ///
    /// `POST` rather than the `GET` the server still accepts : a password in a
    /// query string is a password in the server's access log.
    static func signIn(
        to address: String,
        username: String,
        password: String,
        session: URLSession? = nil,
        userAgent: String = FeedFetcher.defaultUserAgent
    ) async throws(ServiceError) -> GoogleReaderClient {
        guard let endpoint = GoogleReader.base(of: address) else { throw ServiceError.badAddress }

        let account = ServiceAccount(endpoint: endpoint, username: username)
        let session = session ?? defaultSession()

        var request = URLRequest(url: endpoint.appending(path: "accounts/ClientLogin"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(
            "Email=\(Self.escaped(username))&Passwd=\(Self.escaped(password))".utf8
        )

        let data = try await Self.answer(to: request, in: session)

        // Three lines of `text/plain`, and only `Auth` matters. `SID` is the
        // same string under another name and `LSID` is the string `null`.
        guard let text = String(data: data, encoding: .utf8),
            let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("Auth=") })
        else { throw ServiceError.unreadable }

        let token = String(line.dropFirst("Auth=".count)).trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { throw ServiceError.unreadable }

        return GoogleReaderClient(account: account, token: token, session: session, userAgent: userAgent)
    }

    // MARK: - Reading the account

    /// Every subscription of the account, hidden feeds excepted, which the
    /// server omits on its own.
    func subscriptions() async throws(ServiceError) -> [GoogleReaderSubscription] {
        let list: GoogleReaderSubscriptionList = try await get("subscription/list")
        return list.subscriptions
    }

    /// One page of a stream, newest first.
    ///
    /// - Parameters:
    ///   - stream: `feed/42`, or one of the built-in states.
    ///   - continuation: what the previous page ended with, or `nil` to start.
    ///   - count: how many articles to ask for.
    func page(
        of stream: String,
        continuation: String? = nil,
        count: Int = GoogleReaderClient.pageSize
    ) async throws(ServiceError) -> GoogleReaderPage {
        var query = [
            URLQueryItem(name: "n", value: String(count)),
            // Newest first, so a bounded import brings the recent history
            // rather than whatever the server happens to hold from 2011.
            URLQueryItem(name: "r", value: "d"),
        ]
        // The server resets a continuation that is not all digits rather than
        // refusing it, which restarts the stream silently and would loop an
        // import for ever. Anything else is treated as the end.
        if let continuation, !continuation.isEmpty {
            guard continuation.allSatisfy(\.isNumber) else { throw ServiceError.unreadable }
            query.append(URLQueryItem(name: "c", value: continuation))
        }

        return try await get("stream/contents/" + stream, query: query)
    }

    // MARK: - The requests themselves

    private func get<Value: Decodable>(
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws(ServiceError) -> Value {
        // **Into the path with its separators intact.** The server explodes the
        // route on `/` and matches segment by segment, so a stream identifier
        // escaped as one component makes the route fail. `URLComponents` writes
        // the path exactly that way : the slashes stay, a space in a label
        // becomes `%20`.
        guard var components = URLComponents(url: account.endpoint, resolvingAgainstBaseURL: false) else {
            throw ServiceError.badAddress
        }
        components.path += "/reader/api/0/" + path
        // Mandatory on several of these : without it the server answers 501.
        components.queryItems = [URLQueryItem(name: "output", value: "json")] + query

        guard let url = components.url else { throw ServiceError.badAddress }

        var request = URLRequest(url: url)
        request.setValue("GoogleLogin auth=\(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data = try await Self.answer(to: request, in: session)
        guard let value = try? JSONDecoder().decode(Value.self, from: data) else {
            throw ServiceError.unreadable
        }
        return value
    }

    private static func answer(to request: URLRequest, in session: URLSession) async throws(ServiceError) -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ServiceError.unreachable
        }

        guard let http = response as? HTTPURLResponse else { throw ServiceError.unreadable }

        switch http.statusCode {
        case 200..<300:
            return data
        // A wrong password answers 401 and an unknown name answers 400, and
        // both mean the same thing to the reader : the credentials were not
        // accepted. 403 is the same answer from a session that has gone.
        case 400, 401, 403:
            throw ServiceError.rejected
        default:
            throw ServiceError.refused(http.statusCode)
        }
    }

    /// Form encoding, which is stricter than an address's.
    ///
    /// A password is exactly the sort of string that holds a `+`, and a `+` in a
    /// form body is a space. `&` and `=` would end the field.
    private static func escaped(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
