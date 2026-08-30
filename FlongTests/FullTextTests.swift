//
//  FullTextTests.swift
//  FlongTests
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import Synchronization
import Testing

@testable import Flong

@Suite("Going to the page for the rest of the article", .serialized)
struct FullTextTests {
    private let database: AppDatabase
    private let articles: ArticleStore
    private let server = StubServer(host: "lequotidien.example.com")
    private let feed: Feed
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() async throws {
        database = try AppDatabase.inMemory()
        articles = ArticleStore(database)
        feed = try await SubscriptionStore(database).subscribe(
            to: Subscription(address: "https://lequotidien.example.com/rss.xml", title: "Le Quotidien")
        ).feed
    }

    private var fullText: FullText {
        FullText(
            database,
            fetcher: FeedFetcher(
                session: server.makeSession(),
                throttle: HostThrottle(interval: 0, burst: 100),
                userAgent: "Flong/test"
            )
        )
    }

    /// An article as a feed that truncates would leave it.
    @discardableResult
    private func add(summary: String, url: String? = "https://lequotidien.example.com/2026/calendrier.html")
        async throws
        -> Entry
    {
        var entry = Entry(
            feedID: feed.id,
            guid: "urn:example:1",
            url: url.flatMap(URL.init(string:)),
            title: "Une réforme du calendrier scolaire à l'étude",
            publishedAt: now,
            receivedAt: now
        )
        entry.hasMedia = false

        try await database.writer.write { db in
            try entry.insert(db)
            try EntryBody(entryID: entry.id, sanitizedHTML: "<p>\(summary)</p>", plainText: summary).insert(db)
        }
        return entry
    }

    private func serve(_ fixture: String) throws {
        let body = try Fixtures.data("Pages/\(fixture)")
        server.install { _ in
            StubResponse(statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"], body: body)
        }
    }

    // MARK: - Fetching

    @Test("A truncated article is completed from its page")
    func fetches() async throws {
        let entry = try await add(summary: "Le ministère envisage de décaler la rentrée.")
        try serve("article.html")
        defer { server.reset() }

        let extracted = try #require(await fullText.extract(entry.id))
        #expect(extracted.contains("les fédérations de parents d'élèves"))

        // Kept, so the next reading costs the publisher nothing.
        let article = try #require(try await articles.article(id: entry.id))
        #expect(article.hasFullText)
        // And what the feed sent is still there : the reader may want it back.
        #expect(article.bodyHTML?.contains("Le ministère envisage") == true)
    }

    @Test("A page is asked for once, however often the article is read")
    func onlyOnce() async throws {
        let entry = try await add(summary: "Le ministère envisage de décaler la rentrée.")

        let body = try Fixtures.data("Pages/article.html")
        let requests = Mutex(0)
        server.install { _ in
            requests.withLock { $0 += 1 }
            return StubResponse(statusCode: 200, headers: ["Content-Type": "text/html"], body: body)
        }
        defer { server.reset() }

        await fullText.extract(entry.id)
        await fullText.extract(entry.id)
        await fullText.extract(entry.id)

        #expect(requests.withLock { $0 } == 1)
    }

    @Test("Keeping an article keeps the fullest version there is")
    func keptWhole() async throws {
        let entry = try await add(summary: "Le ministère envisage de décaler la rentrée.")
        try serve("article.html")
        defer { server.reset() }

        await fullText.extract(entry.id)

        let library = LibraryStore(database)
        try await library.setStarred([entry.id], to: true, at: now)
        let item = try #require(try await library.allItems().first)

        // The library exists so that what was kept survives its source. A
        // frozen summary of something the reader read whole would not.
        #expect(item.contentHTML?.contains("les fédérations de parents d'élèves") == true)
        // And it is searched by the words it actually holds.
        #expect(item.plainText?.contains("fédérations de parents") == true)
    }

    // MARK: - What is never fetched

    @Test("A feed that sends the whole article is taken at its word")
    func wholeArticle() async throws {
        let whole = String(repeating: "Une phrase complète de l'article, écrite par la rédaction. ", count: 40)
        let entry = try await add(summary: whole)

        let requests = Mutex(0)
        server.install { _ in
            requests.withLock { $0 += 1 }
            return StubResponse(statusCode: 200, body: Data())
        }
        defer { server.reset() }

        #expect(await fullText.extract(entry.id) == nil)
        // Asking a server for something already in hand is asking for nothing.
        #expect(requests.withLock { $0 } == 0)
    }

    @Test("An article with no address is not fetched")
    func noAddress() async throws {
        let entry = try await add(summary: "Court.", url: nil)
        #expect(await fullText.extract(entry.id) == nil)
    }

    @Test("A page that holds no article leaves the feed's version alone")
    func nothingToExtract() async throws {
        let entry = try await add(summary: "Le ministère envisage de décaler la rentrée.")
        try serve("wall.html")
        defer { server.reset() }

        #expect(await fullText.extract(entry.id) == nil)

        let article = try #require(try await articles.article(id: entry.id))
        #expect(!article.hasFullText)
        #expect(article.bodyHTML?.contains("Le ministère envisage") == true)
    }

    @Test("A page that cannot be reached leaves the feed's version alone")
    func unreachable() async throws {
        let entry = try await add(summary: "Le ministère envisage de décaler la rentrée.")
        server.install { _ in StubResponse(statusCode: 500) }
        defer { server.reset() }

        #expect(await fullText.extract(entry.id) == nil)
        #expect(try await articles.article(id: entry.id)?.bodyHTML?.isEmpty == false)
    }

    // MARK: - The rule itself

    @Test("What is worth fetching, and what is not")
    func worthFetching() {
        let url = URL(string: "https://example.com/a")

        #expect(FullText.isWorthFetching(url: url, feedHTML: "<p>Deux phrases.</p>", extractedHTML: nil))
        // Already been.
        #expect(!FullText.isWorthFetching(url: url, feedHTML: "<p>Deux phrases.</p>", extractedHTML: "<p>Tout.</p>"))
        // Nowhere to go.
        #expect(!FullText.isWorthFetching(url: nil, feedHTML: "<p>Deux phrases.</p>", extractedHTML: nil))
        // Not a page.
        #expect(
            !FullText.isWorthFetching(
                url: URL(string: "file:///tmp/a.html"),
                feedHTML: "<p>Deux.</p>",
                extractedHTML: nil
            )
        )
        // Long enough to be the article itself.
        let whole = "<p>" + String(repeating: "Une phrase de l'article. ", count: 80) + "</p>"
        #expect(!FullText.isWorthFetching(url: url, feedHTML: whole, extractedHTML: nil))
    }
}

@Suite("Reading a page's bytes")
struct PageTextTests {
    private let accented = "Une réforme du calendrier scolaire à l'étude"

    @Test("The header's charset is honoured first")
    func fromHeader() throws {
        let data = try #require(accented.data(using: .isoLatin1))
        #expect(PageText.text(of: data, contentType: "text/html; charset=iso-8859-1") == accented)
    }

    @Test("A page's own declaration is honoured when the header says nothing")
    func fromMeta() throws {
        let page = "<html><head><meta charset=\"iso-8859-1\"></head><body><p>\(accented)</p></body></html>"
        let data = try #require(page.data(using: .isoLatin1))

        #expect(PageText.text(of: data, contentType: nil).contains(accented))
        // The long spelling, which the pages that need this most are written in.
        let equiv =
            "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=windows-1252\">"
            + "</head><body><p>\(accented)</p></body></html>"
        let bytes = try #require(equiv.data(using: .windowsCP1252))
        #expect(PageText.text(of: bytes, contentType: nil).contains(accented))
    }

    @Test("A page that declares nothing is read as UTF-8")
    func utf8ByDefault() {
        #expect(PageText.text(of: Data(accented.utf8), contentType: nil) == accented)
    }

    @Test("A declaration that lies does not lose the page")
    func lyingDeclaration() throws {
        // Latin-1 bytes claiming UTF-8 : the claim fails to decode, and the
        // fallbacks read it anyway rather than handing back nothing.
        let data = try #require(accented.data(using: .isoLatin1))
        let text = PageText.text(of: data, contentType: "text/html; charset=utf-8")

        #expect(!text.isEmpty)
        #expect(text.contains("calendrier"))
    }

    @Test("A charset nobody has checked is not guessed at")
    func unknownCharset() {
        #expect(PageText.encoding(named: "iso-8859-15") == nil)
        #expect(PageText.encoding(named: "utf-8") == .utf8)
        #expect(PageText.encoding(named: "Windows-1252") == .windowsCP1252)
    }
}
