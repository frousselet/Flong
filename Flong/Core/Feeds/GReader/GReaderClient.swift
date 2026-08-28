//
//  GReaderClient.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import OSLog

/// HTTP layer of the Google Reader API that FreshRSS serves at `/api/greader.php`.
///
/// The actor serializes the two tokens the API uses : the session token returned
/// by `ClientLogin`, and the modification token that every POST must carry.
actor GReaderClient {
    /// Path of the API inside a FreshRSS instance.
    static let apiPath = "api/greader.php"

    /// How long a modification token is reused before being fetched again.
    ///
    /// FreshRSS derives its token from the account salt and does not expire it,
    /// but its source carries a note about implementing expiry, so the token is
    /// treated as perishable rather than cached for the life of the session.
    private static let modificationTokenLifetime: TimeInterval = 25 * 60

    private let baseURL: URL
    private let session: URLSession

    private var authToken: String?
    private var modificationToken: String?
    private var modificationTokenDate: Date?

    init(baseURL: URL, session: URLSession = .shared, authToken: String? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.authToken = authToken
    }

    var currentAuthToken: String? { authToken }

    func setAuthToken(_ token: String?) {
        authToken = token
        modificationToken = nil
        modificationTokenDate = nil
    }

    // MARK: - Authentication

    /// Exchanges credentials for a session token.
    ///
    /// The reply is `text/plain`, three lines of `SID`, `LSID` and `Auth`. Only
    /// `Auth` matters. FreshRSS answers 401 on a wrong password and 400 on an
    /// unknown user, so both are reported as rejected credentials.
    ///
    /// - Parameter password: the FreshRSS API password, not the web one.
    @discardableResult
    func clientLogin(email: String, password: String) async throws -> String {
        let url = try makeURL(path: "accounts/ClientLogin", query: [])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded([("Email", email), ("Passwd", password)])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GReaderError.decoding("Unexpected HTTP response")
        }

        let body = String(decoding: data, as: UTF8.self)
        guard http.statusCode == 200 else {
            if [400, 401, 403].contains(http.statusCode) || body.contains("BadAuthentication") {
                throw GReaderError.badCredentials
            }
            throw GReaderError.http(status: http.statusCode, body: body)
        }
        guard let token = Self.parseClientLogin(body) else {
            throw GReaderError.missingAuthToken
        }

        setAuthToken(token)
        Log.auth.info("Session opened")
        return token
    }

    /// Pulls the `Auth=` line out of a `ClientLogin` reply.
    static func parseClientLogin(_ body: String) -> String? {
        for line in body.split(whereSeparator: \.isNewline) where line.hasPrefix("Auth=") {
            let token = line.dropFirst("Auth=".count).trimmingCharacters(in: .whitespaces)
            return token.isEmpty ? nil : token
        }
        return nil
    }

    // MARK: - Requests

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        let data = try await getData(path, query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GReaderError.decoding(String(describing: error))
        }
    }

    func getData(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = "GET"
        try authorize(&request)
        return try await perform(request)
    }

    /// Form encoded POST. The modification token is appended automatically,
    /// since every write endpoint rejects a request without it.
    @discardableResult
    func post(_ path: String, form: [(String, String)], includeModificationToken: Bool = true) async throws -> String {
        var fields = form
        if includeModificationToken {
            fields.append(("T", try await modificationTokenValue()))
        }

        var request = URLRequest(url: try makeURL(path: path, query: []))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded(fields)
        try authorize(&request)

        return String(decoding: try await perform(request), as: UTF8.self)
    }

    /// The modification token, fetched again once it is missing or stale.
    func modificationTokenValue() async throws -> String {
        if let modificationToken, let modificationTokenDate,
            Date.now.timeIntervalSince(modificationTokenDate) < Self.modificationTokenLifetime
        {
            return modificationToken
        }

        let data = try await getData("reader/api/0/token")
        let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw GReaderError.missingAuthToken }

        modificationToken = token
        modificationTokenDate = .now
        return token
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GReaderError.decoding("Unexpected HTTP response")
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            Log.network.warning("Request rejected with \(http.statusCode), session needs renewing")
            throw GReaderError.notAuthenticated
        default:
            throw GReaderError.http(status: http.statusCode, body: String(decoding: data.prefix(512), as: UTF8.self))
        }
    }

    private func authorize(_ request: inout URLRequest) throws {
        guard let authToken else { throw GReaderError.notAuthenticated }
        request.setValue("GoogleLogin auth=\(authToken)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - URL building

    /// - Parameter path: path below `/api/greader.php`, with its segments already escaped.
    func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        let root =
            baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString

        guard var components = URLComponents(string: "\(root)/\(Self.apiPath)/\(path)") else {
            throw GReaderError.invalidServerURL
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else { throw GReaderError.invalidServerURL }
        return url
    }

    /// Encodes an `application/x-www-form-urlencoded` body. A list of pairs
    /// rather than a dictionary, because `edit-tag` repeats the `i` field.
    static func formEncoded(_ fields: [(String, String)]) -> Data {
        let body =
            fields
            .map { "\(escapeFormValue($0.0))=\(escapeFormValue($0.1))" }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func escapeFormValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .greaderFormValue) ?? value
    }
}

nonisolated extension CharacterSet {
    /// Unreserved characters only, so nothing in a form value can be read as a separator.
    static let greaderFormValue = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
}
