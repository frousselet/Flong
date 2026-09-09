//
//  CloudTransport.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import OSLog

/// How a request reaches a model that is not on this device, and what comes
/// back.
///
/// One of these per application rather than per account : it holds a session
/// and a bucket, and both are about hosts rather than about accounts.
nonisolated final class CloudTransport: Sendable {
    /// What every call is held to.
    nonisolated struct Limits: Hashable, Sendable {
        /// **The gap between bytes, which for a completion is the whole
        /// generation.** A service that does not stream sends nothing at all
        /// until the answer exists, so the fifteen seconds a feed is given
        /// would kill a four-hundred-token answer from a large model over
        /// Wi-Fi. The number the reader waits on is the deadline of the pass
        /// they are in, not this.
        var timeout: TimeInterval = 120
        var resourceTimeout: TimeInterval = 180
        /// A completion is kilobytes. Anything past this is a broken or hostile
        /// endpoint, and reading it all would be doing what it wanted.
        var maximumBytes = 1024 * 1024
    }

    private let session: URLSession
    private let throttle: HostThrottle
    private let limits: Limits
    private let redirects: RefusingRedirects

    init(session: URLSession? = nil, limits: Limits = Limits()) {
        self.limits = limits
        self.redirects = RefusingRedirects()

        // A bucket of its own, and never the fetcher's. That one is sized for
        // politeness towards publishers, one request a second, which would
        // serialize a night's filing behind a gate no publisher benefits from.
        // What is kept is the half that matters : a service that said to come
        // back later is left alone until then.
        self.throttle = HostThrottle(interval: 0, burst: 1)

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = limits.timeout
            configuration.timeoutIntervalForResource = limits.resourceTimeout
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration, delegate: redirects, delegateQueue: nil)
        }
    }

    /// Sends one request and reads what comes back, bounded.
    ///
    /// The status and the body are handed on rather than judged here : what a
    /// four hundred means is the wire format's to say, and the two formats say
    /// different things with the same number.
    func send(_ request: URLRequest) async throws(ModelFault) -> (status: Int, body: Data, retryAfter: TimeInterval?) {
        let host = request.url?.host() ?? ""

        // A service that asked to be left alone is left alone, which is the one
        // thing the bucket is kept for : one refusal during a pass of two
        // hundred stories would otherwise become two hundred of them.
        let wait = await throttle.wait(forHost: host)
        if wait > 0 {
            do {
                try await Task.sleep(for: .seconds(wait))
            } catch {
                throw .unusable(.cancelled)
            }
        }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw ModelFault.unusable(.unreachable) }

            let retryAfter = FeedFetcher.retryAfter(response.value(forHTTPHeaderField: "Retry-After"))
            if response.statusCode == 429 || response.statusCode == 529 || response.statusCode == 503 {
                await throttle.pause(host: host, until: Date().addingTimeInterval(retryAfter ?? 60))
            }

            if response.expectedContentLength > Int64(limits.maximumBytes) { throw ModelFault.unreadable }

            var body = Data()
            body.reserveCapacity(16 * 1024)
            for try await byte in bytes {
                body.append(byte)
                if body.count > limits.maximumBytes { throw ModelFault.unreadable }
            }

            return (response.statusCode, body, retryAfter)
        } catch let fault as ModelFault {
            throw fault
        } catch let error as URLError where error.code == .cancelled {
            throw .unusable(.cancelled)
        } catch let error as URLError where FeedFetcher.wasNeverSent(error) {
            throw .unusable(.unreachable)
        } catch {
            // The address of a provider may itself be a secret, and a service is
            // free to put anything in its own error : what is logged is the
            // kind of failure and never the address, the body or the key.
            Log.enrich.error("A model could not be reached : \(error.localizedDescription, privacy: .public)")
            throw .unusable(.unreachable)
        }
    }
}

/// Refuses a redirect that would carry a key somewhere else.
///
/// **`URLSession` strips `Authorization` when the origin changes and leaves
/// every other header alone.** Anthropic's key is in `x-api-key`, and a reader
/// may add headers of their own : a gateway that answers a redirect to a host
/// of its choosing would be handed the key by the system, silently, on the
/// second request. A misconfiguration does it by accident and a hostile
/// endpoint does it on purpose, and the two look the same from here.
///
/// So a redirect that changes host, or that steps down from `https` to `http`,
/// is not followed. What comes back instead is the redirect itself, which the
/// wire format reads as a service answering something it cannot use.
nonisolated final class RefusingRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let from = task.originalRequest?.url, let to = request.url else {
            completionHandler(nil)
            return
        }

        let sameHost = from.host()?.lowercased() == to.host()?.lowercased()
        let staysEncrypted = from.scheme?.lowercased() != "https" || to.scheme?.lowercased() == "https"

        guard sameHost, staysEncrypted else {
            Log.enrich.notice("A model service redirected somewhere else, so the request was not followed")
            completionHandler(nil)
            return
        }

        completionHandler(request)
    }
}
