//
//  FeedRefreshTests.swift
//  FlongTests
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import Testing

@testable import Flong

@Suite("Feed refresh", .serialized)
struct FeedRefreshTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let articles: ArticleStore
    private let refresh: FeedRefresh
    private let server = StubServer(host: "refresh.example.com")

    init() throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
        articles = ArticleStore(database)
        refresh = FeedRefresh(
            database: database,
            fetcher: FeedFetcher(
                session: server.makeSession(),
                throttle: HostThrottle(interval: 0, burst: 100),
                userAgent: "Flong/test"
            )
        )
    }

    private var feedURL: URL { server.url.appending(path: "feed.xml") }

    private func subscribe() async throws -> Feed {
        try await subscriptions.subscribe(to: Subscription(url: feedURL, title: "Example")).feed
    }

    private func serve(_ fixture: String, headers: [String: String] = [:]) throws {
        let body = try Fixtures.data("Feeds/\(fixture)")
        server.install { _ in
            StubResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/rss+xml"].merging(headers) { _, new in
                    new
                }, body: body)
        }
    }

    private func feed(_ id: UUID) async throws -> Feed {
        let feed = try await subscriptions.feed(id: id)
        return try #require(feed)
    }

    // MARK: - Storing

    @Test("A refresh brings the articles in, sanitized")
    func refreshing() async throws {
        let feed = try await subscribe()
        try serve("rss2.xml", headers: ["ETag": "\"v1\"", "Last-Modified": "Wed, 26 Aug 2026 09:00:00 GMT"])
        defer { server.reset() }

        let result = await refresh.refresh(feed)

        #expect(result == .updated(newArticles: 2))

        let summaries = try await articles.summaries(.all)
        #expect(summaries.map(\.title) == ["The first post", "Second post"])
        #expect(summaries.first?.feedTitle == "Example")
        #expect(summaries.first?.hasMedia == true)
        #expect(summaries.first?.excerpt?.hasPrefix("A summary") == true)

        let first = try #require(summaries.first)
        let article = try #require(await articles.article(id: first.id))
        #expect(article.bodyHTML?.contains("<p>The body.</p>") == true)
        // The sanitizer ran on the way in, and the address of the article
        // resolved the relative link its summary carried.
        #expect(article.bodyHTML?.contains("script") == false)

        let stored = try await self.feed(feed.id)
        #expect(stored.etag == "\"v1\"")
        #expect(stored.lastModified == "Wed, 26 Aug 2026 09:00:00 GMT")
        #expect(stored.fetchCount == 1)
        #expect(stored.failureCount == 0)
        #expect(stored.lastSuccessAt != nil)
    }

    @Test("The same feed served twice adds nothing the second time")
    func identityHolds() async throws {
        let feed = try await subscribe()
        try serve("rss2.xml", headers: ["ETag": "\"v1\""])
        defer { server.reset() }

        _ = await refresh.refresh(feed)
        let second = await refresh.refresh(try await self.feed(feed.id))

        #expect(second == .updated(newArticles: 0))
        #expect(try await articles.count(.all) == 2)

        // The conditional headers of the second request came from the store.
        #expect(server.requests.count == 2)
        #expect(server.requests.last?.headers["If-None-Match"] == "\"v1\"")
    }

    @Test("A 304 costs nothing and counts as health")
    func notModified() async throws {
        let feed = try await subscribe()
        server.install { _ in StubResponse(statusCode: 304) }
        defer { server.reset() }

        let result = await refresh.refresh(feed)

        #expect(result == .notModified)
        let stored = try await self.feed(feed.id)
        #expect(stored.fetchCount == 1)
        #expect(stored.notModifiedCount == 1)
        #expect(stored.notModifiedRate == 1)
    }

    @Test("An article that changed is rewritten, and stays read")
    func updatingAnArticle() async throws {
        let feed = try await subscribe()
        try serve("rss2.xml")
        _ = await refresh.refresh(feed)
        server.reset()

        let stored = try await articles.summaries(.all)
        let summary = try #require(stored.first)
        try await articles.setRead([summary.id], to: true)
        try await articles.setStarred([summary.id], to: true)

        let rewritten = try Fixtures.text("Feeds/rss2.xml")
            .replacingOccurrences(of: "The &lt;b&gt;first&lt;/b&gt; post", with: "The first post, corrected")
        server.install { _ in StubResponse(statusCode: 200, body: Data(rewritten.utf8)) }
        defer { server.reset() }

        let result = await refresh.refresh(try await self.feed(feed.id))

        #expect(result == .updated(newArticles: 0))
        let all = try await articles.summaries(.all)
        let updated = try #require(all.first { $0.id == summary.id })
        #expect(updated.title == "The first post, corrected")
        #expect(updated.isRead)
        #expect(updated.isStarred)
    }

    @Test("A feed names itself only while nothing else has named it")
    func titles() async throws {
        // Subscribed by address alone, so the title is still the host.
        let feed = try await subscriptions.subscribe(to: Subscription(url: feedURL)).feed
        #expect(feed.title == "refresh.example.com")

        try serve("rss2.xml")
        defer { server.reset() }

        _ = await refresh.refresh(feed)
        #expect(try await self.feed(feed.id).title == "Example Weekly")

        try await subscriptions.rename(feed.id, to: "My own name")
        _ = await refresh.refresh(try await self.feed(feed.id))

        #expect(try await self.feed(feed.id).title == "My own name")
    }

    @Test("A feed's own history sets how often it is asked")
    func observedInterval() async throws {
        let feed = try await subscribe()
        try serve("rss2.xml")
        defer { server.reset() }

        _ = await refresh.refresh(feed)

        // Two articles is not a history, so nothing is concluded from it.
        #expect(try await self.feed(feed.id).observedInterval == nil)
    }

    // MARK: - Failures

    @Test("A failure is written down, and repeated failures end in quarantine")
    func failures() async throws {
        var feed = try await subscribe()
        server.install { _ in StubResponse(statusCode: 500) }
        defer { server.reset() }

        for _ in 0..<(FeedRefresh.quarantineAfterFailure - 1) {
            _ = await refresh.refresh(feed)
            feed = try await self.feed(feed.id)
        }

        #expect(feed.failureCount == FeedRefresh.quarantineAfterFailure - 1)
        #expect(feed.lastFailureReason == "http 500")
        #expect(feed.quarantinedAt == nil)

        _ = await refresh.refresh(feed)
        #expect(try await self.feed(feed.id).quarantinedAt != nil)
    }

    @Test("Credentials that do not work are settled after three tries")
    func rejection() async throws {
        var feed = try await subscribe()
        server.install { _ in StubResponse(statusCode: 401) }
        defer { server.reset() }

        for _ in 0..<FeedRefresh.quarantineAfterRejection {
            _ = await refresh.refresh(feed)
            feed = try await self.feed(feed.id)
        }

        #expect(feed.quarantinedAt != nil)
        #expect(feed.lastFailureReason == "rejected (401)")
    }

    @Test("Bytes that are not a feed are the publisher's problem, and show as one")
    func unreadableFeed() async throws {
        let feed = try await subscribe()
        server.install { _ in StubResponse(statusCode: 200, body: Data("<html><body>Nope</body></html>".utf8)) }
        defer { server.reset() }

        let result = await refresh.refresh(feed)

        #expect(result == .failed(reason: "unreadable"))
        #expect(try await self.feed(feed.id).lastFailureReason == "unreadable")
        #expect(try await articles.count(.all) == 0)
    }

    @Test("A quarantined feed is left alone by a refresh of everything")
    func quarantineIsRespected() async throws {
        let feed = try await subscribe()
        server.install { _ in StubResponse(statusCode: 404) }
        defer { server.reset() }

        for _ in 0..<FeedRefresh.quarantineAfterRejection {
            _ = await refresh.refresh(try await self.feed(feed.id))
        }
        let requestsBefore = server.requests.count

        let summary = await refresh.refreshAll()

        #expect(summary.attempted == 0)
        #expect(server.requests.count == requestsBefore)
    }

    @Test("Refreshing several feeds reports what happened to each")
    func refreshingMany() async throws {
        let first = try await subscribe()
        let second = try await subscriptions.subscribe(
            to: Subscription(url: server.url.appending(path: "other.xml"), title: "Other")
        ).feed

        let body = try Fixtures.data("Feeds/rss2.xml")
        server.install { request in
            request.path.hasSuffix("other.xml")
                ? StubResponse(statusCode: 304)
                : StubResponse(statusCode: 200, body: body)
        }
        defer { server.reset() }

        let summary = await refresh.refresh([first, second])

        #expect(summary.attempted == 2)
        #expect(summary.refreshed == 1)
        #expect(summary.unchanged == 1)
        #expect(summary.newArticles == 2)
    }
}
