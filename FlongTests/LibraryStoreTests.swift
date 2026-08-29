//
//  LibraryStoreTests.swift
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

@Suite("Library")
struct LibraryStoreTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let articles: ArticleStore
    private let library: LibraryStore
    private let feed: Feed
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() async throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
        articles = ArticleStore(database)
        library = LibraryStore(database)
        feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://quotidien.example.com/f.xml", title: "Le Quotidien")
        ).feed
    }

    @discardableResult
    private func add(_ title: String, body: String = "Le corps de l'article.", age: TimeInterval = 3600) async throws
        -> Entry
    {
        var entry = Entry(
            feedID: feed.id,
            guid: "urn:example:\(title)",
            url: URL(string: "https://example.com/\(abs(title.hashValue))"),
            title: title,
            excerpt: String(body.prefix(40)),
            author: "Camille Dupuis",
            language: "fr",
            publishedAt: now.addingTimeInterval(-age),
            receivedAt: now.addingTimeInterval(-age)
        )
        entry.hasMedia = false

        try await database.writer.write { db in
            try entry.insert(db)
            try EntryBody(entryID: entry.id, sanitizedHTML: "<p>\(body)</p>", plainText: body).insert(db)
        }
        return entry
    }

    // MARK: - Keeping

    @Test("Starring an article keeps it, with what it said that day")
    func starringKeeps() async throws {
        let entry = try await add("Une réforme du calendrier")

        try await library.setStarred([entry.id], to: true, at: now)

        let items = try await library.allItems()
        let item = try #require(items.first)

        #expect(items.count == 1)
        #expect(item.entryID == entry.id)
        #expect(item.title == "Une réforme du calendrier")
        #expect(item.feedTitle == "Le Quotidien")
        #expect(item.feedURL == feed.url)
        #expect(item.guid == entry.guid)
        #expect(item.author == "Camille Dupuis")
        #expect(item.contentHTML == "<p>Le corps de l'article.</p>")
        #expect(item.plainText == "Le corps de l'article.")
        #expect(item.promotedAt == now)

        let stored = try await database.writer.read { db in try Entry.fetchOne(db, key: entry.id) }
        #expect(stored?.isStarred == true)
    }

    @Test("A kept article outlives the stream row it came from")
    func survivingThePurge() async throws {
        let entry = try await add("Une réforme du calendrier")
        try await library.setStarred([entry.id], to: true, at: now)

        // The stream is a cache : its row goes, and what was kept does not.
        try await database.writer.write { db in _ = try Entry.deleteOne(db, key: entry.id) }

        let item = try #require(try await library.allItems().first)
        #expect(item.entryID == nil)
        #expect(item.contentHTML == "<p>Le corps de l'article.</p>")
        #expect(try await library.count() == 1)
    }

    @Test("A kept article outlives the feed it came from")
    func survivingTheFeed() async throws {
        let entry = try await add("Une réforme du calendrier")
        try await library.setStarred([entry.id], to: true, at: now)

        try await subscriptions.unsubscribe(feed.id)

        let item = try #require(try await library.allItems().first)
        #expect(item.feedTitle == "Le Quotidien")
        #expect(item.contentHTML != nil)
    }

    @Test("Keeping an article twice keeps it once")
    func promotionIsIdempotent() async throws {
        let entry = try await add("Une réforme")

        try await library.setStarred([entry.id], to: true, at: now)
        try await library.promote([entry.id], at: now.addingTimeInterval(60))

        #expect(try await library.count() == 1)
        #expect(try await library.allItems().first?.promotedAt == now)
    }

    @Test("Unstarring lets go of the article")
    func unstarringLetsGo() async throws {
        let entry = try await add("Une réforme")
        try await library.setStarred([entry.id], to: true, at: now)

        try await library.setStarred([entry.id], to: false)

        #expect(try await library.count() == 0)
        let stored = try await database.writer.read { db in try Entry.fetchOne(db, key: entry.id) }
        #expect(stored?.isStarred == false)
    }

    @Test("Unstarring an article somebody wrote about keeps what they wrote")
    func annotationOutlivesTheStar() async throws {
        let entry = try await add("Une réforme")
        try await library.setStarred([entry.id], to: true, at: now)
        try await library.annotate(entry.id, with: "  À relire avant la rentrée  ")

        try await library.setStarred([entry.id], to: false)

        let item = try #require(try await library.allItems().first)
        #expect(item.annotation == "À relire avant la rentrée")
        #expect(try await library.count() == 1)
    }

    @Test("Annotating an article keeps it, even unstarred")
    func annotationKeeps() async throws {
        let entry = try await add("Une réforme")

        try await library.annotate(entry.id, with: "Une note")

        #expect(try await library.count() == 1)
    }

    @Test("Removing a kept article takes the star with it")
    func removing() async throws {
        let entry = try await add("Une réforme")
        try await library.setStarred([entry.id], to: true, at: now)
        let item = try #require(try await library.allItems().first)

        try await library.remove([item.id])

        #expect(try await library.count() == 0)
        let stored = try await database.writer.read { db in try Entry.fetchOne(db, key: entry.id) }
        #expect(stored?.isStarred == false)
    }

    // MARK: - Reading

    @Test("The library lists what it holds, newest first")
    func listing() async throws {
        let old = try await add("Le plus ancien", age: 86400 * 10)
        let recent = try await add("Le plus récent", age: 60)
        try await library.setStarred([old.id, recent.id], to: true, at: now)

        let summaries = try await library.summaries()

        // `allSatisfy` rethrows, which the expectation macro cannot see through.
        let allFromTheLibrary = summaries.allSatisfy { $0.origin == .library }
        let allStarred = summaries.allSatisfy(\.isStarred)

        #expect(summaries.map(\.title) == ["Le plus récent", "Le plus ancien"])
        #expect(allFromTheLibrary)
        #expect(allStarred)
        #expect(summaries.first?.feedTitle == "Le Quotidien")
        #expect(summaries.first?.excerpt == "Le corps de l'article.")
    }

    @Test("A kept article reads as it read the day it was kept")
    func readingAKeptArticle() async throws {
        let entry = try await add("Une réforme")
        try await library.setStarred([entry.id], to: true, at: now)
        let item = try #require(try await library.allItems().first)

        let article = try #require(try await library.article(id: item.id))

        #expect(article.origin == .library)
        #expect(article.title == "Une réforme")
        #expect(article.bodyHTML == "<p>Le corps de l'article.</p>")
        #expect(article.isStarred)
    }

    @Test("The library can be searched for what was kept in it")
    func searching() async throws {
        let first = try await add("Une réforme du calendrier", body: "Le ministère envisage un décalage.")
        let second = try await add("Les macros Swift", body: "Ce que les macros ont changé.")
        try await library.setStarred([first.id, second.id], to: true, at: now)

        #expect(try await library.summaries(matching: "macros").map(\.title) == ["Les macros Swift"])
        #expect(try await library.summaries(matching: "ministère").map(\.title) == ["Une réforme du calendrier"])
        #expect(try await library.summaries(matching: "Dupuis").count == 2)
        #expect(try await library.summaries(matching: "%").isEmpty)
    }

    // MARK: - Retention

    @Test("A purge never touches the library")
    func purgingSparesTheLibrary() async throws {
        let kept = try await add("Gardé", age: 400 * 86400)
        let forgotten = try await add("Oublié", age: 400 * 86400)
        try await library.setStarred([kept.id], to: true, at: now)

        let summary = try await Retention(database).purge(RetentionPolicy(), now: now)

        #expect(summary.byAge == 1)
        #expect(try await library.count() == 1)
        #expect(try await library.allItems().first?.title == "Gardé")
        #expect(try await articles.count(.all, now: now) == 1)
        _ = forgotten
    }

    @Test("A purge by volume spares it too")
    func purgingByVolumeSparesTheLibrary() async throws {
        var entries: [UUID] = []
        for index in 0..<200 {
            let entry = try await add("Article \(index)", body: String(repeating: "x", count: 2048))
            if index < 10 { entries.append(entry.id) }
        }
        try await library.setStarred(entries, to: true, at: now)

        let retention = Retention(database)
        var policy = RetentionPolicy()
        policy.maximumBytes = try await retention.size() / 2
        _ = try await retention.purge(policy, now: now)

        #expect(try await library.count() == 10)
    }
}
