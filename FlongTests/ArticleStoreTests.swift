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

    /// An article as a feed that dates nothing leaves it, or one a publisher
    /// went back to.
    @discardableResult
    private func addEntry(
        _ title: String,
        feed: Feed,
        published: Date?,
        updated: Date? = nil,
        received: Date
    ) async throws -> UUID {
        var entry = Entry(
            feedID: feed.id,
            guid: "urn:example:\(title)",
            title: title,
            publishedAt: published,
            updatedAt: updated,
            receivedAt: received
        )
        entry.hasMedia = false
        try await database.writer.write { db in try entry.insert(db) }
        return entry.id
    }

    // MARK: - What is known about when

    @Test("An article nobody dated says the moment it arrived, and says which it is")
    func undatedArticlesSayTheyArrived() async throws {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://a.example.com/f.xml", title: "A")
        ).feed

        // What `Le Parisien` serves : a build date for the channel and none for
        // any of its items. A hundred of its articles have only the moment they
        // were pulled to sort by, which is the honest answer and must not be
        // shown as though the publisher had said it.
        try await addEntry("Sans date", feed: feed, published: nil, received: now)
        try await addEntry("Datée", feed: feed, published: now.addingTimeInterval(-60), received: now)

        let summaries = try await articles.summaries(.all)
        let undated = try #require(summaries.first { $0.title == "Sans date" })
        let dated = try #require(summaries.first { $0.title == "Datée" })

        #expect(!undated.isDated)
        #expect(undated.date == now)
        #expect(dated.isDated)
    }

    @Test("A publisher who went back to an article says when, and one who did not says nothing")
    func updatesWorthSaying() async throws {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://b.example.com/f.xml", title: "B")
        ).feed

        let published = now.addingTimeInterval(-3600)
        try await addEntry("Reprise", feed: feed, published: published, updated: now, received: now)
        // Stamped within seconds of publishing, which is publishing and not
        // updating : a row saying `modifié` about every article says nothing.
        try await addEntry(
            "Intacte",
            feed: feed,
            published: published,
            updated: published.addingTimeInterval(2),
            received: now
        )

        let summaries = try await articles.summaries(.all)
        #expect(summaries.first { $0.title == "Reprise" }?.updatedAt == now)
        #expect(summaries.first { $0.title == "Intacte" }?.updatedAt == nil)
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

    private func feed(_ address: String, title: String = "Feed") async throws -> Feed {
        try await subscriptions.subscribe(to: Subscription(address: address, title: title)).feed
    }

    // MARK: - Views

    @Test("A view holds what it says, newest first")
    func filtering() async throws {
        let tech = try await feed("https://a.example.com/f.xml", title: "A")
        let news = try await feed("https://b.example.com/f.xml", title: "B")
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
        #expect(
            try await articles.summaries(.feeds([tech.id, news.id]), now: now).map(\.title) == ["starred", "old"])
        // A group whose last source has gone holds nothing, rather than
        // everything, which is what an empty `IN` would have meant.
        #expect(try await articles.summaries(.feeds([]), now: now).isEmpty)
        #expect(try await articles.summaries(.today, now: now).map(\.title) == ["today", "starred"])
    }

    @Test("An article carries the publisher it came from, and not only the desk")
    func carriesItsPublisher() async throws {
        let sport = try await subscriptions.subscribe(
            to: Subscription(
                address: "https://www.lemonde.fr/sport/rss.xml",
                title: "Le Monde - Sport",
                siteURL: URL(string: "https://www.lemonde.fr")
            )
        ).feed
        try await add("Un match", feed: sport, published: now)

        let summary = try #require(try await articles.summaries(.all, now: now).first)
        #expect(summary.domain == "lemonde.fr")
        #expect(summary.feedTitle == "Le Monde - Sport")

        let article = try #require(await articles.article(id: summary.id))
        #expect(article.domain == "lemonde.fr")
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

    // MARK: - The shape of a day

    @Test("Arrivals are counted in the reader's own hours")
    func hourlyCounts() async throws {
        let calendar = Calendar.current
        let feed = try await feed("https://a.example.com/f.xml")
        let today = calendar.startOfDay(for: now)

        // Two hours of one day and one of the day before, each at half past so
        // that no timezone this suite runs in moves one into the hour next
        // door.
        let noon = today.addingTimeInterval(3600 * 12 + 1800)
        let three = today.addingTimeInterval(3600 * 15 + 1800)
        let yesterdayEvening = today.addingTimeInterval(-3600 * 4 + 1800)

        for (moment, titles) in [(noon, ["a", "b", "c"]), (three, ["d"]), (yesterdayEvening, ["e", "f"])] {
            for title in titles {
                try await add(title, feed: feed, published: moment)
            }
        }

        let counts = try await articles.hourlyCounts(.all, now: now)

        #expect(counts[Hours.hour(of: noon, calendar: calendar)] == 3)
        #expect(counts[Hours.hour(of: three, calendar: calendar)] == 1)
        #expect(counts[Hours.hour(of: yesterdayEvening, calendar: calendar)] == 2)
        // An hour nothing came in on is absent rather than zero : the chart
        // fills the day itself, and a query that invented rows would have to
        // know how far back to invent them.
        #expect(counts[Hours.hour(of: today.addingTimeInterval(3600 * 5), calendar: calendar)] == nil)
    }

    @Test("What the list never shows is never counted either")
    func hourlyCountsMatchTheList() async throws {
        let calendar = Calendar.current
        let feed = try await feed("https://a.example.com/f.xml")
        let noon = calendar.startOfDay(for: now).addingTimeInterval(3600 * 12 + 1800)
        let hour = Hours.hour(of: noon, calendar: calendar)

        try await add("kept", feed: feed, published: noon)
        try await add("read", feed: feed, published: noon, isRead: true)
        try await add("hidden", feed: feed, published: noon, isHidden: true)

        // A bar taller than the list under it is a bar that lies, so the
        // counts pass through exactly the view the list was built from.
        #expect(try await articles.hourlyCounts(.all, now: now)[hour] == 2)
        #expect(try await articles.hourlyCounts(.unread, now: now)[hour] == 1)
        #expect(try await articles.hourlyCounts(.starred, now: now)[hour] == nil)
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
        let tech = try await feed("https://a.example.com/f.xml")
        let other = try await feed("https://b.example.com/f.xml")

        try await add("one", feed: tech, published: now)
        try await add("two", feed: tech, published: now)
        try await add("three", feed: other, published: now)

        let marked = try await articles.markRead(.feeds([tech.id]), at: now, now: now)

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

        let summary = try await Retention(database).purge(.bounded, now: now)

        #expect(summary.byAge == 5)
        let remaining = try await ArticleStore(database).count(.all, now: now)
        #expect(remaining == 7)
    }

    @Test("Nothing is thrown away unless a limit is asked for")
    func nothingIsPurgedByDefault() async throws {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://a.example.com/f.xml")
        ).feed
        // Two years old, which the old policy would have taken twenty times
        // over. The reader keeps everything now, on every device, and the
        // purge is a thing they ask for rather than a thing that happens.
        try await fill(feed, count: 12, age: 700 * 86400)

        let summary = try await Retention(database).purge(now: now)

        #expect(summary.removed == 0)
        #expect(try await ArticleStore(database).count(.all, now: now) == 12)
    }

    @Test("A store past its cap gives up its oldest articles")
    func purgingByVolume() async throws {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://a.example.com/f.xml")
        ).feed
        try await fill(feed, count: 400, age: 3600)

        let retention = Retention(database)
        let before = try await retention.size()
        var policy = RetentionPolicy.bounded
        policy.maximumBytes = before / 2

        let summary = try await retention.purge(policy, now: now)

        #expect(summary.byVolume > 0)
        #expect(summary.bytesAfter <= (policy.maximumBytes ?? .max))
    }
}
