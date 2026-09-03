//
//  ServiceImportTests.swift
//  FlongTests
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import Testing

@testable import Flong

@Suite("Importing a FreshRSS account", .serialized)
struct ServiceImportTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let articles: ArticleStore
    private let jobs: ImportJobStore
    private let service: ServiceImport
    private let credentials = MemoryCredentials()
    private let server = StubServer(host: "rss.example.com")

    init() throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
        articles = ArticleStore(database)
        jobs = ImportJobStore(database)
        service = ServiceImport(database)
    }

    // MARK: - Where the API is

    @Test("Every spelling of an instance reaches the same API")
    func endpoints() {
        let expected = "https://rss.example.com/api/greader.php"

        #expect(GoogleReader.base(of: "rss.example.com")?.absoluteString == expected)
        #expect(GoogleReader.base(of: "https://rss.example.com")?.absoluteString == expected)
        #expect(GoogleReader.base(of: "https://rss.example.com/")?.absoluteString == expected)
        #expect(GoogleReader.base(of: "  https://rss.example.com/i/  ")?.absoluteString == expected)
        #expect(GoogleReader.base(of: "https://rss.example.com/i/index.php?a=normal")?.absoluteString == expected)
        #expect(GoogleReader.base(of: "https://rss.example.com/api/greader.php")?.absoluteString == expected)

        // An installation under a path keeps it : `/FreshRSS/p/` is where
        // somebody put it, and only `i` and `api` are ever dropped.
        #expect(
            GoogleReader.base(of: "https://example.com/FreshRSS/p/i/")?.absoluteString
                == "https://example.com/FreshRSS/p/api/greader.php"
        )
        // What is typed with a scheme keeps it : a server on somebody's own
        // network is theirs to spell.
        #expect(
            GoogleReader.base(of: "http://box.local:8080")?.absoluteString == "http://box.local:8080/api/greader.php")

        #expect(GoogleReader.base(of: "") == nil)
        #expect(GoogleReader.base(of: "ftp://rss.example.com") == nil)
    }

    // MARK: - What the service answers

    @Test("An article is read out of the shape FreshRSS serializes")
    func decodingAnArticle() throws {
        let page = try JSONDecoder().decode(GoogleReaderPage.self, from: Data(Self.starredPage.utf8))
        let item = try #require(page.items.first)

        #expect(item.title == "A kept piece")
        #expect(item.link?.absoluteString == "https://example.com/kept")
        #expect(item.author == "A. Writer")
        // `published` arrives as a number here and as a string elsewhere, and
        // both are read.
        #expect(item.publishedAt == Date(timeIntervalSince1970: 1_756_000_000))
        // Compatibility mode puts the body in `summary` and sends no `content`.
        #expect(item.bodyHTML == "<p>Kept for later.</p>")
        #expect(item.isRead)
        #expect(item.isStarred)
        #expect(item.attachments.first?.url.absoluteString == "https://example.com/kept.mp3")
        // A length written as a string is still a length.
        #expect(item.attachments.first?.length == 4096)
        #expect(page.continuation == nil)
    }

    @Test("A page with no state on an article is neither read nor starred")
    func plainArticle() throws {
        let page = try JSONDecoder().decode(GoogleReaderPage.self, from: Data(Self.feedPage.utf8))
        let item = try #require(page.items.first)

        #expect(!item.isRead)
        #expect(!item.isStarred)
        #expect(page.continuation == "1755000000000000")
    }

    // MARK: - The whole of it

    @Test("The import takes what was ticked, its articles, and its favourites")
    func importing() async throws {
        // A source already followed, under a name the reader gave it, so the
        // merge can be checked against something they decided.
        let already = try await subscriptions.subscribe(
            to: try Subscription(address: "https://example.org/feed", title: "My own name")
        )

        server.install { request in Self.answer(to: request) }
        defer { server.reset() }

        let client = try await GoogleReaderClient.signIn(
            to: server.url.absoluteString,
            username: "alice",
            password: "s3cret",
            session: server.makeSession()
        )

        let listed = try await client.subscriptions()
        #expect(listed.count == 3)

        // Everything but the third, which is the one whose favourite has to be
        // counted and left.
        let job = try await service.begin(
            account: client.account,
            password: "s3cret",
            listed: listed,
            chosen: ["feed/1", "feed/2"],
            depth: .everything,
            wantsArticles: true,
            wantsFavourites: true,
            credentials: credentials
        )

        let report = try await service.run(job, using: client)

        #expect(report.isComplete)
        #expect(report.added == 1)
        #expect(report.merged == 1)
        #expect(report.skipped.isEmpty)

        // A source already followed keeps the name the reader gave it : an
        // import completes what is there and never overwrites it.
        let feeds = try await subscriptions.feeds()
        #expect(feeds.count == 2)
        #expect(try await subscriptions.feed(id: already.feed.id)?.title == "My own name")

        // Two pages of one feed, one page of the other, and one more the
        // starred stream held that neither page carried.
        #expect(report.articles == 4)
        #expect(report.favourites == 2)
        // The favourite of the source nobody ticked has nowhere to go.
        #expect(report.favouritesElsewhere == 1)

        let stored = try await database.writer.read { db in try Entry.order(Column("guid")).fetchAll(db) }
        #expect(stored.count == 4)
        #expect(stored.filter(\.isStarred).count == 2)
        // The read state travels with the article, from the categories and
        // from nowhere else.
        #expect(stored.filter(\.isRead).count == 2)

        // The identity guessed for an imported article is the address it lives
        // at, which is what the same article's own feed almost always states.
        #expect(stored.map(\.guid).contains("https://example.com/first"))

        // The row and the secret are the caller's to take away, once it has
        // settled what the import brought : `run` says the import is over and
        // never decides that for it.
        #expect(try await jobs.job() != nil)
        try await service.finish(job, credentials: credentials)
        #expect(try await jobs.job() == nil)
        #expect(try credentials.credential(for: job.id) == nil)
    }

    @Test("A favourite is never allowed to mark a read article unread")
    func statesAreAUnion() async throws {
        server.install { request in Self.answer(to: request) }
        defer { server.reset() }

        let client = try await GoogleReaderClient.signIn(
            to: server.url.absoluteString,
            username: "alice",
            password: "s3cret",
            session: server.makeSession()
        )

        let listed = try await client.subscriptions()
        let job = try await service.begin(
            account: client.account,
            password: "s3cret",
            listed: listed,
            chosen: ["feed/1"],
            depth: .everything,
            wantsArticles: true,
            wantsFavourites: false,
            credentials: credentials
        )
        _ = try await service.run(job, using: client)

        // The reader read one here that the account holds as unread.
        let unreadOnTheServer = try await database.writer.read { db in
            try Entry.filter(Column("guid") == "https://example.com/second").fetchOne(db)
        }
        let id = try #require(unreadOnTheServer?.id)
        try await articles.setRead([id], to: true)

        // Running the same import again brings the same page back, and what
        // the reader did to the article is theirs.
        let again = try await service.begin(
            account: client.account,
            password: "s3cret",
            listed: listed,
            chosen: ["feed/1"],
            depth: .everything,
            wantsArticles: true,
            wantsFavourites: false,
            credentials: credentials
        )
        let report = try await service.run(again, using: client)

        // Idempotent : the second run adds nothing.
        #expect(report.articles == 0)
        #expect(try await database.writer.read { db in try Entry.fetchCount(db) } == 2)
        #expect(try await subscriptions.feed(at: "https://example.com/feed") != nil)

        let after = try await database.writer.read { db in try Entry.fetchOne(db, key: id) }
        #expect(after?.isRead == true)
    }

    @Test("An import stopped part way carries on from where it was")
    func resuming() async throws {
        let refuses = Locked(true)
        server.install { request in
            // The second source is refused the first time round, which is what
            // an import stopping in the middle actually looks like.
            if request.url.path().contains("/stream/contents/feed/2"), refuses.value {
                return StubResponse(statusCode: 503)
            }
            return Self.answer(to: request)
        }
        defer { server.reset() }

        let client = try await GoogleReaderClient.signIn(
            to: server.url.absoluteString,
            username: "alice",
            password: "s3cret",
            session: server.makeSession()
        )
        let listed = try await client.subscriptions()

        let job = try await service.begin(
            account: client.account,
            password: "s3cret",
            listed: listed,
            chosen: ["feed/1", "feed/2"],
            depth: .everything,
            wantsArticles: true,
            wantsFavourites: true,
            credentials: credentials
        )

        await #expect(throws: ServiceError.self) {
            try await service.run(job, using: client)
        }

        // What the first source served is in, the row saying where it got to is
        // on disk, and the password that reopens the session is in the keychain.
        let standing = try #require(try await jobs.job())
        #expect(standing.tookSubscriptions)
        #expect(try await database.writer.read { db in try Entry.fetchCount(db) } == 2)
        #expect(try service.password(of: standing, credentials: credentials) == "s3cret")

        refuses.write { $0 = false }
        let report = try await service.run(standing, using: client)

        #expect(report.isComplete)
        // The two the first run brought are counted, and not fetched again.
        #expect(report.articles == 4)
        #expect(report.favourites == 2)
        #expect(try await database.writer.read { db in try Entry.fetchCount(db) } == 4)

        try await service.finish(standing, credentials: credentials)
        #expect(try await jobs.job() == nil)
        #expect(try credentials.credential(for: job.id) == nil)
    }

    @Test("How much of each source to bring is honoured")
    func depth() {
        #expect(ImportDepth.hundred.limit == 100)
        #expect(ImportDepth.fiveHundred.limit == 500)
        #expect(ImportDepth.everything.limit == nil)
    }

    // MARK: - The server this suite talks to

    /// One instance holding three subscriptions, one of which the reader does
    /// not take, and two articles they starred.
    private static func answer(to request: RecordedRequest) -> StubResponse {
        let path = request.url.path()

        if path.hasSuffix("/accounts/ClientLogin") {
            guard request.formValue("Passwd") == "s3cret" else { return StubResponse(statusCode: 401) }
            return .text("SID=alice/token\nLSID=null\nAuth=alice/token\n")
        }

        if path.hasSuffix("/reader/api/0/subscription/list") {
            return .json(subscriptionList)
        }

        if path.contains("/stream/contents/feed/1") {
            // Two pages, so pagination and the resume point are both exercised.
            return .json(request.query("c") == nil ? feedPage : feedSecondPage)
        }
        if path.contains("/stream/contents/feed/2") {
            return .json(otherFeedPage)
        }
        if path.contains("/stream/contents/user/-/state/com.google/starred") {
            return .json(starredPage)
        }

        return StubResponse(statusCode: 404)
    }

    private static let subscriptionList = """
        {"subscriptions": [
          {"id": "feed/1", "title": "Example", "url": "https://example.com/feed",
           "htmlUrl": "https://example.com", "categories": [{"id": "user/-/label/News", "label": "News"}]},
          {"id": "feed/2", "title": "Renamed by the service", "url": "https://example.org/feed",
           "htmlUrl": "https://example.org", "categories": []},
          {"id": "feed/3", "title": "Not taken", "url": "https://example.net/feed", "categories": []}
        ]}
        """

    private static let feedPage = """
        {"id": "feed/1", "continuation": "1755000000000000", "items": [
          {"id": "tag:google.com,2005:reader/item/0000000000000001",
           "title": "The first piece", "published": 1756000001,
           "canonical": [{"href": "https://example.com/first"}],
           "origin": {"streamId": "feed/1", "title": "Example"},
           "summary": {"content": "<p>The first.</p>"},
           "categories": ["user/-/state/com.google/reading-list"]}
        ]}
        """

    private static let feedSecondPage = """
        {"id": "feed/1", "items": [
          {"id": "tag:google.com,2005:reader/item/0000000000000002",
           "title": "The second piece", "published": "1755000001",
           "alternate": [{"href": "https://example.com/second"}],
           "origin": {"streamId": "feed/1", "title": "Example"},
           "summary": {"content": "<p>The second.</p>"},
           "categories": ["user/-/state/com.google/reading-list"]}
        ]}
        """

    private static let otherFeedPage = """
        {"id": "feed/2", "items": [
          {"id": "tag:google.com,2005:reader/item/0000000000000003",
           "title": "Elsewhere", "published": 1756000003,
           "canonical": [{"href": "https://example.org/elsewhere"}],
           "origin": {"streamId": "feed/2", "title": "Renamed by the service"},
           "summary": {"content": "<p>Elsewhere.</p>"},
           "categories": ["user/-/state/com.google/reading-list",
                          "user/-/state/com.google/read"]}
        ]}
        """

    /// Three starred articles : two of sources the reader took, one of the
    /// source they left behind.
    private static let starredPage = """
        {"id": "user/-/state/com.google/starred", "items": [
          {"id": "tag:google.com,2005:reader/item/0000000000000001",
           "title": "A kept piece", "author": "A. Writer", "published": 1756000000,
           "canonical": [{"href": "https://example.com/kept"}],
           "origin": {"streamId": "feed/1", "title": "Example"},
           "summary": {"content": "<p>Kept for later.</p>"},
           "enclosure": [{"href": "https://example.com/kept.mp3", "type": "audio/mpeg", "length": "4096"}],
           "categories": ["user/-/state/com.google/reading-list",
                          "user/-/state/com.google/read",
                          "user/-/state/com.google/starred"]},
          {"id": "tag:google.com,2005:reader/item/0000000000000003",
           "title": "Elsewhere", "published": 1756000003,
           "canonical": [{"href": "https://example.org/elsewhere"}],
           "origin": {"streamId": "feed/2", "title": "Renamed by the service"},
           "summary": {"content": "<p>Elsewhere.</p>"},
           "categories": ["user/-/state/com.google/starred"]},
          {"id": "tag:google.com,2005:reader/item/0000000000000009",
           "title": "From a source nobody took", "published": 1756000009,
           "canonical": [{"href": "https://example.net/left"}],
           "origin": {"streamId": "feed/3", "title": "Not taken"},
           "summary": {"content": "<p>Left behind.</p>"},
           "categories": ["user/-/state/com.google/starred"]}
        ]}
        """
}
