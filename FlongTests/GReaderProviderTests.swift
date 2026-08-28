//
//  GReaderProviderTests.swift
//  FlongTests
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

@Suite("GReader provider", .serialized)
struct GReaderProviderTests {
    private let server = StubServer(host: "provider.rss.example.com")

    private func makeProvider(authToken: String? = "alice/abc") -> GReaderProvider {
        GReaderProvider(
            serverURL: server.url,
            credentials: GReaderCredentials(username: "alice", password: "s3cret"),
            authToken: authToken,
            session: server.makeSession()
        )
    }

    // MARK: - Wire to model

    /// `tag/list` mixes built-in states, which carry no type, folders typed
    /// `folder`, and article labels typed `tag`. Folders and labels share the
    /// same prefix, so only the type separates them.
    @Test("Only folders are kept out of the tag list")
    func mapFolders() {
        let tags = [
            GReaderDTO.Tag(id: "user/-/state/com.google/starred", type: nil, unreadCount: nil),
            GReaderDTO.Tag(id: "user/-/state/com.google/reading-list", type: nil, unreadCount: nil),
            GReaderDTO.Tag(id: "user/-/label/News", type: "folder", unreadCount: nil),
            GReaderDTO.Tag(id: "user/-/label/To read", type: "tag", unreadCount: LooseInt(3)),
        ]

        let folders = GReaderProvider.mapFolders(tags)
        #expect(folders.count == 1)
        #expect(folders.first?.id == "user/-/label/News")
        #expect(folders.first?.name == "News")
    }

    @Test("A subscription keeps its numeric identifier and both URLs")
    func mapFeed() {
        let feed = GReaderProvider.mapFeed(
            GReaderDTO.Subscription(
                id: "feed/42",
                title: "Example",
                url: "https://example.com/rss.xml",
                htmlUrl: "https://example.com",
                iconUrl: "https://rss.example.com/f.ico",
                categories: [GReaderDTO.SubscriptionCategory(id: "user/-/label/News", label: "News")]
            )
        )

        #expect(feed.id == "feed/42")
        #expect(feed.title == "Example")
        #expect(feed.feedURL?.absoluteString == "https://example.com/rss.xml")
        #expect(feed.siteURL?.absoluteString == "https://example.com")
        #expect(feed.folderIDs == ["user/-/label/News"])
    }

    @Test("A subscription without a title falls back to its site")
    func mapFeedWithoutTitle() {
        let feed = GReaderProvider.mapFeed(
            GReaderDTO.Subscription(
                id: "feed/42", title: "  ", url: nil, htmlUrl: "https://example.com", iconUrl: nil, categories: nil
            )
        )
        #expect(feed.title == "https://example.com")
        #expect(feed.folderIDs.isEmpty)
    }

    @Test("States are read off the categories array")
    func mapArticleStates() {
        let item = GReaderDTO.Item(
            id: "tag:google.com,2005:reader/item/000000000004c608",
            title: "Hello",
            author: "Alice",
            published: LooseInt(1_700_000_000),
            updated: nil,
            crawlTimeMsec: "1700000000000",
            timestampUsec: "1700000000000000",
            summary: GReaderDTO.ItemContent(content: "<p>Body</p>"),
            content: nil,
            canonical: [GReaderDTO.Link(href: "https://example.com/a")],
            alternate: nil,
            categories: [
                "user/-/state/com.google/reading-list",
                "user/-/label/News",
                "user/-/state/com.google/read",
                "user/-/state/com.google/starred",
            ],
            origin: GReaderDTO.Origin(streamId: "feed/42", title: "Example", htmlUrl: "https://example.com")
        )

        let article = GReaderProvider.mapArticle(item)
        #expect(article.feedID == "feed/42")
        #expect(article.title == "Hello")
        #expect(article.author == "Alice")
        #expect(article.summary == "<p>Body</p>")
        #expect(article.url?.absoluteString == "https://example.com/a")
        #expect(article.published == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(article.isRead)
        #expect(article.isStarred)
    }

    /// FreshRSS omits `published` on some entries, and never sends `updated`, so
    /// the microsecond crawl date is the fallback.
    @Test("A missing publication date falls back to the crawl date")
    func mapArticleWithoutPublishedDate() {
        let item = GReaderDTO.Item(
            id: "tag:google.com,2005:reader/item/1", title: nil, author: nil, published: nil, updated: nil,
            crawlTimeMsec: nil, timestampUsec: "1700000000000000", summary: nil, content: nil,
            canonical: nil, alternate: [GReaderDTO.Link(href: "https://example.com/b")],
            categories: nil, origin: nil
        )

        let article = GReaderProvider.mapArticle(item)
        #expect(article.published == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(article.url?.absoluteString == "https://example.com/b")
        #expect(article.title.isEmpty)
        #expect(!article.isRead)
    }

    // MARK: - Requests

    @Test("Reading a stream asks for JSON and a page size")
    func articlesRequest() async throws {
        server.install { _ in .json(#"{"items": []}"#) }
        defer { server.reset() }

        _ = try await makeProvider().articles(in: .all, unreadOnly: false, limit: 50, continuation: nil)

        let request = try #require(server.requests.first)
        #expect(request.path == "/api/greader.php/reader/api/0/stream/contents/user/-/state/com.google/reading-list")
        #expect(request.query("output") == "json")
        #expect(request.query("n") == "50")
        #expect(request.query("xt") == nil)
    }

    @Test("Reading unread only excludes the read state")
    func articlesUnreadOnly() async throws {
        server.install { _ in .json(#"{"items": []}"#) }
        defer { server.reset() }

        _ = try await makeProvider().articles(
            in: .folder(id: "user/-/label/News"), unreadOnly: true, limit: 20, continuation: nil
        )

        let request = try #require(server.requests.first)
        #expect(request.path == "/api/greader.php/reader/api/0/stream/contents/user/-/label/News")
        #expect(request.query("xt") == "user/-/state/com.google/read")
    }

    /// The server resets a continuation that is not all digits, silently
    /// restarting the stream, so a malformed one is dropped before sending.
    @Test("Only a numeric continuation is forwarded")
    func continuationHandling() async throws {
        server.install { _ in .json(#"{"items": []}"#) }
        defer { server.reset() }

        let provider = makeProvider()
        _ = try await provider.articles(in: .all, unreadOnly: false, limit: 20, continuation: "1755000000000000")
        _ = try await provider.articles(in: .all, unreadOnly: false, limit: 20, continuation: "not-a-number")

        let requests = server.requests
        #expect(requests[0].query("c") == "1755000000000000")
        #expect(requests[1].query("c") == nil)
    }

    @Test("A page carries its continuation back")
    func articlesPagination() async throws {
        server.install { _ in .json(#"{"items": [], "continuation": "1755000000000000"}"#) }
        defer { server.reset() }

        let page = try await makeProvider().articles(in: .all, unreadOnly: false, limit: 20, continuation: nil)
        #expect(page.continuation == "1755000000000000")
    }

    @Test("Unread counts are keyed by feed and by folder")
    func unreadCounts() async throws {
        server.install { _ in
            .json(
                """
                {"max": 5, "unreadcounts": [
                  {"id": "feed/42", "count": 3, "newestItemTimestampUsec": "1700000000000000"},
                  {"id": "user/-/label/News", "count": 5, "newestItemTimestampUsec": "1700000000000000"},
                  {"id": "user/-/state/com.google/reading-list", "count": 5, "newestItemTimestampUsec": "0"}
                ]}
                """
            )
        }
        defer { server.reset() }

        let counts = try await makeProvider().unreadCounts()
        #expect(counts["feed/42"] == 3)
        #expect(counts["user/-/label/News"] == 5)
        #expect(counts["user/-/state/com.google/reading-list"] == 5)
    }

    // MARK: - Writes

    @Test("Marking as read adds the read state to every identifier")
    func setRead() async throws {
        server.install { request in
            request.path.hasSuffix("/token") ? .text("tok\n") : .text("OK")
        }
        defer { server.reset() }

        try await makeProvider().setRead(true, articleIDs: ["item/1", "item/2"])

        let write = try #require(server.requests.last)
        #expect(write.path == "/api/greader.php/reader/api/0/edit-tag")
        #expect(write.formValues("i") == ["item/1", "item/2"])
        #expect(write.formValue("a") == "user/-/state/com.google/read")
        #expect(write.formValue("r") == nil)
    }

    @Test("Marking as unread removes the read state instead")
    func setUnread() async throws {
        server.install { request in
            request.path.hasSuffix("/token") ? .text("tok\n") : .text("OK")
        }
        defer { server.reset() }

        try await makeProvider().setRead(false, articleIDs: ["item/1"])

        let write = try #require(server.requests.last)
        #expect(write.formValue("r") == "user/-/state/com.google/read")
        #expect(write.formValue("a") == nil)
    }

    @Test("An empty selection makes no request at all")
    func setReadWithNoArticles() async throws {
        server.install { _ in .text("OK") }
        defer { server.reset() }

        try await makeProvider().setStarred(true, articleIDs: [])
        #expect(server.requests.isEmpty)
    }

    /// PHP drops input fields past `max_input_vars`, so a large selection is
    /// split rather than silently truncated by the server.
    @Test("A large selection is split into batches")
    func editTagBatching() async throws {
        server.install { request in
            request.path.hasSuffix("/token") ? .text("tok\n") : .text("OK")
        }
        defer { server.reset() }

        let identifiers = (0..<250).map { "item/\($0)" }
        try await makeProvider().setRead(true, articleIDs: identifiers)

        let writes = server.requests.filter { $0.path.hasSuffix("/edit-tag") }
        #expect(writes.count == 3)
        #expect(writes[0].formValues("i").count == 100)
        #expect(writes[2].formValues("i").count == 50)
    }

    /// The server compares `ts` against article identifiers, which are insertion
    /// dates in microseconds. Any other unit marks the wrong set of articles.
    @Test("Mark all as read sends the cutoff in microseconds")
    func markAllReadUnit() async throws {
        server.install { request in
            request.path.hasSuffix("/token") ? .text("tok\n") : .text("OK")
        }
        defer { server.reset() }

        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        try await makeProvider().markAllRead(in: .feed(id: "feed/42"), olderThan: cutoff)

        let write = try #require(server.requests.last)
        #expect(write.path == "/api/greader.php/reader/api/0/mark-all-as-read")
        #expect(write.formValue("s") == "feed/42")
        #expect(write.formValue("ts") == "1700000000000000")
    }

    // MARK: - Session recovery

    @Test("A refused token triggers a new sign in and one replay")
    func replaysAfterReauthentication() async throws {
        let attempts = Counter()
        server.install { request in
            if request.path.hasSuffix("/ClientLogin") {
                return .text("Auth=alice/renewed")
            }
            return attempts.next() == 0 ? .json("", status: 401) : .json(#"{"subscriptions": []}"#)
        }
        defer { server.reset() }

        let feeds = try await makeProvider().feeds()
        #expect(feeds.isEmpty)

        let paths = server.requests.map(\.path)
        #expect(paths.filter { $0.hasSuffix("/ClientLogin") }.count == 1)
        #expect(paths.filter { $0.hasSuffix("/subscription/list") }.count == 2)
    }

    @Test("Without a cached token, the session is opened first")
    func signsInWhenNoTokenIsCached() async throws {
        server.install { request in
            request.path.hasSuffix("/ClientLogin")
                ? .text("Auth=alice/fresh") : .json(#"{"subscriptions": []}"#)
        }
        defer { server.reset() }

        _ = try await makeProvider(authToken: nil).feeds()

        let paths = server.requests.map(\.path)
        #expect(paths.first?.hasSuffix("/ClientLogin") == true)
    }
}

/// Counts stub invocations across the concurrent calls a session replay makes.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            defer { value += 1 }
            return value
        }
    }
}
