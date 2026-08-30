//
//  FeedFetcher.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import OSLog

/// What Flong knows about a feed before asking for it again.
nonisolated struct FetchRequest: Hashable, Sendable {
    let url: URL
    var etag: String?
    var lastModified: String?
    /// What proves the reader is entitled to it, for a feed that asks.
    /// Section 9 keeps it in the keychain ; it reaches a request and goes no
    /// further.
    var credential: FeedCredential?
    /// The cookies of a session the reader signed in for, when the request is
    /// to a site they subscribe to. Only ever that site's own.
    var cookies: [SessionCookie] = []
}

/// A feed as the server just served it.
nonisolated struct FetchedDocument: Sendable {
    let data: Data
    let contentType: String?
    let etag: String?
    let lastModified: String?
    /// Where the request ended up, redirects followed.
    let url: URL
}

/// Why a fetch did not bring a feed back.
nonisolated enum FetchFailure: Error, Hashable, Sendable {
    /// The request never reached a server, or the connection broke.
    case unreachable
    /// The feed needs credentials, or refuses these. Section 9 quarantines it.
    case unauthorized(status: Int)
    /// The feed is not there any more.
    case gone(status: Int)
    /// The server asked to be left alone, with the moment it named.
    case rateLimited(retryAfter: TimeInterval?)
    /// Any other status.
    case http(status: Int)
    /// The body ran past the cap without ending.
    case tooLarge
    /// The request was cancelled.
    case cancelled
}

/// What a fetch came back with.
nonisolated enum FetchOutcome: Sendable {
    case updated(FetchedDocument)
    /// The server answered 304 : nothing changed, and it cost almost nothing.
    case notModified
    case failed(FetchFailure)
}

/// Asks servers for feeds, politely.
///
/// Every request is conditional, capped in size and in time, and spaced out per
/// host. The user agent names the project and carries its address, so a
/// publisher looking at their logs can tell what is asking and why.
actor FeedFetcher {
    /// The limits every request is held to.
    nonisolated struct Limits: Hashable, Sendable {
        var timeout: TimeInterval = 15
        var resourceTimeout: TimeInterval = 60
        /// Feeds are text. A body past this is a mistake or a trap.
        var maximumBytes = 8 * 1024 * 1024
    }

    private let session: URLSession
    private let throttle: HostThrottle
    private let limits: Limits
    private let userAgent: String

    init(
        session: URLSession? = nil,
        throttle: HostThrottle = HostThrottle(),
        limits: Limits = Limits(),
        userAgent: String = FeedFetcher.defaultUserAgent
    ) {
        self.throttle = throttle
        self.limits = limits
        self.userAgent = userAgent

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = limits.timeout
            configuration.timeoutIntervalForResource = limits.resourceTimeout
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            // The store holds the conditional state itself, so a second cache
            // in front of it would only answer with what it already knows.
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Names the project and where to complain about it.
    nonisolated static var defaultUserAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Flong/\(version) (+https://github.com/frousselet/Flong)"
    }

    func fetch(_ request: FetchRequest) async -> FetchOutcome {
        let host = request.url.host() ?? ""

        let wait = await throttle.wait(forHost: host)
        if wait > 0 {
            do {
                try await Task.sleep(for: .seconds(wait))
            } catch {
                return .failed(.cancelled)
            }
        }

        do {
            return try await perform(request, host: host)
        } catch is CancellationError {
            return .failed(.cancelled)
        } catch let error as FetchFailure {
            return .failed(error)
        } catch let error as URLError where error.code == .cancelled {
            return .failed(.cancelled)
        } catch {
            // The address of a private feed is a secret : the reason a request
            // failed is logged, never what was asked for.
            Log.fetch.error("A feed could not be fetched : \(error.localizedDescription, privacy: .public)")
            return .failed(.unreachable)
        }
    }

    private func perform(_ request: FetchRequest, host: String) async throws -> FetchOutcome {
        let (bytes, response) = try await session.bytes(for: urlRequest(for: request))
        guard let response = response as? HTTPURLResponse else { return .failed(.unreachable) }

        switch response.statusCode {
        case 304:
            return .notModified

        case 429, 503:
            let retryAfter = Self.retryAfter(response.value(forHTTPHeaderField: "Retry-After"))
            await throttle.pause(host: host, until: Date().addingTimeInterval(retryAfter ?? 300))
            return .failed(.rateLimited(retryAfter: retryAfter))

        case 401, 403:
            return .failed(.unauthorized(status: response.statusCode))

        case 404, 410:
            return .failed(.gone(status: response.statusCode))

        case 200..<300:
            break

        default:
            return .failed(.http(status: response.statusCode))
        }

        // A declared length past the cap is refused before a byte is read.
        if response.expectedContentLength > Int64(limits.maximumBytes) {
            return .failed(.tooLarge)
        }

        var data = Data()
        data.reserveCapacity(64 * 1024)
        for try await byte in bytes {
            data.append(byte)
            if data.count > limits.maximumBytes { return .failed(.tooLarge) }
        }

        return .updated(
            FetchedDocument(
                data: data,
                contentType: response.value(forHTTPHeaderField: "Content-Type"),
                etag: response.value(forHTTPHeaderField: "ETag"),
                lastModified: response.value(forHTTPHeaderField: "Last-Modified"),
                url: response.url ?? request.url
            )
        )
    }

    private func urlRequest(for request: FetchRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: limits.timeout)
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue(
            "application/atom+xml, application/rss+xml, application/feed+json, application/xml;q=0.9, */*;q=0.8",
            forHTTPHeaderField: "Accept"
        )

        // URLSession asks for gzip and brotli by itself, and decodes them before
        // handing anything over. Setting Accept-Encoding here would only turn
        // that off.
        // A secret address carries no header : the secret was the address, and
        // has already been spent by the time there is a request.
        if let header = request.credential?.header {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.name)
        }

        // The session the reader signed in for, spelled the way a browser
        // spells it. Set on the request rather than left to a shared cookie
        // store, so that one site's cookies can never reach another.
        if !request.cookies.isEmpty {
            let jar = request.cookies.compactMap(\.cookie)
            for (name, value) in HTTPCookie.requestHeaderFields(with: jar) {
                urlRequest.setValue(value, forHTTPHeaderField: name)
            }
        }

        if let etag = request.etag { urlRequest.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified = request.lastModified {
            urlRequest.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        return urlRequest
    }

    /// `Retry-After` is a number of seconds or a date, and servers send both.
    nonisolated static func retryAfter(_ header: String?, now: Date = Date()) -> TimeInterval? {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return nil }

        if let seconds = TimeInterval(header) { return max(0, seconds) }
        guard let date = FeedDates.date(from: header) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }
}
