//
//  FeedFinderTests.swift
//  FlongTests
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

@Suite("Feed finder", .serialized)
struct FeedFinderTests {
    private let server = StubServer(host: "finder.example.com")

    private var finder: FeedFinder {
        FeedFinder(
            fetcher: FeedFetcher(
                session: server.makeSession(),
                throttle: HostThrottle(interval: 0, burst: 100),
                userAgent: "Flong/test"
            )
        )
    }

    @Test("An address that is already a feed is taken as it is")
    func directFeed() async throws {
        let feed = try Fixtures.data("Feeds/rss2.xml")
        server.install { _ in StubResponse(statusCode: 200, body: feed) }
        defer { server.reset() }

        let found = try await finder.find(at: "finder.example.com/feed.xml")

        #expect(found.url.absoluteString == "https://finder.example.com/feed.xml")
        #expect(found.title == "Example Weekly")
        #expect(server.requests.count == 1)
    }

    @Test("A page is asked where its feed is")
    func declaredFeed() async throws {
        let page = try Fixtures.data("Feeds/page.html")
        let feed = try Fixtures.data("Feeds/rss2.xml")
        server.install { request in
            request.path == "/feed.xml"
                ? StubResponse(statusCode: 200, body: feed)
                : StubResponse(statusCode: 200, headers: ["Content-Type": "text/html"], body: page)
        }
        defer { server.reset() }

        let found = try await finder.find(at: "https://finder.example.com/")

        #expect(found.url.absoluteString == "https://finder.example.com/feed.xml")
        #expect(found.title == "Example Weekly")
    }

    @Test("A page that declares nothing still has the usual locations tried")
    func guessedFeed() async throws {
        let feed = try Fixtures.data("Feeds/rss2.xml")
        server.install { request in
            switch request.path {
            case "/feed": StubResponse(statusCode: 200, body: feed)
            case "/":
                StubResponse(
                    statusCode: 200, headers: ["Content-Type": "text/html"],
                    body: Data("<html><head><title>Site</title></head><body>Hi</body></html>".utf8))
            default: StubResponse(statusCode: 404)
            }
        }
        defer { server.reset() }

        let found = try await finder.find(at: "https://finder.example.com/")

        #expect(found.url.absoluteString == "https://finder.example.com/feed")
    }

    @Test("A site with no feed anywhere says so")
    func noFeed() async throws {
        server.install { _ in
            StubResponse(statusCode: 200, headers: ["Content-Type": "text/html"], body: Data("<html></html>".utf8))
        }
        defer { server.reset() }

        await #expect(throws: FeedFinderError.noFeedFound) {
            try await finder.find(at: "https://finder.example.com/")
        }
    }

    @Test("An address that leads nowhere is told apart from one with no feed")
    func failures() async throws {
        server.install { _ in StubResponse(statusCode: 500) }
        defer { server.reset() }

        await #expect(throws: FeedFinderError.unreachable) {
            try await finder.find(at: "https://finder.example.com/")
        }
        await #expect(throws: FeedFinderError.invalidAddress(.unsupportedScheme("ftp"))) {
            try await finder.find(at: "ftp://finder.example.com/")
        }
    }
}
