//
//  StatisticsStore.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB

/// How far back a reading of the stream goes.
///
/// **Eight, and they are not a scale.** A reader asks two different questions
/// of a page of figures : what has been happening lately, which is a day or a
/// week, and what it has all added up to, which is a year or the lot. The
/// months in between are there so the second question can be narrowed without
/// falling off a cliff into the first.
///
/// The window is measured back from now rather than snapped to a calendar. A
/// reader opening this at nine in the morning and asking for a day means the
/// last twenty-four hours, not the ninety minutes since midnight.
nonisolated enum StatisticsRange: String, CaseIterable, Hashable, Sendable, Identifiable {
    case day
    case week
    case month
    case quarter
    case half
    case threeQuarters
    case year
    case all

    var id: String { rawValue }

    /// What the reader picks it by, short enough to sit on a pill.
    var name: LocalizedStringResource {
        switch self {
        case .day: "24 h"
        case .week: "1 week"
        case .month: "1 month"
        case .quarter: "3 months"
        case .half: "6 months"
        case .threeQuarters: "9 months"
        case .year: "1 year"
        case .all: "All"
        }
    }

    /// What a test presses, which is never a translated name.
    var identifier: String { "range-\(rawValue)" }

    /// How long the window is, or nothing at all where it has no beginning.
    var duration: TimeInterval? {
        let day: TimeInterval = 24 * 60 * 60
        switch self {
        case .day: return day
        case .week: return 7 * day
        case .month: return 30 * day
        case .quarter: return 91 * day
        case .half: return 182 * day
        case .threeQuarters: return 274 * day
        case .year: return 365 * day
        case .all: return nil
        }
    }

    /// The first moment the window covers, or nothing where it covers everything.
    func start(from now: Date) -> Date? {
        duration.map { now.addingTimeInterval(-$0) }
    }

    /// How the counts are grouped along the bottom of a chart.
    ///
    /// **Between twelve and about forty marks, whatever the window.** Fewer is
    /// a chart with nothing to say about its own shape ; more is a row of
    /// hairlines. A day is read hour by hour, a season day by day, and a year
    /// month by month.
    var grain: StatisticsGrain {
        switch self {
        case .day: .hour
        case .week, .month, .quarter: .day
        case .half, .threeQuarters: .week
        case .year, .all: .month
        }
    }
}

/// How wide one mark of a chart is.
nonisolated enum StatisticsGrain: Hashable, Sendable {
    case hour
    case day
    case week
    case month

    /// What SQLite is asked to group by.
    ///
    /// Weeks are absent on purpose : SQLite counts them from the first Sunday
    /// or the first Monday of the year depending on the letter used, and
    /// neither is necessarily the reader's own first weekday. Days are asked
    /// for instead and folded into weeks against the reader's calendar, which
    /// is the only one that knows where their week begins.
    var format: String {
        switch self {
        case .hour: "%Y-%m-%d %H"
        case .day, .week: "%Y-%m-%d"
        case .month: "%Y-%m"
        }
    }

    /// How a moment is read back out of that format.
    var pattern: String {
        switch self {
        case .hour: "yyyy-MM-dd HH"
        case .day, .week: "yyyy-MM-dd"
        case .month: "yyyy-MM"
        }
    }

    /// The calendar unit one mark stands for.
    var component: Calendar.Component {
        switch self {
        case .hour: .hour
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

/// One name and how often it came up.
///
/// The one shape every ranking on the page takes : a subject, a person, a
/// byline, a language. They are counted differently and read identically, and
/// four types that differ only in the word above the list would be four types
/// to draw four times.
nonisolated struct Tally: Identifiable, Hashable, Sendable {
    let name: String
    let count: Int

    var id: String { name }
}

/// One publisher, what it gave and how much of it was opened.
///
/// A publisher rather than a feed : `The Guardian` is followed here through
/// three addresses, and a list that named all three would say the paper is a
/// third of what it is. See ``FeedURL/publisher(site:feed:)``.
nonisolated struct SourceTally: Identifiable, Hashable, Sendable {
    /// The publisher's room, which is what its mark is looked up by, or nothing
    /// for a feed whose address says nothing usable.
    let domain: String?
    /// What the publisher is called, which is one of its feeds' titles.
    let name: String
    let count: Int
    /// How many of them the reader opened.
    let read: Int
    /// This publisher's own shape over the window, one count per mark of the
    /// chart above, in the same order.
    let flow: [Int]

    var id: String { domain ?? name }

    /// How much of what it published the reader opened, where it published
    /// anything.
    var attention: Double? {
        count > 0 ? Double(read) / Double(count) : nil
    }
}

/// How much of an article a source actually puts in its feed.
///
/// **The one figure here that is about the feeds rather than about the news.**
/// A feed may carry the whole piece or a sentence and a link, and nothing in
/// the interface ever says which : a reader only learns it by tapping through
/// the same publisher for the tenth time. Measured across this corpus, more
/// than half of every body stored is under two hundred characters, and one
/// paper's median is six.
///
/// **A median and never a mean.** One long read drags an average across a whole
/// publisher, and the question here is what a typical article of theirs looks
/// like rather than what their longest one does.
nonisolated struct BodyLength: Identifiable, Hashable, Sendable {
    let domain: String?
    let name: String
    /// The middle length, in characters, of what its articles carry.
    let median: Int
    /// How many were measured, which is what keeps a source that published
    /// once out of the ranking.
    let articles: Int

    var id: String { domain ?? name }
}

/// How many articles fell in one mark of the chart.
nonisolated struct Arrivals: Identifiable, Hashable, Sendable {
    /// The first moment the mark covers.
    let start: Date
    /// How many arrived in it.
    let count: Int
    /// How many the reader read in it, counted from when they read them rather
    /// than from when the articles were written.
    let read: Int

    var id: Date { start }
}

/// Everything a page of figures is drawn from, read in one pass.
///
/// **One value rather than a dozen properties.** Every figure on the page is
/// about the same window and has to change with it in one movement : a screen
/// holding a count from the last window beside a chart from this one is a
/// screen that lies for the length of a load.
nonisolated struct Statistics: Hashable, Sendable {
    /// The window it was read for.
    var range = StatisticsRange.week
    /// The first moment counted, or nothing where everything was.
    var from: Date?
    /// The moment it was read, which is where every window ends.
    var to = Date()

    /// How many articles arrived, copies and hidden ones excluded, exactly as
    /// every list in the application counts them.
    var arrived = 0
    /// How many of those the reader has read.
    var read = 0
    /// How many the reader kept.
    var starred = 0
    /// How many publishers spoke at all, and through how many feeds.
    var publishers = 0
    var feeds = 0
    /// How many of the read articles carry the moment they were read.
    ///
    /// **Not all of them, and this is what decides whether reading is drawn.**
    /// `read_at` is written by the two paths a reader goes through on this
    /// device ; a read state merged from another of their devices arrives as a
    /// month and a fingerprint and sets `is_read` with no moment attached, and
    /// there is none to attach. So the counts of what was read are whole and
    /// the shape of *when* it was read is not, and a chart drawn from a third
    /// of the truth would be a chart about the wrong evenings.
    var datedReads = 0
    /// How many arrivals were the same article reaching the reader a second
    /// time through another feed, and were never shown.
    var duplicates = 0

    /// The same counts over the window immediately before this one, or nothing
    /// where there is no such window : `Tout` has nothing before it, and a
    /// device that has been collecting for a week has no previous year.
    var previous: Previously?

    /// The shape of the window, one entry per mark of the chart.
    var flow: [Arrivals] = []
    /// How wide one of those marks is.
    var grain = StatisticsGrain.day

    /// The publishers that spoke, the loudest first.
    var sources: [SourceTally] = []
    /// What it was all about, as the digest filed it.
    var subjects: [Tally] = []
    /// Who it was about.
    var people: [Tally] = []
    /// Who wrote it.
    var bylines: [Tally] = []
    /// What it was written in.
    var languages: [Tally] = []
    /// What each publisher puts in its feed, the fullest first.
    var bodies: [BodyLength] = []

    /// How many articles carry each hour of the day, from midnight, and how
    /// many the reader read in each.
    var arrivalsByHour = [Int](repeating: 0, count: 24)
    var readingByHour = [Int](repeating: 0, count: 24)

    /// Whether anything at all was counted.
    var isEmpty: Bool { arrived == 0 }

    /// Whether *when* the reader read is worth drawing.
    ///
    /// Only where most of what they read carries a moment. Below that the shape
    /// is a picture of the reading done on this device passed off as the whole,
    /// and a line along the floor of a chart is worse than no line : see
    /// ``datedReads``.
    var showsReading: Bool {
        read > 0 && Double(datedReads) >= Double(read) * 0.6
    }

    /// The counts of the window before this one, for the only thing that makes
    /// a number interesting, which is the number before it.
    nonisolated struct Previously: Hashable, Sendable {
        var arrived = 0
        var read = 0
    }

    /// How much more or less than last time, where there is a last time and it
    /// was not nought.
    ///
    /// Nothing where the previous window held none : everything is infinitely
    /// more than nothing, and a page that says so has said nothing.
    static func change(from before: Int, to now: Int) -> Double? {
        guard before > 0 else { return nil }
        return Double(now - before) / Double(before)
    }
}

/// Reads the stream as a page of figures.
///
/// **Every count comes out of the database and none out of Swift.** A season of
/// a busy corpus is tens of thousands of rows, and all that is wanted from them
/// is a few dozen integers : fetching the articles to count them here would
/// carry the whole stream across for the sake of the arithmetic.
///
/// **One snapshot for the whole page.** Every query runs inside one read, so
/// the figure at the top and the chart under it are counted from the same
/// database rather than from whatever it happened to be between them : a
/// refresh landing halfway through would otherwise leave a total that does not
/// match its own parts.
nonisolated struct StatisticsStore: Sendable {

    /// How many publishers, subjects, people and bylines a ranking names.
    ///
    /// A list of names is read down to the point where the numbers stop
    /// meaning anything, which is soon : the tenth busiest publisher of a week
    /// is a publisher, and the fortieth is a row of the sources list.
    static let ranked = 10

    /// How many publishers keep a shape of their own beside their count.
    ///
    /// Fewer than are named. A sparkline is read by comparing it with the ones
    /// above it, and past a handful there is nothing left to compare.
    static let sparked = 6

    /// How many articles a source has to have published before the middle
    /// length of its bodies means anything.
    ///
    /// Eight. A median over two articles is one of those two articles, and a
    /// ranking of publishers by it would open on whoever happened to publish
    /// one long piece this week.
    static let measuredAtLeast = 8

    /// How long an article's body has to be before the feed is carrying the
    /// piece rather than an invitation to go and read it.
    ///
    /// Twelve hundred characters, which is about two hundred words, or four
    /// paragraphs. Below it a body is a standfirst : more than half of every
    /// body in a real corpus sits under two hundred characters, and one paper
    /// here stores a median of six.
    static let wholePiece = 1_200

    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    /// Everything the page shows, for one window.
    ///
    /// **The window is measured on the date the stream itself sorts by**, which
    /// is when the publisher says the article was written, or when it reached
    /// this device where the publisher says nothing. Anything else would be a
    /// page of figures that disagrees with the list they are figures about.
    ///
    /// Reading is the one exception and has to be : when the reader read
    /// something is not when it was written, and a chart of their evenings
    /// drawn on publication dates would be a chart of somebody else's day.
    func report(
        for range: StatisticsRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> Statistics {
        let from = range.start(from: now)
        let grain = range.grain
        let (window, arguments) = Self.window(from: from)

        // Everything crosses back out of the database as plain values : a `Row`
        // is not `Sendable`, and a block that hands one back picks GRDB's
        // synchronous read, which would count a season of articles on the
        // thread drawing the screen.
        let raw: Raw = try await database.writer.read { db in
            try Self.read(db, window: window, arguments: arguments, from: from, now: now, grain: grain)
        }

        return Self.assemble(raw, range: range, from: from, now: now, grain: grain, calendar: calendar)
    }

    // MARK: - What comes out of the database

    /// The counts as SQLite hands them over, before a calendar has been near
    /// them.
    ///
    /// Its own type rather than a tuple of eleven things : the read block has to
    /// return something `Sendable`, and a tuple that wide is one nobody can read
    /// at either end of it.
    private struct Raw: Sendable {
        var arrived = 0
        var read = 0
        var starred = 0
        var duplicates = 0
        var datedReads = 0
        var previous: Statistics.Previously?
        /// The middle body length of each feed, and how many it was taken over.
        var medians: [UUID: (median: Int, articles: Int)] = [:]
        /// One count per bucket, keyed as SQLite formatted it.
        var arrivals: [String: Int] = [:]
        var reading: [String: Int] = [:]
        /// One count per bucket per feed, keyed by the feed and then the bucket.
        var byFeed: [UUID: [String: Int]] = [:]
        /// What each feed gave and how much of it was opened.
        var feedTotals: [UUID: (count: Int, read: Int)] = [:]
        /// What each feed is called and where it is served from.
        var feeds: [UUID: FeedIdentity] = [:]
        var subjects: [Tally] = []
        var people: [Tally] = []
        var bylines: [Tally] = []
        var languages: [Tally] = []
        var arrivalsByHour = [Int](repeating: 0, count: 24)
        var readingByHour = [Int](repeating: 0, count: 24)
    }

    /// The little a ranking needs to know about a feed.
    private struct FeedIdentity: Sendable {
        let title: String
        let publisher: String?
    }

    /// One publisher while its feeds are still being added up.
    private struct Gathering {
        let domain: String?
        var name: String
        var count = 0
        var read = 0
        /// How much the busiest of its feeds gave, which is the one the name
        /// comes from.
        var loudest = 0
        var flow: [Date: Int] = [:]
    }

    /// The condition every count is narrowed by, and its arguments.
    ///
    /// Copies and hidden articles are excluded exactly as they are everywhere
    /// else : a duplicate is never shown, so it must never be counted, or the
    /// page reports a fifth more articles than the reader was ever offered.
    /// How many there were is a figure of its own, counted on purpose.
    private static func window(from: Date?) -> (String, StatementArguments) {
        guard let from else { return ("1", []) }
        return ("COALESCE(e.published_at, e.received_at) >= ?", [from])
    }

    private static func read(
        _ db: Database,
        window: String,
        arguments: StatementArguments,
        from: Date?,
        now: Date,
        grain: StatisticsGrain
    ) throws -> Raw {
        var raw = Raw()
        let shown = "e.is_hidden = 0 AND e.duplicate_of IS NULL"
        /// The date the window is measured on, written once : it is the same
        /// expression in eight queries, and eight spellings of it would be
        /// eight chances for one figure to be about a different day.
        let when = "COALESCE(e.published_at, e.received_at)"

        // The totals, in one pass over the window.
        if let row = try Row.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) AS arrived,
                       COALESCE(SUM(e.is_read), 0) AS read,
                       COALESCE(SUM(e.is_starred), 0) AS starred
                FROM entry e
                WHERE \(shown) AND \(window)
                """,
            arguments: arguments
        ) {
            raw.arrived = row["arrived"]
            raw.read = row["read"]
            raw.starred = row["starred"]
        }

        // The copies, which are the one thing here counted from the rows that
        // are never shown.
        raw.duplicates =
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM entry e
                    WHERE e.is_hidden = 0 AND e.duplicate_of IS NOT NULL AND \(window)
                    """,
                arguments: arguments
            ) ?? 0

        // How many of the read articles know when they were read, which is
        // what decides whether the reading may be drawn at all.
        raw.datedReads =
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM entry e
                    WHERE \(shown) AND e.is_read = 1 AND e.read_at IS NOT NULL AND \(window)
                    """,
                arguments: arguments
            ) ?? 0

        // The middle length of what each feed carries.
        //
        // **A window function and not an average.** A single long read drags a
        // mean across a whole publisher, and the question is what a typical
        // article of theirs looks like. The same pattern the store already uses
        // to take a few articles per favourite : see ``ArticleStore``.
        for row in try Row.fetchAll(
            db,
            sql: """
                WITH measured AS (
                    SELECT e.feed_id AS feed_id, LENGTH(b.plain_text) AS length,
                           ROW_NUMBER() OVER (PARTITION BY e.feed_id ORDER BY LENGTH(b.plain_text)) AS place,
                           COUNT(*) OVER (PARTITION BY e.feed_id) AS measured
                    FROM entry e JOIN entry_body b ON b.entry_id = e.id
                    WHERE \(shown) AND \(window) AND b.plain_text IS NOT NULL
                )
                SELECT feed_id, length, measured FROM measured
                WHERE place = (measured + 1) / 2 AND measured >= \(measuredAtLeast)
                """,
            arguments: arguments
        ) {
            guard let feed = row["feed_id"] as UUID? else { continue }
            raw.medians[feed] = (row["length"], row["measured"])
        }

        raw.previous = try previously(db, from: from, now: now, shown: shown)

        // The shape of the window : one row per bucket, and one per bucket per
        // feed. Both are grouped by SQLite rather than counted here, and both
        // are bounded by the grain rather than by the corpus : a year is twelve
        // rows however many articles fell in it.
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT strftime('\(grain.format)', \(when), 'localtime') AS bucket, COUNT(*) AS count
                FROM entry e WHERE \(shown) AND \(window) GROUP BY bucket
                """,
            arguments: arguments
        ) {
            guard let bucket = row["bucket"] as String? else { continue }
            raw.arrivals[bucket] = row["count"]
        }

        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT strftime('\(grain.format)', \(when), 'localtime') AS bucket,
                       e.feed_id AS feed_id, COUNT(*) AS count
                FROM entry e WHERE \(shown) AND \(window) GROUP BY bucket, e.feed_id
                """,
            arguments: arguments
        ) {
            guard let bucket = row["bucket"] as String?, let feed = row["feed_id"] as UUID? else { continue }
            raw.byFeed[feed, default: [:]][bucket] = row["count"]
        }

        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT e.feed_id AS feed_id, COUNT(*) AS count,
                       COALESCE(SUM(e.is_read), 0) AS read
                FROM entry e WHERE \(shown) AND \(window) GROUP BY e.feed_id
                """,
            arguments: arguments
        ) {
            guard let feed = row["feed_id"] as UUID? else { continue }
            raw.feedTotals[feed] = (row["count"], row["read"])
        }

        for row in try Row.fetchAll(db, sql: "SELECT id, title, url, site_url FROM feed") {
            guard let id = row["id"] as UUID? else { continue }
            raw.feeds[id] = FeedIdentity(
                title: row["title"] ?? "",
                publisher: FeedURL.publisher(
                    site: (row["site_url"] as String?).flatMap(URL.init(string:)),
                    feed: (row["url"] as String?).flatMap(URL.init(string:))
                )
            )
        }

        // **When the reader read, counted on when they read it.** The window
        // moves to `read_at`, since an evening spent on last month's backlog is
        // an evening in this week and not in last month.
        let readWindow = from == nil ? "1" : "e.read_at >= ?"
        let readArguments: StatementArguments = from.map { [$0] } ?? []
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT strftime('\(grain.format)', e.read_at, 'localtime') AS bucket, COUNT(*) AS count
                FROM entry e
                WHERE \(shown) AND e.read_at IS NOT NULL AND \(readWindow) GROUP BY bucket
                """,
            arguments: readArguments
        ) {
            guard let bucket = row["bucket"] as String? else { continue }
            raw.reading[bucket] = row["count"]
        }

        raw.arrivalsByHour = try hours(
            db,
            sql: """
                SELECT CAST(strftime('%H', \(when), 'localtime') AS INTEGER) AS hour, COUNT(*) AS count
                FROM entry e WHERE \(shown) AND \(window) GROUP BY hour
                """,
            arguments: arguments
        )
        raw.readingByHour = try hours(
            db,
            sql: """
                SELECT CAST(strftime('%H', e.read_at, 'localtime') AS INTEGER) AS hour, COUNT(*) AS count
                FROM entry e
                WHERE \(shown) AND e.read_at IS NOT NULL AND \(readWindow) GROUP BY hour
                """,
            arguments: readArguments
        )

        // **A subject belongs to a story and reaches an article through it.**
        // The digest is what files the news, and only the articles it grouped
        // carry a subject at all : this counts the ones that do, and says as
        // much on the page rather than passing it off as the whole stream.
        //
        // **Counted in stories and never in articles.** A subject is filed onto
        // a story, so the story is its native grain ; counting the articles
        // underneath instead lets one runaway cluster carry a whole rubric.
        // Measured on a real corpus, `Technologie` came to twelve hundred
        // articles off forty stories and `Politique` to two hundred and fifty
        // off forty-one : ranked by articles the first is five times the
        // second, ranked by stories they are the same size, which is what the
        // page actually looked like.
        raw.subjects = try tallies(
            db,
            sql: """
                SELECT st.name AS name, COUNT(DISTINCT st.story_id) AS count
                FROM story_topic st
                JOIN story_member sm ON sm.story_id = st.story_id
                JOIN entry e ON e.id = sm.entry_id
                WHERE \(shown) AND \(window)
                GROUP BY st.name ORDER BY count DESC, st.name LIMIT \(ranked)
                """,
            arguments: arguments
        )

        raw.people = try tallies(
            db,
            sql: """
                SELECT n.name AS name, COUNT(*) AS count
                FROM entry_newsmaker n JOIN entry e ON e.id = n.entry_id
                WHERE \(shown) AND \(window)
                GROUP BY n.name ORDER BY count DESC, n.name LIMIT \(ranked)
                """,
            arguments: arguments
        )

        raw.bylines = try tallies(
            db,
            sql: """
                SELECT a.name AS name, COUNT(*) AS count
                FROM entry_author a JOIN entry e ON e.id = a.entry_id
                WHERE \(shown) AND \(window)
                GROUP BY a.name ORDER BY count DESC, a.name LIMIT \(ranked)
                """,
            arguments: arguments
        )

        raw.languages = try tallies(
            db,
            sql: """
                SELECT e.language AS name, COUNT(*) AS count
                FROM entry e
                WHERE \(shown) AND \(window) AND e.language IS NOT NULL AND e.language <> ''
                GROUP BY e.language ORDER BY count DESC, e.language
                """,
            arguments: arguments
        )

        return raw
    }

    /// The same counts over the window immediately before this one.
    ///
    /// Nothing at all where the window has no beginning : `Tout` is everything
    /// there is, and there is nothing before everything.
    private static func previously(
        _ db: Database,
        from: Date?,
        now: Date,
        shown: String
    ) throws -> Statistics.Previously? {
        guard let from else { return nil }
        let before = from.addingTimeInterval(from.timeIntervalSince(now))
        let window = "COALESCE(e.published_at, e.received_at) >= ? AND COALESCE(e.published_at, e.received_at) < ?"
        let arguments: StatementArguments = [before, from]

        var previously = Statistics.Previously()
        if let row = try Row.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) AS arrived, COALESCE(SUM(e.is_read), 0) AS read
                FROM entry e WHERE \(shown) AND \(window)
                """,
            arguments: arguments
        ) {
            previously.arrived = row["arrived"]
            previously.read = row["read"]
        }
        return previously
    }

    private static func tallies(_ db: Database, sql: String, arguments: StatementArguments) throws -> [Tally] {
        try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap { row in
            guard let name = row["name"] as String?, !name.isEmpty else { return nil }
            return Tally(name: name, count: row["count"])
        }
    }

    /// Twenty-four counts, from midnight, with the hours nothing fell in left
    /// at nought rather than missing.
    private static func hours(_ db: Database, sql: String, arguments: StatementArguments) throws -> [Int] {
        var counts = [Int](repeating: 0, count: 24)
        for row in try Row.fetchAll(db, sql: sql, arguments: arguments) {
            guard let hour = row["hour"] as Int?, (0..<24).contains(hour) else { continue }
            counts[hour] = row["count"]
        }
        return counts
    }

    // MARK: - What a calendar makes of it

    private static func assemble(
        _ raw: Raw,
        range: StatisticsRange,
        from: Date?,
        now: Date,
        grain: StatisticsGrain,
        calendar: Calendar
    ) -> Statistics {
        var report = Statistics()
        report.range = range
        report.from = from
        report.to = now
        report.grain = grain
        report.arrived = raw.arrived
        report.read = raw.read
        report.starred = raw.starred
        report.duplicates = raw.duplicates
        report.datedReads = raw.datedReads
        report.previous = raw.previous
        report.subjects = raw.subjects
        report.people = raw.people
        report.bylines = raw.bylines
        report.arrivalsByHour = raw.arrivalsByHour
        report.readingByHour = raw.readingByHour
        report.languages = raw.languages

        // The marks of the chart, every one of them, in order. Built from the
        // calendar rather than from the rows : a day nothing arrived on is a
        // quiet day and has to keep its place, or a fortnight of silence draws
        // as no gap at all.
        let reader = Self.reader(for: grain, calendar: calendar)
        let arrivals = Self.fold(raw.arrivals, by: grain, reader: reader, calendar: calendar)
        let reading = Self.fold(raw.reading, by: grain, reader: reader, calendar: calendar)
        let marks = Self.marks(from: from, to: now, grain: grain, calendar: calendar, counted: arrivals)

        report.flow = marks.map { start in
            Arrivals(start: start, count: arrivals[start] ?? 0, read: reading[start] ?? 0)
        }

        // The publishers, gathered from their feeds : three addresses of one
        // paper are one row, and its shape is the three added together.
        //
        // Keyed by the room and never by the name, exactly as the sources list
        // is : a feed whose address says nothing usable is its own publisher,
        // keyed by the feed itself so two of them never collapse into one.
        var gathered: [String: Gathering] = [:]

        for (feed, totals) in raw.feedTotals {
            guard let identity = raw.feeds[feed] else { continue }
            let key = identity.publisher ?? feed.uuidString
            var publisher = gathered[key] ?? Gathering(domain: identity.publisher, name: identity.title)
            publisher.count += totals.count
            publisher.read += totals.read
            // The name of whichever of its feeds gave the most, so a paper
            // followed through three addresses is called what its main feed is
            // called rather than whatever the dictionary happened to hand over
            // first. Only ever shown for a publisher the sources list has no
            // name for : see ``SourceIdentity``.
            if totals.count > publisher.loudest {
                publisher.loudest = totals.count
                publisher.name = identity.title
            }
            for (start, count) in Self.fold(raw.byFeed[feed] ?? [:], by: grain, reader: reader, calendar: calendar) {
                publisher.flow[start, default: 0] += count
            }
            gathered[key] = publisher
        }

        report.publishers = gathered.count
        report.feeds = raw.feedTotals.count

        // What each publisher puts in its feed, the fullest first.
        //
        // **The busiest feed of a publisher answers for it.** A median cannot
        // be added to another median, so three addresses of one paper cannot be
        // folded into one figure the way their counts can. The one that
        // published the most is the one the reader mostly sees, and it is the
        // honest stand-in : a paper whose main feed carries the piece is a
        // paper that carries the piece.
        var fullest: [String: BodyLength] = [:]
        for (feed, measured) in raw.medians {
            guard let identity = raw.feeds[feed] else { continue }
            let key = identity.publisher ?? feed.uuidString
            if let standing = fullest[key], standing.articles >= measured.articles { continue }
            fullest[key] = BodyLength(
                domain: identity.publisher,
                name: identity.title,
                median: measured.median,
                articles: measured.articles
            )
        }
        report.bodies = fullest.values.sorted {
            $0.median == $1.median ? $0.id < $1.id : $0.median > $1.median
        }
        report.sources =
            gathered
            .sorted { left, right in
                left.value.count == right.value.count
                    ? left.key < right.key
                    : left.value.count > right.value.count
            }
            .prefix(ranked)
            .enumerated()
            .map { index, entry in
                SourceTally(
                    domain: entry.value.domain,
                    name: entry.value.name,
                    count: entry.value.count,
                    read: entry.value.read,
                    flow: index < sparked ? marks.map { entry.value.flow[$0] ?? 0 } : []
                )
            }

        return report
    }

    /// Reads a bucket key back into the moment it stands for.
    ///
    /// Built once per report rather than held as a static : a `DateFormatter`
    /// is not `Sendable`, and this is asked for when a page loads rather than
    /// once per row.
    private static func reader(for grain: StatisticsGrain, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = grain.pattern
        return formatter
    }

    /// Turns the keys SQLite grouped by into moments the reader's calendar
    /// agrees with, folding days into weeks where the chart is drawn in weeks.
    private static func fold(
        _ counted: [String: Int],
        by grain: StatisticsGrain,
        reader: DateFormatter,
        calendar: Calendar
    ) -> [Date: Int] {
        var folded: [Date: Int] = [:]
        for (key, count) in counted {
            guard let moment = reader.date(from: key), let start = Self.start(of: moment, grain: grain, in: calendar)
            else { continue }
            folded[start, default: 0] += count
        }
        return folded
    }

    /// The first moment of the mark a date falls in.
    private static func start(of date: Date, grain: StatisticsGrain, in calendar: Calendar) -> Date? {
        calendar.dateInterval(of: grain.component, for: date)?.start
    }

    /// Every mark of the chart, in order and with none missing.
    ///
    /// A window with a beginning is walked from it. `Tout` has none, so it is
    /// walked from where the stream actually starts running.
    ///
    /// **And that is not necessarily its oldest article.** A feed serves its own
    /// archive, so a corpus collected last week routinely holds a piece dated
    /// 2017, and an axis stretched to reach it draws one bar and a hundred and
    /// twelve empty months. The walk begins at the earliest mark carrying a
    /// hundredth of the busiest, which leaves a straggler counted in every
    /// figure on the page and stops it deciding the shape of the chart.
    private static func marks(
        from: Date?,
        to: Date,
        grain: StatisticsGrain,
        calendar: Calendar,
        counted: [Date: Int]
    ) -> [Date] {
        let last = start(of: to, grain: grain, in: calendar) ?? to
        let opening = from.flatMap { start(of: $0, grain: grain, in: calendar) } ?? worthDrawing(counted) ?? last
        let first = min(opening, last)
        guard first <= last else { return [last] }

        var marks: [Date] = []
        var mark = first
        // A window nobody could draw is one nobody should try to : a corpus
        // holding an article dated 1970 would otherwise walk six hundred
        // thousand hours to reach today.
        while mark <= last, marks.count < 1_000 {
            marks.append(mark)
            guard let next = calendar.date(byAdding: grain.component, value: 1, to: mark) else { break }
            mark = next
        }
        return marks
    }

    /// The earliest mark it is worth opening a chart on.
    ///
    /// A hundredth of the busiest, and at least one : a month that held a
    /// single archived piece against a month that held four thousand is not
    /// where the reader's stream began.
    private static func worthDrawing(_ counted: [Date: Int]) -> Date? {
        guard let peak = counted.values.max() else { return nil }
        let floor = max(peak / 100, 1)
        return counted.filter { $0.value >= floor }.keys.min() ?? counted.keys.min()
    }
}
