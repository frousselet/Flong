//
//  StubURLProtocol.swift
//  FlongTests
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// A canned HTTP reply.
nonisolated struct StubResponse: Sendable {
    var statusCode = 200
    var headers: [String: String] = [:]
    var body = Data()
    /// The connection failing rather than answering.
    ///
    /// Some of what a fetch has to tell apart never reaches a status code : a
    /// request the system refuses to send at all, over a network the reader
    /// pays for or with no network there, arrives as a `URLError` and nothing
    /// else.
    var error: URLError.Code?

    static func failing(_ code: URLError.Code) -> StubResponse {
        StubResponse(error: code)
    }

    static func text(_ body: String, status: Int = 200) -> StubResponse {
        StubResponse(statusCode: status, headers: ["Content-Type": "text/plain"], body: Data(body.utf8))
    }

    static func json(_ body: String, status: Int = 200) -> StubResponse {
        StubResponse(statusCode: status, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }
}

/// A request as it reached the stub.
///
/// `URLProtocol` moves `httpBody` into `httpBodyStream`, so the body is drained
/// here once and kept as a string.
nonisolated struct RecordedRequest: Sendable {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: String

    init(_ request: URLRequest) {
        url = request.url ?? URL(string: "about:blank")!
        method = request.httpMethod ?? "GET"
        headers = request.allHTTPHeaderFields ?? [:]

        if let data = request.httpBody {
            body = String(decoding: data, as: UTF8.self)
        } else if let stream = request.httpBodyStream {
            var drained = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            stream.open()
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                drained.append(contentsOf: buffer[0..<read])
            }
            stream.close()
            body = String(decoding: drained, as: UTF8.self)
        } else {
            body = ""
        }
    }

    var path: String { url.path() }

    var queryItems: [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    func query(_ name: String) -> String? {
        queryItems.first { $0.name == name }?.value
    }

    /// Form fields in order, with repeats preserved.
    var formFields: [(name: String, value: String)] {
        body.split(separator: "&").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0].removingPercentEncoding ?? parts[0], parts[1].removingPercentEncoding ?? parts[1])
        }
    }

    func formValues(_ name: String) -> [String] {
        formFields.filter { $0.name == name }.map(\.value)
    }

    func formValue(_ name: String) -> String? {
        formValues(name).first
    }
}

/// Holds the handlers the stubbed protocol answers with, and records what it saw.
///
/// Entries are keyed by host so that suites running in parallel cannot observe
/// each other's traffic. Within a suite, `.serialized` keeps request order
/// meaningful.
nonisolated final class StubRegistry: @unchecked Sendable {
    static let shared = StubRegistry()

    private let lock = NSLock()
    private var handlers: [String: @Sendable (RecordedRequest) -> StubResponse] = [:]
    private var recorded: [String: [RecordedRequest]] = [:]

    func install(host: String, _ handler: @escaping @Sendable (RecordedRequest) -> StubResponse) {
        lock.withLock {
            handlers[host] = handler
            recorded[host] = []
        }
    }

    func reset(host: String) {
        lock.withLock {
            handlers[host] = nil
            recorded[host] = nil
        }
    }

    func record(_ request: RecordedRequest) {
        guard let host = request.url.host() else { return }
        lock.withLock { recorded[host, default: []].append(request) }
    }

    func respond(to request: RecordedRequest) -> StubResponse {
        guard let host = request.url.host() else { return StubResponse(statusCode: 500) }
        let handler = lock.withLock { handlers[host] }
        return handler?(request) ?? StubResponse(statusCode: 500)
    }

    func requests(host: String) -> [RecordedRequest] {
        lock.withLock { recorded[host] ?? [] }
    }
}

/// A stubbed server, addressed by its own host so each suite stays isolated.
nonisolated struct StubServer: Sendable {
    let url: URL
    let host: String

    init(host: String) {
        self.host = host
        self.url = URL(string: "https://\(host)")!
    }

    func install(_ handler: @escaping @Sendable (RecordedRequest) -> StubResponse) {
        StubRegistry.shared.install(host: host, handler)
    }

    func reset() {
        StubRegistry.shared.reset(host: host)
    }

    var requests: [RecordedRequest] {
        StubRegistry.shared.requests(host: host)
    }

    /// A session wired to the stub, with no cache and no cookie storage.
    func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

nonisolated final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let recorded = RecordedRequest(request)
        StubRegistry.shared.record(recorded)
        let stub = StubRegistry.shared.respond(to: recorded)

        if let code = stub.error {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }

        let response = HTTPURLResponse(
            url: recorded.url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
