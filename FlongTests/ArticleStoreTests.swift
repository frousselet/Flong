//
//  ArticleStoreTests.swift
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

@Suite("Articles")
struct ArticleStoreTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let articles: ArticleStore
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
        articles = ArticleStore(database)
    }

    @discardableResult
    private func add(
        _ title: String,
        feed: Feed,
        published: Date,
        isRead: Bool = false,
        isStarred: Bool = false,
        isHidden: Bool = false,
        body: String? = nil
    ) async throws -> UUID {
        var entry = Entry(
            feedID: feed.id,
            guid: "urn:example:\(title)",
            url: URL(string: "https://example.com/\(title)"),
            title: title,
            excerpt: "Excerpt of \(title)",
            publishedAt: published,
            receivedAt: published,
            isRead: isRead,
            isStarred: isStarred,
            isHidden: isHidden
        )
        entry.hasMedia = false

        try await database.writer.write { db in
            try entry.insert(db)
            if let body {
                try EntryBody(entryID: entry.id, sanitizedHTML: body, plainText: body).insert(db)
            }
        }
        return entry.id
    }

    private func feed(_ address: String, folder: String? = nil, title: String = "Feed") async throws -> Feed {
        try await subscriptions.subscribe(to: Subscription(address: address, title: title, folder: folder)).feed
    }

    // MARK: - Views

    @Test("A view holds what it says, newest first")
    func filtering() async throws {
        let tech = try await feed("https://a.example.com/f.xml", folder: "Tech", title: "A")
        let news = try await feed("https://b.example.com/f.xml", folder: "Tech/Daily", title: "B")
        let loose = try await feed("https://c.example.com/f.xml", title: "C")

        try await add("old", feed: tech, published: now.addingTimeInterval(-86400 * 3), isRead: true)
        try await add("starred", feed: news, published: now.addingTimeInterval(-3600), isStarred: true)
        try await add("today", feed: loose, published: now.addingTimeInterval(-60))
        try await add("hidden", feed: loose, published: now, isHidden: true)

        let all = try await articles.summaries(.all, now: now)
        #expect(all.map(\.title) == ["today", "starred", "old"])

        #expect(try await articles.summaries(.unread, now: now).map(\.title) == ["today", "starred"])
        #expect(try await articles.summaries(.starred, now: now).map(\.title) == ["starred"])
        #expect(try await articles.summaries(.feed(tech.id), now: now).map(\.title) == ["old"])
        #expect(try await articles.summaries(.folder("Tech"), now: now).map(\.title) == ["starred", "old"])
        #expect(try await articles.summaries(.today, now: now).map(\.title) == ["today", "starred"])
    }

    @Test("An article carries the feed it came from")
    func joinsTheFeed() async throws {
        let feed = try await feed("https://a.example.com/f.xml", title: "The Feed")
        let id = try await add("post", feed: feed, published: now, body: "<p>Body</p>")

        let summary = try #require(try await articles.summaries(.all, now: now).first)
        #expect(summary.feedTitle == "The Feed")
        #expect(summary.excerpt == "Excerpt of post")

        let article = try #require(await articles.article(id: id))
        #expect(article.feedTitle == "The Feed")
        #expect(article.bodyHTML == "<p>Body</p>")
    }

    @Test("Unread counts are per feed, and hidden articles count for nothing")
    func unreadCounts() async throws {
        let first = try await feed("https://a.example.com/f.xml", title: "A")
        let second = try await feed("https://b.example.com/f.xml", title: "B")

        try await add("one", feed: first, published: now)
        try await add("two", feed: first, published: now, isRead: true)
        try await add("three", feed: second, published: now)
        try await add("four", feed: second, published: now, isHidden: true)

        let counts = try await articles.unreadCounts()
        #expect(counts[first.id] == 1)
        #expect(counts[second.id] == 1)
    }

    // MARK: - Reading and starring

    @Test("Reading and starring take effect at once")
    func marking() async throws {
        let feed = try await feed("https://a.example.com/f.xml")
        let id = try await add("post", feed: feed, published: now)

        try await articles.setRead([id], to: true, at: now)
        try await articles.setStarred([id], to: true)

        var summary = try #require(try await articles.summaries(.all, now: now).first)
        #expect(summary.isRead)
        #expect(summary.isStarred)

        try await articles.setRead([id], to: false)
        summary = try #require(try await articles.summaries(.all, now: now).first)
        #expect(!summary.isRead)

        let entry = try await database.writer.read { db in try Entry.fetchOne(db, key: id) }
        #expect(entry?.readAt == nil)
    }

    @Test("A whole view can be given up on")
    func markingAViewRead() async throws {
        let tech = try await feed("https://a.example.com/f.xml", folder: "Tech")
        let other = try await feed("https://b.example.com/f.xml")

        try await add("one", feed: tech, published: now)
        try await add("two", feed: tech, published: now)
        try await add("three", feed: other, published: now)

        let marked = try await articles.markRead(.folder("Tech"), at: now, now: now)

        #expect(marked == 2)
        #expect(try await articles.count(.unread, now: now) == 1)
    }
}

@Suite("Retention")
struct RetentionTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
    }

    private func fill(_ feed: Feed, count: Int, age: TimeInterval, starred: Bool = false) async throws {
        try await database.writer.write { db in
            for index in 0..<count {
                let date = now.addingTimeInterval(-age - Double(index))
                var entry = Entry(
                    feedID: feed.id,
                    guid: "urn:example:\(age)-\(index)-\(starred)",
                    title: "Article \(index)",
                    publishedAt: date,
                    receivedAt: date,
                    isStarred: starred
                )
                entry.hasMedia = false
                try entry.insert(db)
                try EntryBody(entryID: entry.id, sanitizedHTML: String(repeating: "x", count: 2048)).insert(db)
            }
        }
    }

    @Test("Articles past their age go, and what the reader kept stays")
    func purgingByAge() async throws {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://a.example.com/f.xml")
        ).feed

        try await fill(feed, count: 5, age: 60 * 86400)
        try await fill(feed, count: 3, age: 60 * 86400, starred: true)
        try await fill(feed, count: 4, age: 3600)

        let summary = try await Retention(database).purge(RetentionPolicy(), now: now)

        #expect(summary.byAge == 5)
        let remaining = try await ArticleStore(database).count(.all, now: now)
        #expect(remaining == 7)
    }

    @Test("A store past its cap gives up its oldest articles")
    func purgingByVolume() async throws {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://a.example.com/f.xml")
        ).feed
        try await fill(feed, count: 400, age: 3600)

        let retention = Retention(database)
        let before = try await retention.size()
        var policy = RetentionPolicy()
        policy.maximumBytes = before / 2

        let summary = try await retention.purge(policy, now: now)

        #expect(summary.byVolume > 0)
        #expect(summary.bytesAfter <= policy.maximumBytes)
    }
}
