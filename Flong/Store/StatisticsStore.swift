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
    /// Everything there is, which is what the page opens on.
    ///
    /// **First in the row and not last.** A reader opening a page of figures
    /// for the first time is asking what it all comes to, not what happened
    /// since yesterday : the widest window is the answer to that, and every
    /// narrower one is a question they ask afterwards. It also opens on the
    /// page's best case, since a window of a day on a device that has been
    /// collecting for an afternoon has almost nothing in it.
    case all
    case day
    case week
    case month
    case quarter
    case half
    case threeQuarters
    case year

    var id: String { rawValue }

    /// What the reader picks it by, short enough to sit on a pill.
    var name: LocalizedStringResource {
        switch self {
        case .all: "All"
        case .day: "24 h"
        case .week: "1 week"
        case .month: "1 month"
        case .quarter: "3 months"
        case .half: "6 months"
        case .threeQuarters: "9 months"
        case .year: "1 year"
        }
    }

    /// What a test presses, which is never a translated name.
    var identifier: String { "range-\(rawValue)" }

    /// How long the window is, or nothing at all where it has no beginning.
    var duration: TimeInterval? {
        let day: TimeInterval = 24 * 60 * 60
        switch self {
        case .all: return nil
        case .day: return day
        case .week: return 7 * day
        case .month: return 30 * day
        case .quarter: return 91 * day
        case .half: return 182 * day
        case .threeQuarters: return 274 * day
        case .year: return 365 * day
        }
    }

    /// The first moment the window covers, or nothing where it covers everything.
    func start(from now: Date) -> Date? {
        duration.map { now.addingTimeInterval(-$0) }
    }

    /// Whether a dial of this unit has anything to say over this window.
    ///
    /// **A dial is a comparison between the places on it**, and a place that
    /// came round once over the whole window is not being compared with
    /// anything : `Articles par jour de la semaine` over twenty-four hours is
    /// one spoke and six empty ones, and `Articles par jour du mois` over a
    /// week is seven of thirty-one. Both were drawn, and both were nonsense.
    ///
    /// Twice round is the floor. Below it the dial says what the chart at the
    /// head of the page already said, bent into a circle.
    func turns(every cycle: TimeInterval) -> Bool {
        guard let duration else { return true }
        return duration >= cycle * 2
    }

    /// How the counts are grouped along the bottom of a chart.
    ///
    /// **Between twelve and about forty marks, whatever the window.** Fewer is
    /// a chart with nothing to say about its own shape ; more is a row of
    /// hairlines. A day is read hour by hour, a season day by day, and a year
    /// month by month.
    var grain: StatisticsGrain {
        switch self {
        case .year, .all: .month
        case .day: .hour
        case .week, .month, .quarter: .day
        case .half, .threeQuarters: .week
        }
    }
}

/// How long the units a dial can be drawn round take to come round again.
nonisolated enum Cycle {
    /// A day, which the hours of a dial come round in.
    static let day: TimeInterval = 24 * 60 * 60
    /// A week, which its days come round in.
    static let week: TimeInterval = 7 * day
    /// A month, near enough : the mean length of one over a leap cycle, since
    /// the question is whether the window holds two of them and not which two.
    static let month: TimeInterval = 30.44 * day
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
    /// How many stories the digest made of the window, and how many articles
    /// it gathered into them.
    ///
    /// **What the wire came to, rather than how much of it there was.** Eight
    /// hundred articles is a number nobody can hold ; a hundred and fifteen
    /// things that happened is a day. The two counts are kept apart because the
    /// digest groups what it can and not everything : the average below is
    /// taken over the articles it actually gathered, or it would be an average
    /// of a story and a heap of things that are in no story.
    var stories = 0
    var storiedArticles = 0

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

    /// How many articles carry each hour of the day, from midnight, and how
    /// many the reader read in each.
    var arrivalsByHour = [Int](repeating: 0, count: 24)
    var readingByHour = [Int](repeating: 0, count: 24)

    /// The same, by day of the week, Sunday first.
    ///
    /// **Sunday first because that is where SQLite counts from**, and never
    /// because it is where a week begins : `strftime('%w')` answers nought for
    /// Sunday whatever the reader's calendar says. The dial turns it round to
    /// the reader's own first weekday when it draws it, which is the one place
    /// that knows.
    var arrivalsByWeekday = [Int](repeating: 0, count: 7)
    var readingByWeekday = [Int](repeating: 0, count: 7)

    /// The same, by day of the month, the first at index nought.
    ///
    /// **The last three are structurally quieter and it is not a lie.** A
    /// thirty-first only comes round in seven months of twelve and a
    /// twenty-ninth in one year of four, so over a long window those spokes
    /// stand for fewer days than the ones before them. The count is what was
    /// asked for and what is drawn ; dividing it by the number of times the day
    /// came round would be an average of a count and no longer articles.
    var arrivalsByDay = [Int](repeating: 0, count: 31)
    var readingByDay = [Int](repeating: 0, count: 31)

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
    /// How many articles a story gathered, on average, where any did.
    var articlesPerStory: Double? {
        stories > 0 ? Double(storiedArticles) / Double(stories) : nil
    }

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
        var stories = 0
        var storiedArticles = 0
        var datedReads = 0
        var previous: Statistics.Previously?
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
        var arrivalsByWeekday = [Int](repeating: 0, count: 7)
        var readingByWeekday = [Int](repeating: 0, count: 7)
        var arrivalsByDay = [Int](repeating: 0, count: 31)
        var readingByDay = [Int](repeating: 0, count: 31)
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

        // What the digest made of it. An article belongs to one story at most,
        // so the members are the articles gathered and the distinct stories are
        // the things that happened.
        if let row = try Row.fetchOne(
            db,
            sql: """
                SELECT COUNT(DISTINCT sm.story_id) AS stories, COUNT(*) AS gathered
                FROM story_member sm JOIN entry e ON e.id = sm.entry_id
                WHERE \(shown) AND \(window)
                """,
            arguments: arguments
        ) {
            raw.stories = row["stories"]
            raw.storiedArticles = row["gathered"]
        }

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

        // The three ways round a dial : the hours of a day, the days of a week
        // and the days of a month. One shape, asked three times, of the
        // arrivals and then of the reading.
        //
        // `%w` counts the week from Sunday and `%d` the month from one, so the
        // day of the month is shifted to sit at nought : see ``Statistics``.
        for (unit, format, slots, first) in [
            ("hour", "%H", 24, 0),
            ("weekday", "%w", 7, 0),
            ("day", "%d", 31, 1),
        ] {
            let arrivals = try dial(
                db,
                sql: """
                    SELECT CAST(strftime('\(format)', \(when), 'localtime') AS INTEGER) AS slot, COUNT(*) AS count
                    FROM entry e WHERE \(shown) AND \(window) GROUP BY slot
                    """,
                arguments: arguments,
                slots: slots,
                first: first
            )
            let reading = try dial(
                db,
                sql: """
                    SELECT CAST(strftime('\(format)', e.read_at, 'localtime') AS INTEGER) AS slot, COUNT(*) AS count
                    FROM entry e
                    WHERE \(shown) AND e.read_at IS NOT NULL AND \(readWindow) GROUP BY slot
                    """,
                arguments: readArguments,
                slots: slots,
                first: first
            )

            switch unit {
            case "hour":
                raw.arrivalsByHour = arrivals
                raw.readingByHour = reading
            case "weekday":
                raw.arrivalsByWeekday = arrivals
                raw.readingByWeekday = reading
            default:
                raw.arrivalsByDay = arrivals
                raw.readingByDay = reading
            }
        }

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

    /// One count per place round a dial, with the places nothing fell in left
    /// at nought rather than missing.
    ///
    /// - Parameter slots: how many places the dial has.
    /// - Parameter first: what SQLite calls the first of them, which is nought
    ///   for an hour and for a weekday and one for a day of the month.
    private static func dial(
        _ db: Database,
        sql: String,
        arguments: StatementArguments,
        slots: Int,
        first: Int
    ) throws -> [Int] {
        var counts = [Int](repeating: 0, count: slots)
        for row in try Row.fetchAll(db, sql: sql, arguments: arguments) {
            guard let slot = row["slot"] as Int? else { continue }
            let place = slot - first
            guard counts.indices.contains(place) else { continue }
            counts[place] = row["count"]
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
        report.stories = raw.stories
        report.storiedArticles = raw.storiedArticles
        report.datedReads = raw.datedReads
        report.previous = raw.previous
        report.subjects = raw.subjects
        report.people = raw.people
        report.bylines = raw.bylines
        report.arrivalsByHour = raw.arrivalsByHour
        report.readingByHour = raw.readingByHour
        report.arrivalsByWeekday = raw.arrivalsByWeekday
        report.readingByWeekday = raw.readingByWeekday
        report.arrivalsByDay = raw.arrivalsByDay
        report.readingByDay = raw.readingByDay
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
