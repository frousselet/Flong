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

    @Test("The same article from two feeds of one newsroom is read once")
    func duplicates() async throws {
        // Two desks of one paper, both running the piece.
        var feeds: [Feed] = []
        for desk in ["societe", "politique"] {
            let url = server.url.appending(path: "\(desk).xml")
            feeds.append(try await subscriptions.subscribe(to: Subscription(url: url, title: desk)).feed)
        }

        let body = Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel>
              <title>Le Quotidien</title><link>https://refresh.example.com/</link><description>d</description>
              <item>
                <title>L'interdiction des téléphones au lycée</title>
                <link>https://refresh.example.com/2026/telephones.php?utm_source=rss</link>
                <guid>urn:example:desk:1</guid>
                <description>Le gouvernement annonce la mesure.</description>
              </item>
            </channel></rss>
            """.utf8
        )
        server.install { _ in
            StubResponse(statusCode: 200, headers: ["Content-Type": "application/rss+xml"], body: body)
        }
        defer { server.reset() }

        for feed in feeds { _ = await refresh.refresh(feed) }

        let stored = try await database.writer.read { db in try Entry.fetchAll(db) }
        let summaries = try await articles.summaries(.all)

        // Both rows are kept : each belongs to a feed the reader follows, and
        // unsubscribing from one must take its own row away.
        #expect(stored.count == 2)
        #expect(stored.filter { $0.duplicateOf != nil }.count == 1)
        // The reader sees it once.
        #expect(summaries.count == 1)
        #expect(try await articles.count(.unread) == 1)
    }

    @Test("A feed that renumbers its own articles still delivers them once")
    func duplicatesWithinOneFeed() async throws {
        let feed = try await subscribe()

        // The same article, twice in one document, under two identifiers : a
        // feed whose builder renumbers everything it emits.
        let body = Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel>
              <title>Libération</title><link>https://refresh.example.com/</link><description>d</description>
              <item>
                <title>Sophie Binet accuse une partie du patronat</title>
                <link>https://refresh.example.com/2026/binet-patronat</link>
                <guid>urn:example:build-1</guid>
              </item>
              <item>
                <title>Sophie Binet accuse une partie du patronat</title>
                <link>https://refresh.example.com/2026/binet-patronat?utm_source=rss</link>
                <guid>urn:example:build-2</guid>
              </item>
            </channel></rss>
            """.utf8
        )
        server.install { _ in
            StubResponse(statusCode: 200, headers: ["Content-Type": "application/rss+xml"], body: body)
        }
        defer { server.reset() }

        _ = await refresh.refresh(feed)

        let rows = try await database.writer.read { db in try Entry.fetchCount(db) }
        #expect(rows == 2)
        #expect(try await articles.summaries(.all).count == 1)
    }

    @Test("An article arrives with the picture that stands for it")
    func covers() async throws {
        let feed = try await subscribe()
        try serve("covers.xml")
        defer { server.reset() }

        _ = await refresh.refresh(feed)

        let summaries = try await articles.summaries(.all)
        let covers = Dictionary(uniqueKeysWithValues: summaries.map { ($0.title, $0.imageURL?.absoluteString) })

        #expect(covers["Stated as a thumbnail"] == "https://example.com/covers/1.jpg")
        #expect(covers["Stated as media content"] == "https://example.com/covers/2.jpg")
        #expect(covers["Stated the podcast way"] == "https://example.com/covers/3.jpg")
        #expect(covers["Enclosed rather than stated"] == "https://example.com/media/4.png")

        // A thumbnail is not an attachment : only the podcast and the enclosed
        // picture are media, and only they wear the badge.
        let withMedia = summaries.filter(\.hasMedia).map(\.title).sorted()
        #expect(withMedia == ["Enclosed rather than stated", "Stated as media content", "Stated the podcast way"])
    }

    @Test("A feed that states no picture lends the first one in the body")
    func coverFromTheBody() async throws {
        let feed = try await subscribe()
        server.install { _ in
            StubResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/rss+xml"],
                body: Data(
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <rss version="2.0"><channel>
                      <title>Plain</title><link>https://example.com/</link><description>d</description>
                      <item>
                        <title>Illustrated in its body</title>
                        <link>https://example.com/posts/1</link>
                        <guid>urn:example:1</guid>
                        <description><![CDATA[
                          <p><img src="/pixel.gif" width="1" height="1"></p>
                          <p><img src="/badge.png" width="16"></p>
                          <figure><img src="/photo.jpg" width="1200"></figure>
                        ]]></description>
                      </item>
                    </channel></rss>
                    """.utf8))
        }
        defer { server.reset() }

        _ = await refresh.refresh(feed)

        let summary = try #require(try await articles.summaries(.all).first)

        // The tracking pixel is already gone by then, and the badge is too
        // small to be what the article is about.
        #expect(summary.imageURL?.absoluteString == "https://example.com/photo.jpg")
    }

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

    @Test("Ingesting an article writes out everybody its byline names")
    func theWritersAreIndexed() async throws {
        let feed = try await subscribe()
        let authors = AuthorStore(database)

        func serve(byline: String) {
            server.install { _ in
                StubResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml"],
                    body: Data(
                        """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
                          <channel><title>P</title><link>https://example.com/</link>
                            <item>
                              <title>Un titre</title><guid isPermaLink="false">urn:1</guid>
                              <dc:creator>\(byline)</dc:creator>
                            </item>
                          </channel>
                        </rss>
                        """.utf8
                    )
                )
            }
        }
        defer { server.reset() }

        // **End to end on purpose.** The people beside an article are written
        // by hand at each path that stores one, so a path that forgot would
        // leave its articles out of their own writers' pages and nothing else
        // would notice.
        serve(byline: "Claire Ancelin et Paul Rey")
        _ = await refresh.refresh(feed)
        #expect(try await authors.all().map(\.name) == ["Claire Ancelin", "Paul Rey"])

        // And again when the publisher rewrites it : the update path is the
        // second of the two, and a writer taken off a byline goes with it.
        serve(byline: "Claire Ancelin")
        _ = await refresh.refresh(try await self.feed(feed.id))
        #expect(try await authors.all().map(\.name) == ["Claire Ancelin"])
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

    // MARK: - What is not the publisher's fault

    @Test("A request the system would not send is not held against the feed")
    func neverSent() async throws {
        let feed = try await subscribe()
        // What any pass gets with cellular data switched off for Flong, and
        // what any pass gets with no network at all.
        server.install { _ in StubResponse.failing(.dataNotAllowed) }
        defer { server.reset() }

        let result = await refresh.refresh(feed)

        #expect(result == .skipped)

        // Nothing reached a server, so the feed's health says nothing about
        // it. Counting these was how a reader who spent two days tethered came
        // back to a shelf of quarantined feeds.
        let stored = try await self.feed(feed.id)
        #expect(stored.failureCount == 0)
        #expect(stored.lastFailureReason == nil)
        #expect(stored.quarantinedAt == nil)
        #expect(stored.lastFetchAt == nil)
    }

    @Test("Six passes over a network that will not carry them quarantine nothing")
    func neverSentNeverQuarantines() async throws {
        let feed = try await subscribe()
        server.install { _ in StubResponse.failing(.notConnectedToInternet) }
        defer { server.reset() }

        for _ in 0..<(FeedRefresh.quarantineAfterFailure + 1) {
            _ = await refresh.refresh(feed)
        }

        #expect(try await self.feed(feed.id).quarantinedAt == nil)
    }

    @Test("A pass that runs out of time says what it never got to")
    func deadline() async throws {
        var feeds: [Feed] = []
        for index in 0..<(FeedRefresh.concurrency + 4) {
            let url = server.url.appending(path: "f\(index).xml")
            feeds.append(try await subscriptions.subscribe(to: Subscription(url: url, title: "F\(index)")).feed)
        }

        server.install { _ in StubResponse(statusCode: 304) }
        defer { server.reset() }

        // A deadline already past : the first handful are already in flight and
        // are seen through, and nothing else is handed out.
        let summary = await refresh.refresh(feeds, until: Date().addingTimeInterval(-1))

        #expect(summary.attempted == FeedRefresh.concurrency)
        #expect(summary.skipped == 4)
        // What was in flight was finished rather than cut off, so every feed
        // the pass did reach is fully written down.
        #expect(summary.unchanged == FeedRefresh.concurrency)
    }

    // MARK: - Sleeping until a feed is due

    @Test("A feed nobody has fetched is due now, so nothing waits for it")
    func nextDueOnAFreshStore() async throws {
        _ = try await subscribe()

        let due = try #require(await refresh.nextDue())
        #expect(due <= Date())
    }

    @Test("The moment the earliest feed is due is what the clock sleeps until")
    func nextDueIsTheEarliest() async throws {
        try serve("rss2.xml")
        let feed = try await subscribe()
        _ = await refresh.refresh([feed])

        let fetched = try await self.feed(feed.id)
        let expected = try #require(RefreshSchedule.due(fetched, stagger: 0))

        let due = try #require(await refresh.nextDue())
        // The stagger is a share of the interval and is added on top, so the
        // moment can only be later than the bare one, never earlier.
        #expect(due >= expected)
        #expect(due <= expected.addingTimeInterval(RefreshSchedule.interval(of: fetched) / 3))
    }

    @Test("A store of nothing but quarantined feeds has no moment to wake for")
    func nextDueWithNothingToAsk() async throws {
        let feed = try await subscribe()
        try await database.writer.write { db in
            var stored = try #require(try Feed.fetchOne(db, key: feed.id))
            stored.quarantinedAt = Date()
            try stored.update(db)
        }

        #expect(await refresh.nextDue() == nil)
    }
}

@Suite("What a fetch counts as never having been sent")
struct NeverSentTests {
    @Test("A network the reader pays for, or no network at all")
    func refusals() {
        #expect(FeedFetcher.wasNeverSent(URLError(.dataNotAllowed)))
        #expect(FeedFetcher.wasNeverSent(URLError(.notConnectedToInternet)))
        #expect(FeedFetcher.wasNeverSent(URLError(.internationalRoamingOff)))
    }

    @Test("A server that answered badly is not one that was never asked")
    func actualFailures() {
        // These reached somebody, so they say something about the feed and
        // count towards its health.
        #expect(!FeedFetcher.wasNeverSent(URLError(.timedOut)))
        #expect(!FeedFetcher.wasNeverSent(URLError(.cannotFindHost)))
        #expect(!FeedFetcher.wasNeverSent(URLError(.badServerResponse)))
    }
}
