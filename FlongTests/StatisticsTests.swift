//
//  StatisticsTests.swift
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

/// What the stream adds up to.
///
/// The figures are read out of SQL and folded against a calendar, and both
/// halves have a way of being quietly wrong : a count that includes the copies
/// nobody was shown, a chart with a silent day missing from it, a publisher
/// counted three times because it is followed through three addresses.
@Suite("Statistics")
struct StatisticsTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let statistics: StatisticsStore
    private let articles: ArticleStore

    /// A fixed noon, so a window measured back from it lands where the test
    /// says rather than where the clock does.
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    /// The reader's own calendar, stated rather than inherited, since where a
    /// week begins decides which mark a day falls in.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }()

    init() throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
        statistics = StatisticsStore(database)
        articles = ArticleStore(database)
    }

    // MARK: - Building a stream to count

    private func subscribe(_ address: String, _ title: String, site: String? = nil) async throws -> Feed {
        var feed = try await subscriptions.subscribe(
            to: Subscription(address: address, title: title)
        ).feed
        if let site {
            feed.siteURL = URL(string: site)
            try await database.writer.write { db in try feed.update(db) }
        }
        return feed
    }

    @discardableResult
    private func add(
        _ title: String,
        to feed: Feed,
        published: Date,
        read: Date? = nil,
        duplicateOf: UUID? = nil,
        language: String? = nil,
        body: String? = nil
    ) async throws -> UUID {
        var entry = Entry(
            feedID: feed.id,
            guid: "urn:example:\(title)",
            title: title,
            language: language,
            publishedAt: published,
            receivedAt: published,
            isRead: read != nil,
            readAt: read,
            duplicateOf: duplicateOf
        )
        entry.readAt = read
        let id = entry.id
        try await database.writer.write { db in
            try entry.insert(db)
            if let body {
                try EntryBody(entryID: id, sanitizedHTML: nil, extractedHTML: nil, plainText: body).insert(db)
            }
        }
        return id
    }

    /// Named for what it returns rather than `report`, which every test then
    /// shadows with the value it binds.
    private func figures(_ range: StatisticsRange) async throws -> Statistics {
        try await statistics.report(for: range, now: now, calendar: calendar)
    }

    private func hours(_ count: Double) -> Date { now.addingTimeInterval(-count * 3600) }

    // MARK: - What is counted, and what is not

    @Test("A copy is counted as a copy and never as an article")
    func copiesAreCountedApart() async throws {
        let feed = try await subscribe("https://a.example.com/f.xml", "A")
        let first = try await add("Une", to: feed, published: hours(2))
        try await add("La même", to: feed, published: hours(1), duplicateOf: first)

        let report = try await figures(.day)

        // The stream showed one article and set the other aside, so the page
        // says one : a figure that counted both would report a fifth more
        // articles than the reader was ever offered.
        #expect(report.arrived == 1)
        #expect(report.duplicates == 1)
    }

    @Test("A hidden article is counted nowhere")
    func hiddenArticlesAreCountedNowhere() async throws {
        let feed = try await subscribe("https://a.example.com/f.xml", "A")
        let id = try await add("Cachée", to: feed, published: hours(2))
        try await add("Montrée", to: feed, published: hours(1))
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE entry SET is_hidden = 1 WHERE id = ?", arguments: [id])
        }

        let report = try await figures(.day)
        #expect(report.arrived == 1)
        #expect(report.duplicates == 0)
    }

    @Test("The window is measured on the date the stream itself sorts by")
    func theWindowFollowsTheStream() async throws {
        let feed = try await subscribe("https://a.example.com/f.xml", "A")
        try await add("Hier", to: feed, published: hours(20))
        try await add("La semaine dernière", to: feed, published: hours(24 * 5))

        #expect(try await figures(.day).arrived == 1)
        #expect(try await figures(.week).arrived == 2)
        #expect(try await figures(.all).arrived == 2)
    }

    // MARK: - The shape of the window

    @Test("A quiet mark keeps its place in the chart")
    func quietMarksKeepTheirPlace() async throws {
        let feed = try await subscribe("https://a.example.com/f.xml", "A")
        try await add("Il y a six jours", to: feed, published: hours(24 * 6))
        try await add("Aujourd'hui", to: feed, published: hours(1))

        let report = try await figures(.week)

        // Seven or eight marks depending on where the window's first moment
        // falls in its day, and the days in between are drawn at nought rather
        // than left out : a fortnight of silence must read as a fortnight.
        #expect(report.flow.count >= 7)
        #expect(report.flow.allSatisfy { $0.count >= 0 })
        #expect(report.flow.reduce(0) { $0 + $1.count } == 2)

        // In order, and with no mark twice.
        #expect(report.flow.map(\.start) == report.flow.map(\.start).sorted())
        #expect(Set(report.flow.map(\.start)).count == report.flow.count)
    }

    @Test("A day is read hour by hour and a year month by month")
    func theGrainFollowsTheWindow() async throws {
        #expect(StatisticsRange.day.grain == .hour)
        #expect(StatisticsRange.week.grain == .day)
        #expect(StatisticsRange.half.grain == .week)
        #expect(StatisticsRange.year.grain == .month)

        let feed = try await subscribe("https://a.example.com/f.xml", "A")
        try await add("Une", to: feed, published: hours(3))

        let day = try await figures(.day)
        #expect(day.grain == .hour)
        // Twenty-four or twenty-five marks : the window is measured back from
        // now, so its first moment falls inside an hour rather than on one.
        #expect(day.flow.count >= 24)
        #expect(day.flow.count <= 25)
    }

    @Test("An archived straggler is counted without stretching the chart to reach it")
    func aStragglerDoesNotStretchTheChart() async throws {
        let feed = try await subscribe("https://a.example.com/f.xml", "A")
        // What a feed's own archive routinely drops into a corpus collected
        // last week. It is one article and it is real.
        try await add("De 2017", to: feed, published: now.addingTimeInterval(-9 * 365 * 24 * 3600))
        for index in 0..<200 {
            try await add("Récente \(index)", to: feed, published: hours(Double(index)))
        }

        let report = try await figures(.all)

        // Counted in the figures, which is what makes them true.
        #expect(report.arrived == 201)
        // And not in the axis : nine years of empty months would draw one bar
        // and a hundred and twelve nothings.
        #expect(report.flow.count <= 3)
    }

    // MARK: - The publishers

    @Test("A paper followed through three addresses is one row")
    func feedsOfOnePublisherAreOneRow() async throws {
        let world = try await subscribe(
            "https://www.theguardian.com/world/rss",
            "The Guardian",
            site: "https://www.theguardian.com/world"
        )
        let tech = try await subscribe(
            "https://www.theguardian.com/technology/rss",
            "The Guardian Tech",
            site: "https://www.theguardian.com/technology"
        )
        let other = try await subscribe("https://lemonde.fr/rss.xml", "Le Monde", site: "https://lemonde.fr")

        try await add("Une", to: world, published: hours(1))
        try await add("Deux", to: world, published: hours(2))
        try await add("Trois", to: tech, published: hours(3))
        try await add("Quatre", to: other, published: hours(4))

        let report = try await figures(.day)

        #expect(report.publishers == 2)
        #expect(report.feeds == 3)

        let guardian = try #require(report.sources.first { $0.domain == "theguardian.com" })
        #expect(guardian.count == 3)
        // The busiest of its feeds answers for it, so the name does not depend
        // on which one the dictionary handed over first.
        #expect(guardian.name == "The Guardian")

        // Loudest first.
        #expect(report.sources.first?.domain == "theguardian.com")
        // And its shape has one mark per mark of the chart.
        #expect(guardian.flow.count == report.flow.count)
        #expect(guardian.flow.reduce(0, +) == 3)
    }

    // MARK: - What it was about

    @Test("A subject is counted in stories and never in articles")
    func subjectsAreCountedInStories() async throws {
        let feed = try await subscribe("https://a.example.com/f.xml", "A")

        // One runaway cluster against a subject that actually ran : counted in
        // articles the first is ten times the second, counted in stories they
        // are the same size, and the second is what the page looked like.
        try await file("Technologie", stories: 1, articles: 10, in: feed, from: 1)
        try await file("Politique", stories: 3, articles: 3, in: feed, from: 40)

        let report = try await figures(.day)
        let subjects = Dictionary(uniqueKeysWithValues: report.subjects.map { ($0.name, $0.count) })

        #expect(subjects["Politique"] == 3)
        #expect(subjects["Technologie"] == 1)
        #expect(report.subjects.first?.name == "Politique")
    }

    /// Files a run of articles into stories under one subject.
    private func file(
        _ topic: String,
        stories: Int,
        articles perStory: Int,
        in feed: Feed,
        from offset: Int
    ) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO topic (name, is_own, created_at) VALUES (?, 0, ?)",
                arguments: [topic, self.now]
            )
        }

        for story in 0..<stories {
            let storyID = UUID.v7()
            try await database.writer.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO story (id, title, is_generated, brief_locked, article_count,
                                           feed_count, first_at, last_at, updated_at)
                        VALUES (?, ?, 0, 0, ?, 1, ?, ?, ?)
                        """,
                    arguments: [storyID, "\(topic) \(story)", perStory, self.now, self.now, self.now]
                )
                try db.execute(
                    sql: "INSERT INTO story_topic (story_id, name) VALUES (?, ?)",
                    arguments: [storyID, topic]
                )
            }

            for member in 0..<perStory {
                let id = try await add(
                    "\(topic) \(story) \(member)",
                    to: feed,
                    published: hours(Double(offset + story * perStory + member) * 0.1 + 1)
                )
                try await database.writer.write { db in
                    try db.execute(
                        sql: "INSERT INTO story_member (story_id, entry_id, similarity) VALUES (?, ?, 1.0)",
                        arguments: [storyID, id]
                    )
                }
            }
        }
    }

    @Test("The languages are ranked, and a feed that states none is left out of them")
    func languagesAreRanked() async throws {
        let feed = try await subscribe("https://a.example.com/f.xml", "A")
        try await add("Une", to: feed, published: hours(1), language: "fr")
        try await add("Deux", to: feed, published: hours(2), language: "fr")
        try await add("Three", to: feed, published: hours(3), language: "en")
        try await add("Sans langue", to: feed, published: hours(4))

        let report = try await figures(.day)
        #expect(report.languages.map(\.name) == ["fr", "en"])
        #expect(report.languages.first?.count == 2)
    }

    // MARK: - What a source puts in its feed

    @Test("A feed is judged against a length and never against its place in a list")
    func theVerdictIsAThreshold() {
        func kind(_ median: Int) -> BodyLength.Kind {
            BodyLength(domain: "a.example.com", name: "A", median: median, articles: 20).kind
        }

        // The card used to call the top half of the ranking whole articles and
        // the bottom half headlines, so a reader following eight generous
        // sources had the bottom four accused of sending nothing. Measured on a
        // real corpus : `theguardian.com` sits at 730 and is an excerpt whoever
        // else is in the list, and `Le Monde` stores a median of six.
        #expect(kind(3_461) == .whole)
        #expect(kind(1_745) == .whole)
        #expect(kind(StatisticsStore.wholePiece) == .whole)
        #expect(kind(StatisticsStore.wholePiece - 1) == .excerpt)
        #expect(kind(730) == .excerpt)
        #expect(kind(StatisticsStore.excerpt) == .excerpt)
        #expect(kind(StatisticsStore.excerpt - 1) == .headline)
        #expect(kind(109) == .headline)
        #expect(kind(6) == .headline)
    }

    @Test("A source that gives a headline is told from one that gives the article")
    func bodyLengthsSeparateTheTwoKinds() async throws {
        let full = try await subscribe("https://full.example.com/f.xml", "Full", site: "https://full.example.com")
        let teaser = try await subscribe("https://tease.example.com/f.xml", "Tease", site: "https://tease.example.com")

        for index in 0..<10 {
            try await add(
                "Longue \(index)", to: full, published: hours(Double(index) + 1),
                body: String(repeating: "a", count: 3_000))
            try await add("Courte \(index)", to: teaser, published: hours(Double(index) + 1), body: "Lisez la suite")
        }

        let report = try await figures(.day)
        #expect(report.bodies.count == 2)
        #expect(report.bodies.first?.domain == "full.example.com")
        #expect(report.bodies.first?.median == 3_000)
        #expect(report.bodies.first?.kind == .whole)
        #expect(report.bodies.last?.domain == "tease.example.com")
        #expect(report.bodies.last?.kind == .headline)
    }

    @Test("A source that has barely published is left out of the lengths")
    func aSourceWithTooLittleIsNotMeasured() async throws {
        let feed = try await subscribe("https://a.example.com/f.xml", "A", site: "https://a.example.com")
        // Under the floor : a median over two articles is one of those two.
        try await add("Une", to: feed, published: hours(1), body: String(repeating: "a", count: 4_000))
        try await add("Deux", to: feed, published: hours(2), body: "court")

        let report = try await figures(.day)
        #expect(report.bodies.isEmpty)
    }

    // MARK: - The reading

    @Test("When the reader read is drawn only where most of it is known")
    func readingIsDrawnOnlyWhenItIsKnown() async throws {
        let feed = try await subscribe("https://a.example.com/f.xml", "A")
        for index in 0..<10 {
            try await add("Lue \(index)", to: feed, published: hours(Double(index) + 1), read: hours(Double(index)))
        }

        var report = try await figures(.day)
        #expect(report.read == 10)
        #expect(report.datedReads == 10)
        #expect(report.showsReading)
        #expect(report.readingByHour.reduce(0, +) == 10)

        // What a read state merged from another device looks like : the article
        // is read and there is no moment to attach, so the shape of the reading
        // stops being worth drawing.
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE entry SET read_at = NULL")
        }
        report = try await figures(.day)
        #expect(report.read == 10)
        #expect(report.datedReads == 0)
        #expect(!report.showsReading)
    }

    @Test("The reading is counted on when it was read and not on when it was written")
    func readingIsCountedWhenItHappened() async throws {
        let feed = try await subscribe("https://a.example.com/f.xml", "A")
        // Last month's backlog, got through this afternoon.
        try await add("Vieille", to: feed, published: hours(24 * 40), read: hours(2))

        let day = try await figures(.day)
        // It was not published in the window, so it is not an arrival.
        #expect(day.arrived == 0)
        // It was read in it, so the hour it was read in carries a mark.
        #expect(day.readingByHour.reduce(0, +) == 1)
    }

    // MARK: - The window before

    @Test("A figure is set against the same length of time just before it")
    func theWindowBeforeIsCounted() async throws {
        let feed = try await subscribe("https://a.example.com/f.xml", "A")
        try await add("Une", to: feed, published: hours(2))
        try await add("Deux", to: feed, published: hours(3))
        try await add("Avant", to: feed, published: hours(30))

        let report = try await figures(.day)
        #expect(report.arrived == 2)
        #expect(report.previous?.arrived == 1)
        #expect(Statistics.change(from: 1, to: 2) == 1)

        // Nothing is infinitely more than nothing.
        #expect(Statistics.change(from: 0, to: 5) == nil)

        // `Tout` has no window before it.
        #expect(try await figures(.all).previous == nil)
    }

    // MARK: - An empty stream

    @Test("A window with nothing in it says so rather than failing")
    func anEmptyWindowIsAnAnswer() async throws {
        let report = try await figures(.week)
        #expect(report.isEmpty)
        #expect(report.arrived == 0)
        #expect(report.sources.isEmpty)
        #expect(report.subjects.isEmpty)
        #expect(!report.showsReading)
        // The chart still has its marks : an empty week is a week of nought,
        // not an absence of days.
        #expect(!report.flow.isEmpty)
    }
}
