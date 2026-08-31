//
//  SearchTests.swift
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

@Suite("Search")
struct SearchTests {
    private let database: AppDatabase
    private let articles: ArticleStore
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    private let press: Feed
    private let tech: Feed

    init() async throws {
        database = try AppDatabase.inMemory()
        articles = ArticleStore(database)

        let subscriptions = SubscriptionStore(database)
        press = try await subscriptions.subscribe(
            to: Subscription(address: "https://quotidien.example.com/f.xml", title: "Le Quotidien")
        ).feed
        tech = try await subscriptions.subscribe(
            to: Subscription(address: "https://swift.example.dev/f.xml", title: "Swift au quotidien")
        ).feed

        try await add(
            "Une réforme du calendrier scolaire",
            feed: press,
            body: "Le ministère envisage de décaler la rentrée dans trois académies.",
            author: "Camille Dupuis",
            language: "fr",
            age: 3600
        )
        try await add(
            "Les macros Swift, deux ans après",
            feed: tech,
            body: "Ce que les macros ont changé au calendrier des versions.",
            author: "Alex Martin",
            language: "fr",
            age: 86400 * 3,
            isRead: true
        )
        try await add(
            "Concurrency, one year on",
            feed: tech,
            body: "What strict concurrency changed, and what it did not.",
            author: "Alex Martin",
            language: "en",
            age: 86400 * 40,
            isStarred: true,
            hasMedia: true
        )
    }

    private func add(
        _ title: String,
        feed: Feed,
        body: String,
        author: String,
        language: String,
        age: TimeInterval,
        isRead: Bool = false,
        isStarred: Bool = false,
        hasMedia: Bool = false
    ) async throws {
        var entry = Entry(
            feedID: feed.id,
            guid: "urn:example:\(title)",
            url: URL(string: "https://\(feed.url.host() ?? "example.com")/\(abs(title.hashValue))"),
            title: title,
            excerpt: String(body.prefix(60)),
            author: author,
            language: language,
            publishedAt: now.addingTimeInterval(-age),
            receivedAt: now.addingTimeInterval(-age),
            isRead: isRead,
            isStarred: isStarred
        )
        entry.hasMedia = hasMedia

        try await database.writer.write { db in
            try entry.insert(db)
            try EntryBody(entryID: entry.id, sanitizedHTML: "<p>\(body)</p>", plainText: body).insert(db)
        }
    }

    private func search(_ query: String, in filter: ArticleFilter = .all) async throws -> [String] {
        let node = QueryParser.parse(query, now: now)
        return try await articles.summaries(filter, matching: node, now: now).map(\.title)
    }

    // MARK: - Text

    @Test("A word finds the articles that hold it, wherever they hold it")
    func words() async throws {
        #expect(try await search("réforme") == ["Une réforme du calendrier scolaire"])
        #expect(try await search("ministère") == ["Une réforme du calendrier scolaire"])
        #expect(try await search("Dupuis") == ["Une réforme du calendrier scolaire"])
    }

    @Test("Two words both have to be there")
    func conjunction() async throws {
        #expect(try await search("macros calendrier") == ["Les macros Swift, deux ans après"])
        #expect(try await search("macros réforme").isEmpty)
    }

    @Test("A search is ranked, a title outweighing a body")
    func ranking() async throws {
        // Both articles hold "calendrier" : one in its title, one in its body.
        #expect(
            try await search("calendrier") == [
                "Une réforme du calendrier scolaire",
                "Les macros Swift, deux ans après",
            ]
        )
    }

    @Test("A field looks in one place only")
    func fields() async throws {
        #expect(try await search("title:calendrier") == ["Une réforme du calendrier scolaire"])
        #expect(try await search("text:calendrier") == ["Les macros Swift, deux ans après"])
        #expect(try await search("author:martin").count == 2)
    }

    @Test("A phrase has to appear in that order")
    func phrases() async throws {
        #expect(try await search("\"calendrier scolaire\"") == ["Une réforme du calendrier scolaire"])
        #expect(try await search("\"scolaire calendrier\"").isEmpty)
    }

    @Test("A prefix finds what has only been typed halfway")
    func prefixes() async throws {
        #expect(try await search("concur*") == ["Concurrency, one year on"])
    }

    // MARK: - States, dates and places

    @Test("A state narrows a search to what the reader has done")
    func states() async throws {
        #expect(try await search("is:unread").count == 2)
        #expect(try await search("is:starred") == ["Concurrency, one year on"])
        #expect(try await search("has:media") == ["Concurrency, one year on"])
        #expect(try await search("has:fulltext").count == 3)
        #expect(try await search("is:collected").isEmpty)
        #expect(try await search("is:annotated").isEmpty)
    }

    @Test("A language narrows it to what can be read")
    func languages() async throws {
        #expect(try await search("lang:fr").count == 2)
        #expect(try await search("lang:en-GB") == ["Concurrency, one year on"])
    }

    @Test("A feed and a site narrow it to where an article came from")
    func places() async throws {
        // Both feeds are called something "quotidien", and both answer.
        #expect(try await search("feed:quotidien").count == 3)
        #expect(try await search("feed:\"Le Quotidien\"") == ["Une réforme du calendrier scolaire"])
        #expect(try await search("site:swift.example.dev").count == 2)
    }

    @Test("A tag narrows it to what the reader filed, and to nothing else")
    func tags() async throws {
        let collections = CollectionStore(database)
        let summaries = try await articles.summaries(.all, now: now)
        let filed = try #require(summaries.first { $0.title == "Une réforme du calendrier scolaire" })

        _ = try await collections.create("Presse")
        try await collections.add([filed.id], to: "Presse")

        #expect(try await search("tag:collection/Presse") == ["Une réforme du calendrier scolaire"])
        // A tag answers for everything below it, which is what makes
        // `collection` the whole shelf.
        #expect(try await search("tag:collection") == ["Une réforme du calendrier scolaire"])

        // A source is no longer filed anywhere. It belongs to the publisher
        // serving it, and `feed:` and `site:` are what ask about that.
        #expect(try await search("tag:quotidien.example.com").isEmpty)
    }

    @Test("A date keeps a search to a period")
    func dates() async throws {
        #expect(try await search("age:<2d") == ["Une réforme du calendrier scolaire"])
        #expect(try await search("age:>1w") == ["Concurrency, one year on"])
        #expect(try await search("after:2026-08-01").count == 2)
        #expect(try await search("before:2026-08-01") == ["Concurrency, one year on"])
    }

    // MARK: - Combining

    @Test("Everything combines, as the specification's own example does")
    func combining() async throws {
        #expect(try await search("calendrier -macros") == ["Une réforme du calendrier scolaire"])
        #expect(try await search("(macros OR réforme) is:unread").count == 1)
        // In that feed, what is unread is in English and what is French has
        // been read.
        #expect(try await search("feed:\"Swift au quotidien\" is:unread lang:fr").isEmpty)
        #expect(
            try await search("feed:\"Le Quotidien\" is:unread lang:fr") == ["Une réforme du calendrier scolaire"])
        #expect(try await search("author:martin -is:read") == ["Concurrency, one year on"])
    }

    @Test("A search runs inside the view it was typed in")
    func withinAView() async throws {
        #expect(try await search("calendrier", in: .feed(tech.id)) == ["Les macros Swift, deux ans après"])
        #expect(try await search("calendrier", in: .unread) == ["Une réforme du calendrier scolaire"])
    }

    @Test("An empty query is not a filter")
    func emptyQuery() async throws {
        #expect(try await search("").count == 3)
    }

    @Test("Counting agrees with listing")
    func counting() async throws {
        let node = QueryParser.parse("calendrier", now: now)
        #expect(try await articles.count(.all, matching: node, now: now) == 2)
    }

    // MARK: - Hostile input

    @Test(
        "What is typed is searched for, never run",
        arguments: [
            "'; DROP TABLE entry; --",
            "\" OR 1=1 --",
            "NEAR(réforme calendrier)",
            "^réforme",
            "réforme AND (",
            "%_%",
            "\\",
        ]
    )
    func injection(query: String) async throws {
        // Every one of these must come back with an answer rather than an error,
        // and the store must still be there afterwards.
        _ = try await search(query)
        #expect(try await articles.count(.all, now: now) == 3)
    }

    @Test("A query nobody meant matches nothing rather than everything")
    func nonsense() async throws {
        #expect(try await search("zzzzzz").isEmpty)
        #expect(try await search("title:zzzzzz").isEmpty)
    }
}
