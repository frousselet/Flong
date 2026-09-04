//
//  ArticleStore.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB

/// What a list shows about an article.
///
/// The body is deliberately absent : it is what weighs in the store, and a list
/// of five hundred rows must not carry five hundred articles' worth of markup.
nonisolated struct ArticleSummary: Identifiable, Hashable, Sendable, FetchableRecord {
    let id: UUID
    let feedID: UUID?
    let feedTitle: String
    let title: String
    let excerpt: String?
    let author: String?
    /// When the article says it was published, or when it reached this device
    /// if it says nothing.
    let date: Date
    /// Whether that date is the publisher's own.
    ///
    /// **Some feeds date nothing.** `Le Parisien` states a build date for the
    /// channel and none for any of its items, so a hundred of its articles have
    /// only the moment they were pulled to sort by. That is the honest answer
    /// and there is no other, but it must not be shown as though the publisher
    /// had said it : a row reading `il y a 2 heures` about an article nobody
    /// dated is telling the reader something nobody knows.
    let isDated: Bool
    /// When the publisher last changed it, where they say so and it is later
    /// than the publication.
    let updatedAt: Date?
    var isRead: Bool
    var isStarred: Bool
    let hasMedia: Bool
    let url: URL?
    /// The article's picture, when it has one.
    let imageURL: URL?
    /// The publisher the article came from, which is what a row shows.
    ///
    /// Its name and its mark are looked up rather than carried here : they
    /// belong to the group and not to the feed, and a reader who renames a
    /// publisher must not have to wait for five hundred rows to be read again.
    let domain: String?

    /// When an article was last changed, where that is later than when it was
    /// published and by more than a moment.
    static func meaningfulUpdate(of entry: Entry) -> Date? {
        guard let updated = entry.updatedAt else { return nil }
        guard let published = entry.publishedAt else { return updated }
        return updated.timeIntervalSince(published) >= ArticleSummary.worthCalling ? updated : nil
    }

    /// How much later an update has to be before it is worth saying.
    ///
    /// A minute. A publisher who stamps the two within seconds of each other
    /// has published, not updated, and a row that said `modifié` about every
    /// article would say nothing at all.
    static let worthCalling: TimeInterval = 60

    init(row: Row) {
        id = row["id"]
        feedID = row["feed_id"]
        feedTitle = row["feed_title"] ?? ""
        title = row["title"]
        excerpt = row["excerpt"]
        author = row["author"]
        isDated = (row["published_at"] as Date?) != nil

        // Only when it is later than the publication and by more than a moment.
        // A publisher who stamps both at the same second, or who republishes a
        // feed without changing anything, has not updated the article, and a
        // row saying so about every article says nothing.
        let published = row["published_at"] as Date?
        let updated = row["updated_at"] as Date?
        updatedAt = updated.flatMap { moment in
            guard let published else { return moment }
            return moment.timeIntervalSince(published) >= ArticleSummary.worthCalling ? moment : nil
        }
        date = row["date"]
        isRead = row["is_read"] ?? true
        isStarred = row["is_starred"] ?? true
        hasMedia = row["has_media"] ?? false
        url = (row["url"] as String?).flatMap(URL.init(string:))
        imageURL = (row["image_url"] as String?).flatMap(URL.init(string:))
        domain = FeedURL.publisher(
            site: (row["site_url"] as String?).flatMap(URL.init(string:)),
            feed: (row["feed_url"] as String?).flatMap(URL.init(string:))
        )
    }
}

/// An article as the reader sees it, wherever it was read from.
nonisolated struct Article: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let feedTitle: String
    /// The publisher it came from, whose name is what the page is headed with.
    let domain: String?
    /// The picture that stands for it, which a row and a story's page show.
    let imageURL: URL?
    let author: String?
    let url: URL?
    let publishedAt: Date?
    /// When the publisher last changed it, where they say so.
    let updatedAt: Date?
    let language: String?
    var isRead: Bool
    var isStarred: Bool
    /// What the feed gave.
    let bodyHTML: String?
    /// What the page gave, when it has been fetched.
    let extractedHTML: String?
    let annotation: String?

    /// Whether there is a fuller version than the feed's to show.
    var hasFullText: Bool { extractedHTML?.isEmpty == false }

    init(
        id: UUID,
        title: String,
        feedTitle: String,
        domain: String? = nil,
        imageURL: URL? = nil,
        author: String? = nil,
        url: URL? = nil,
        publishedAt: Date? = nil,
        updatedAt: Date? = nil,
        language: String? = nil,
        isRead: Bool = true,
        isStarred: Bool = false,
        bodyHTML: String? = nil,
        extractedHTML: String? = nil,
        annotation: String? = nil
    ) {
        self.id = id
        self.title = title
        self.feedTitle = feedTitle
        self.domain = domain
        self.imageURL = imageURL
        self.author = author
        self.url = url
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
        self.language = language
        self.isRead = isRead
        self.isStarred = isStarred
        self.bodyHTML = bodyHTML
        self.extractedHTML = extractedHTML
        self.annotation = annotation
    }
}

/// Which articles a view is about.
nonisolated enum ArticleFilter: Hashable, Sendable {
    case all
    case unread
    case starred
    case today
    case feed(UUID)
    /// Every feed of one publisher, which is what a group of the sources list
    /// shows. The members are passed rather than the address : the grouping is
    /// worked out from the feeds themselves and never stored on a row.
    case feeds([UUID])
    /// Everything one writer signed, matched on the name exactly : an author is
    /// a name and Flong never guesses that two spellings are one person. Asked
    /// of the people beside an article rather than of its byline, since one
    /// byline names two of them as often as not. See ``Author``.
    case author(String)
    /// Everything written about one person, matched on the name exactly and for
    /// the same reason. Who an article is about is no field a feed carries : it
    /// is read out of the prose, and the rows it is asked of are what
    /// ``NewsmakerStore`` writes. See ``Newsmaker``.
    case newsmaker(String)

    /// The condition and its arguments, as SQL.
    fileprivate func condition(now: Date) -> (String, StatementArguments) {
        switch self {
        case .all: ("1", [])
        case .unread: ("e.is_read = 0", [])
        case .starred: ("e.is_starred = 1", [])
        case .today: ("COALESCE(e.published_at, e.received_at) >= ?", [Calendar.current.startOfDay(for: now)])
        case .feed(let id): ("e.feed_id = ?", [id])
        case .feeds(let ids):
            // A group with nothing in it is not a group, but a view can outlive
            // the last of its feeds by a moment, and `IN ()` is not SQL.
            ids.isEmpty
                ? ("0", [])
                : ("e.feed_id IN (\(databaseQuestionMarks(count: ids.count)))", StatementArguments(ids))
        case .author(let name): (AuthorStore.signedBy("e"), [name])
        case .newsmaker(let name): (NewsmakerStore.about("e"), [name])
        }
    }
}

/// Reads and writes articles.
nonisolated struct ArticleStore: Sendable {
    /// How many arrivals one notice is ever counted out of.
    ///
    /// **A safety valve and not a sentence's worth.** It was twenty, with the
    /// watermark stamped from the last row read so the rest waited for the next
    /// pass. That cannot work : a feed's articles are all written in one go and
    /// share one `received_at` to the millisecond, so the cut falls inside a
    /// group of equal stamps far more often than not, and a mark set to that
    /// stamp skips every sibling that did not fit while a mark set just below it
    /// announces the whole group again, for ever.
    ///
    /// So the mark stays the clock, and the bound is high enough that reaching
    /// it means a pass nobody could write a sentence about anyway. What the
    /// notice *names* is bounded separately, by ``Announcement`` : the count is
    /// the whole truth and the list is the part that fits.
    static let mostBeforeAnnouncing = 200

    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    // MARK: - Reading

    /// The columns a list needs, whichever way the rows were found.
    static let columns = """
        SELECT e.id, e.feed_id, e.title, e.excerpt, e.author, e.url,
               e.is_read, e.is_starred, e.has_media, e.image_url,
               f.site_url, f.url AS feed_url,
               COALESCE(e.published_at, e.received_at) AS date,
               e.published_at AS published_at, e.updated_at AS updated_at,
               f.title AS feed_title
        """

    /// The articles of a view, newest first.
    ///
    /// Hidden articles never appear : hiding is what a rule does to something
    /// the reader said they never want to see.
    ///
    /// A query narrows the view further. When the whole of it is answered by the
    /// index, the rows come back ranked : a word in a title says far more than
    /// the same word in a body, and a reader searching for something wants the
    /// article about it before the one that mentions it. Anything the index
    /// cannot answer whole is ordered by date, which is the honest fallback.
    func summaries(
        _ filter: ArticleFilter,
        matching query: QueryNode? = nil,
        limit: Int = 500,
        now: Date = Date()
    ) async throws -> [ArticleSummary] {
        let (condition, arguments) = self.condition(filter, query: query, now: now)

        if let query, let match = QueryCompiler.compile(query, now: now).matchExpression {
            let (filterCondition, filterArguments) = filter.condition(now: now)

            return try await database.writer.read { db in
                try ArticleSummary.fetchAll(
                    db,
                    sql: """
                        \(Self.columns)
                        FROM entry_fts
                        JOIN entry e ON e.rowid = entry_fts.rowid
                        JOIN feed f ON f.id = e.feed_id
                        WHERE entry_fts MATCH ? AND e.is_hidden = 0 AND e.duplicate_of IS NULL
                          AND \(filterCondition)
                        ORDER BY \(QueryCompiler.ranking)
                        LIMIT \(limit)
                        """,
                    arguments: [match] + filterArguments
                )
            }
        }

        return try await database.writer.read { db in
            try ArticleSummary.fetchAll(
                db,
                sql: """
                    \(Self.columns)
                    FROM entry e
                    JOIN feed f ON f.id = e.feed_id
                    WHERE e.is_hidden = 0 AND e.duplicate_of IS NULL AND \(condition)
                    ORDER BY date DESC
                    LIMIT \(limit)
                    """,
                arguments: arguments
            )
        }
    }

    /// The reader's own copies of pieces somebody shared, by the key that says
    /// two articles are the same article.
    ///
    /// **What a shared collection shows instead of the excerpt.** A recipient
    /// who follows the same source already holds the article, with its body,
    /// its read state and whatever they have said about it ; showing them the
    /// sender's three hundred characters of it would be showing them less than
    /// they have. ``ArticleKey`` is what answers whether the two are one piece,
    /// and it is already computed on every row at ingestion.
    func summaries(matchingKeys keys: [String]) async throws -> [String: ArticleSummary] {
        guard !keys.isEmpty else { return [:] }

        return try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    \(Self.columns), e.canonical_key AS canonical_key
                    FROM entry e
                    JOIN feed f ON f.id = e.feed_id
                    WHERE e.is_hidden = 0 AND e.duplicate_of IS NULL
                      AND e.canonical_key IN (\(databaseQuestionMarks(count: keys.count)))
                    """,
                arguments: StatementArguments(keys)
            )
            .reduce(into: [:]) { found, row in
                guard let key = row["canonical_key"] as String? else { return }
                found[key] = ArticleSummary(row: row)
            }
        }
    }

    /// The view and the query, as one condition.
    private func condition(
        _ filter: ArticleFilter,
        query: QueryNode?,
        now: Date
    ) -> (String, StatementArguments) {
        let (condition, arguments) = filter.condition(now: now)
        guard let query else { return (condition, arguments) }

        let compiled = QueryCompiler.compile(query, now: now)
        return ("(\(condition)) AND (\(compiled.condition))", arguments + compiled.arguments)
    }

    /// One article of the stream, with its body and the feed it came from.
    func article(id: UUID) async throws -> Article? {
        try await database.writer.read { db in
            guard let entry = try Entry.fetchOne(db, key: id),
                let feed = try Feed.fetchOne(db, key: entry.feedID)
            else { return nil }

            let body = try EntryBody.fetchOne(db, key: id)
            return Article(
                id: entry.id,
                title: entry.title,
                feedTitle: feed.title,
                domain: feed.domain,
                imageURL: entry.imageURL,
                author: entry.author,
                url: entry.url,
                publishedAt: entry.publishedAt,
                updatedAt: ArticleSummary.meaningfulUpdate(of: entry),
                language: entry.language,
                isRead: entry.isRead,
                isStarred: entry.isStarred,
                bodyHTML: body?.sanitizedHTML,
                extractedHTML: body?.extractedHTML,
                annotation: entry.annotation
            )
        }
    }

    /// How many unread articles each feed holds, feeds with none excluded.
    func unreadCounts() async throws -> [UUID: Int] {
        try await counts(unreadOnly: true)
    }

    /// How many articles each feed holds, feeds with none excluded.
    ///
    /// **What the sources list counts, and it counts everything.** It said what
    /// was unread, which is a number that only ever grows and that nobody owes
    /// their feeds : a reader looking down the list wants to know how much a
    /// publisher has given them, not how much of it they are behind on.
    func counts() async throws -> [UUID: Int] {
        try await counts(unreadOnly: false)
    }

    private func counts(unreadOnly: Bool) async throws -> [UUID: Int] {
        let unread = unreadOnly ? "is_read = 0 AND " : ""

        return try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT feed_id, COUNT(*) AS count FROM entry
                    WHERE \(unread)is_hidden = 0 AND duplicate_of IS NULL GROUP BY feed_id
                    """
            )
            return Dictionary(uniqueKeysWithValues: rows.map { ($0["feed_id"] as UUID, $0["count"] as Int) })
        }
    }

    func count(_ filter: ArticleFilter, matching query: QueryNode? = nil, now: Date = Date()) async throws -> Int {
        let (condition, arguments) = self.condition(filter, query: query, now: now)

        return try await database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM entry e JOIN feed f ON f.id = e.feed_id
                    WHERE e.is_hidden = 0 AND e.duplicate_of IS NULL AND \(condition)
                    """,
                arguments: arguments
            ) ?? 0
        }
    }

    /// How many articles arrived in each hour of a view, keyed by the hour.
    ///
    /// **A local hour, not a slice of UTC.** A reader in Paris opening this at
    /// one in the morning is still looking at last night's wire, and a chart
    /// that disagrees is a chart about a timezone rather than about them.
    /// SQLite is handed the reader's own offset, which is what `localtime` is,
    /// and the hour it answers with is read back in the same offset.
    ///
    /// **Grouped by the database rather than in Swift.** A season of a busy
    /// corpus is tens of thousands of rows and all that is wanted from them is
    /// one number per hour : fetching the dates to count them here would carry
    /// the whole stream across for the sake of a few dozen integers.
    func hourlyCounts(
        _ filter: ArticleFilter,
        matching query: QueryNode? = nil,
        now: Date = Date()
    ) async throws -> [Date: Int] {
        let (condition, arguments) = self.condition(filter, query: query, now: now)

        // The rows are turned into something `Sendable` inside the block, which
        // is what picks GRDB's asynchronous read : a block that hands a `Row`
        // back picks the synchronous one instead and reads the database on
        // whichever thread asked, and here that is the one drawing the screen.
        let counted: [String: Int] = try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT strftime('%Y-%m-%d %H', COALESCE(e.published_at, e.received_at), 'localtime') AS day,
                           COUNT(*) AS count
                    FROM entry e JOIN feed f ON f.id = e.feed_id
                    WHERE e.is_hidden = 0 AND e.duplicate_of IS NULL AND \(condition)
                    GROUP BY day
                    """,
                arguments: arguments
            )
            return Dictionary(
                uniqueKeysWithValues: rows.compactMap { row in
                    (row["day"] as String?).map { ($0, row["count"] as Int) }
                })
        }

        // Built here rather than held as a static : a formatter is not `Sendable`,
        // and this is asked for once when a view loads, not once per row.
        let midnight = DateFormatter()
        midnight.locale = Locale(identifier: "en_US_POSIX")
        midnight.calendar = Calendar(identifier: .gregorian)
        midnight.timeZone = .current
        midnight.dateFormat = "yyyy-MM-dd HH"

        var counts: [Date: Int] = [:]
        for (day, count) in counted {
            guard let start = midnight.date(from: day) else { continue }
            counts[start] = count
        }
        return counts
    }

    // MARK: - The reader's own marks

    /// Writes what the reader thinks of an article.
    ///
    /// An empty note is no note : it takes the article out of the notes rather
    /// than putting an empty string in them.
    func annotate(_ entryID: UUID, with note: String?) async throws {
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines)

        try await database.writer.write { db in
            _ = try Entry.filter(key: entryID).updateAll(
                db,
                Column("annotation").set(to: (note?.isEmpty ?? true) ? nil : note)
            )
        }
    }

    func annotation(of entryID: UUID) async throws -> String? {
        try await database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT annotation FROM entry WHERE id = ?", arguments: [entryID])
        }
    }

    /// The collections every reader has, which are questions the articles
    /// answer about themselves.
    func builtInCollections() async throws -> [ArticleCollection] {
        let counted: [Counted] = try await database.writer.read { db in
            let deliberate: [(ArticleCollection.BuiltIn, String, String)] = [
                (.starred, "e.is_starred = 1", "i.is_starred = 1"),
                // Next to the star, and deliberately : the two are different
                // judgements, and a page that showed them apart would leave the
                // reader to work out that they are not the same one.
                (.favouriteSources, Self.fromAFavouriteSource("e"), Self.fromAFavouriteSource("i")),
                (.annotated, "COALESCE(e.annotation, '') <> ''", "COALESCE(i.annotation, '') <> ''"),
            ]
            return try deliberate.compactMap { kind, condition, ofTheCover in
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) AS count,
                               \(CollectionCovers.sql(where: "\(ofTheCover) AND i.is_hidden = 0")) AS covers
                        FROM entry e WHERE \(condition) AND e.is_hidden = 0 AND e.duplicate_of IS NULL
                        """
                )
                guard let row, row["count"] as Int > 0 else { return nil }
                return Counted(kind: kind, count: row["count"], covers: CollectionCovers.read(row["covers"]))
            }
        }

        return counted.map { ArticleCollection(kind: .builtIn($0.kind), count: $0.count, covers: $0.covers) }
    }

    /// Articles served by a publisher the reader singled out.
    ///
    /// A subquery rather than a join : the two callers below count over `entry`
    /// alone, and a condition that needed `feed` at the other end of a join
    /// could not be dropped into either of them.
    private static func fromAFavouriteSource(_ table: String) -> String {
        "\(table).feed_id IN (SELECT id FROM feed WHERE is_favourite = 1)"
    }

    /// How many articles one favourite is worth to the system index.
    ///
    /// **A star is a decision about an article ; a favourite is a decision
    /// about everything that follows from it.** The first bounds itself : a
    /// reader stars, annotates and files a few thousand articles in years,
    /// which is exactly the size Core Spotlight is good at. The second does
    /// not. A favourite daily serving forty articles a day is fifteen thousand
    /// items within the year, on its own, and section 11 of the specification
    /// budgets a few thousand in total, beyond which the system search
    /// degrades for everything the device holds and not only for Flong.
    ///
    /// So a favourite is worth its most recent articles and no more. The index
    /// is then bounded by the number of favourites rather than by the size of
    /// the corpus, which is the only bound a reader controls. It costs them
    /// nothing they cannot reach another way : Flong's own search covers every
    /// article ever stored, and Spotlight was never the primary index.
    ///
    /// It bites hardest exactly where it was meant to. Two hundred and fifty
    /// articles is five days of a firehose and five years of a weekly, and a
    /// favourite writer almost never has that many to their name at all.
    static let perFavourite = 250

    /// The identifier of every article the reader chose.
    ///
    /// **Five ways of choosing, written once.** Three are about the article
    /// itself and are made one article at a time : a star, a note, a filing.
    /// Two are made once and stand for everything that follows : a publisher
    /// singled out, a writer singled out. All five are the reader saying this
    /// one, and none of them is the stream saying it.
    ///
    /// It is deliberately wider than ``Retention/marked``, which is what a
    /// purge may not take. A favourite is a judgement about a source or a
    /// writer rather than about an article, so it earns an article a place in
    /// the system search without earning it a place a purge has to work
    /// around. It is deliberately narrower than the favourites' own
    /// collections, which hold everything : the cap is what the system index
    /// can carry, not what the reader chose.
    ///
    /// **A table expression rather than a condition**, because the two capped
    /// ways ask where an article stands among its neighbours rather than
    /// anything about the article. `ORDER BY date DESC LIMIT n` cannot answer
    /// that : it is one list, and this needs one per source and one per writer.
    /// The rank is broken by the identifier where two articles share a date, so
    /// that the cut falls in the same place at every reading and an index that
    /// has not changed is not written again.
    private static func choice(perFavourite: Int) -> String {
        """
        chosen(id) AS (
            SELECT e.id FROM entry e
            WHERE \(shown("e"))
              AND (e.is_starred = 1 OR COALESCE(e.annotation, '') <> ''
                   OR e.id IN (SELECT target_id FROM tag_binding WHERE target_kind = 'entry'))
            UNION
            SELECT id FROM (
                SELECT e.id AS id, ROW_NUMBER() OVER (
                    PARTITION BY e.feed_id
                    ORDER BY COALESCE(e.published_at, e.received_at) DESC, e.id DESC
                ) AS place
                FROM entry e WHERE \(shown("e")) AND \(fromAFavouriteSource("e"))
            ) WHERE place <= \(perFavourite)
            UNION
            SELECT id FROM (
                SELECT a.entry_id AS id, ROW_NUMBER() OVER (
                    PARTITION BY a.name
                    ORDER BY COALESCE(e.published_at, e.received_at) DESC, e.id DESC
                ) AS place
                FROM entry_author a JOIN entry e ON e.id = a.entry_id
                WHERE \(shown("e")) AND a.name IN (SELECT name FROM favourite_author)
            ) WHERE place <= \(perFavourite)
            UNION
            SELECT id FROM (
                SELECT m.entry_id AS id, ROW_NUMBER() OVER (
                    PARTITION BY m.name
                    ORDER BY COALESCE(e.published_at, e.received_at) DESC, e.id DESC
                ) AS place
                FROM entry_newsmaker m JOIN entry e ON e.id = m.entry_id
                WHERE \(shown("e")) AND m.name IN (SELECT name FROM favourite_newsmaker)
            ) WHERE place <= \(perFavourite)
        )
        """
    }

    /// What is not a duplicate and was not hidden by a rule.
    private static func shown(_ table: String) -> String {
        "\(table).is_hidden = 0 AND \(table).duplicate_of IS NULL"
    }

    /// What is in one collection of the first two natures, newest first.
    ///
    /// A dynamic one is not here : it is a description, answered by the ordinary
    /// query path, and it would be strange for a description to be a case in a
    /// list of memberships.
    func summaries(in collection: ArticleCollection.Kind, limit: Int = 500) async throws -> [ArticleSummary] {
        let (condition, arguments) = Self.condition(for: collection)

        return try await database.writer.read { db in
            try ArticleSummary.fetchAll(
                db,
                sql: """
                    \(Self.columns)
                    FROM entry e JOIN feed f ON f.id = e.feed_id
                    WHERE e.is_hidden = 0 AND e.duplicate_of IS NULL AND \(condition)
                    ORDER BY date DESC LIMIT \(limit)
                    """,
                arguments: arguments
            )
        }
    }

    /// An article the reader chose, as the indexer needs it.
    ///
    /// What makes an article worth handing to Spotlight is that the reader
    /// chose it, one way or another : see ``wasChosen(_:)`` for the five of
    /// them. Everything else is a cache, and a system-wide index of a cache is
    /// an index of things nobody chose.
    nonisolated struct Chosen: Hashable, Sendable {
        var id: UUID
        var title: String
        var plainText: String?
        var url: URL?
        var author: String?
        var feedTitle: String?
        /// The publisher it came from, so the system index names an article's
        /// source the way the application does.
        var domain: String?
        var publishedAt: Date?
        var markedAt: Date
    }

    /// One chosen article, named and dated and nothing else.
    ///
    /// What asking whether Spotlight is up to date is allowed to cost. The
    /// answer is almost always yes, and reading a corpus of full texts back out
    /// of the store to arrive at it would cost more than the rebuild it decided
    /// against.
    nonisolated struct Choice: Hashable, Sendable {
        var id: UUID
        var chosenAt: Date
    }

    /// What the index should be holding, without what it should be holding
    /// about it.
    ///
    /// In the store's own order, which is the identifier, so that two readings
    /// of one unchanged store are two identical answers.
    func choices(perFavourite: Int = ArticleStore.perFavourite) async throws -> [Choice] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    WITH \(Self.choice(perFavourite: perFavourite))
                    SELECT e.id AS id, e.received_at AS received_at
                    FROM entry e JOIN chosen c ON c.id = e.id
                    ORDER BY e.id
                    """
            )
            .map { Choice(id: $0["id"], chosenAt: $0["received_at"]) }
        }
    }

    /// Every article the reader chose, for the indexer.
    ///
    /// Narrowed to a few of them when only a few changed, so that starring one
    /// article does not read every mark there is back out of the database.
    func chosen(_ ids: [UUID]? = nil, perFavourite: Int = ArticleStore.perFavourite) async throws -> [Chosen] {
        let narrowing = ids.map { " WHERE e.id IN (\(databaseQuestionMarks(count: $0.count)))" } ?? ""
        let arguments = StatementArguments(ids ?? [])

        return try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    WITH \(Self.choice(perFavourite: perFavourite))
                    SELECT e.id AS id, e.title AS title, b.plain_text AS plain_text, e.url AS url,
                           e.author AS author, f.title AS feed_title, f.site_url AS site_url,
                           f.url AS feed_url, e.published_at AS published_at,
                           e.received_at AS received_at
                    FROM entry e
                    JOIN chosen c ON c.id = e.id
                    JOIN feed f ON f.id = e.feed_id
                    LEFT JOIN entry_body b ON b.entry_id = e.id
                    \(narrowing)
                    """,
                arguments: arguments
            )
            .map { row in
                Chosen(
                    id: row["id"],
                    title: row["title"],
                    plainText: row["plain_text"],
                    url: (row["url"] as String?).flatMap(URL.init(string:)),
                    author: row["author"],
                    feedTitle: row["feed_title"],
                    domain: FeedURL.publisher(
                        site: (row["site_url"] as String?).flatMap(URL.init(string:)),
                        feed: (row["feed_url"] as String?).flatMap(URL.init(string:))
                    ),
                    publishedAt: row["published_at"],
                    markedAt: row["received_at"]
                )
            }
        }
    }

    private struct Counted: Sendable {
        var kind: ArticleCollection.BuiltIn
        var count: Int
        var covers: [URL]
    }

    private static func condition(for kind: ArticleCollection.Kind) -> (String, StatementArguments) {
        switch kind {
        case .builtIn(.starred): ("e.is_starred = 1", [])
        case .builtIn(.annotated): ("COALESCE(e.annotation, '') <> ''", [])
        case .builtIn(.favouriteSources): (Self.fromAFavouriteSource("e"), [])
        case .builtIn(.favouriteAuthors): (AuthorStore.byAFavouriteAuthor("e"), [])
        case .builtIn(.favouriteNewsmakers): (NewsmakerStore.aboutAFavourite("e"), [])
        // A directory of people rather than a set of articles : the square
        // opens on ``AuthorsScreen``, and there is no list of articles for it
        // to answer. Nothing asks this, and it says nothing rather than
        // quietly answering the whole stream.
        case .builtIn(.authors): ("0", [])
        // The other directory, and the same answer for the same reason : it
        // opens on ``NewsmakersScreen``, which is a list of names.
        case .builtIn(.newsmakers): ("0", [])
        case .made(let name):
            (
                """
                e.id IN (
                    SELECT b.target_id FROM tag_binding b JOIN tag t ON t.id = b.tag_id
                    WHERE b.target_kind = 'entry' AND t.path = ?
                )
                """,
                [CollectionStore.path(of: name)]
            )
        // A dynamic one is a description, answered by the ordinary query path.
        case .dynamic: ("0", [])
        // One somebody else shared holds nothing of this store's : what is in
        // it came from feeds the reader does not follow and lives in
        // `shared_entry`. Answering the whole stream here would show them their
        // own articles under another person's name.
        case .shared: ("0", [])
        }
    }

    /// The addresses of one feed's recent articles.
    ///
    /// What the reader is shown when they are asked which parameters of a
    /// feed's addresses are theirs : the question can only be answered against
    /// real addresses, and the ones that matter are the articles', which are
    /// written down exactly as the publisher spelled them.
    ///
    /// A sample rather than all of them. A parameter a feed uses is on every
    /// link it serves, so a hundred answers the question as well as a hundred
    /// thousand and costs nothing.
    func addresses(ofFeed feedID: UUID, limit: Int = 100) async throws -> [URL] {
        try await database.writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT url FROM entry
                    WHERE feed_id = ? AND url IS NOT NULL
                    ORDER BY received_at DESC LIMIT ?
                    """,
                arguments: [feedID, limit]
            )
            .compactMap(URL.init(string:))
        }
    }

    /// One article the reader asked to be told about, whether they asked of the
    /// source or of whoever signed it.
    ///
    /// What a notice needs and nothing else : what to say, what to say it came
    /// from, the picture to say it beside, and where a tap lands. A summary
    /// would carry an excerpt and a read state on top of that, neither of which
    /// a notification has anywhere to put.
    nonisolated struct Arrival: Identifiable, Hashable, Sendable {
        let id: UUID
        let title: String
        /// What the source is called.
        let source: String
        /// The picture that stands for the article, when it has one.
        ///
        /// The address the feed stated or the one read out of the body, which
        /// is the same picture the row in the list carries : a notice showing
        /// one thing and the article it opens showing another would be two
        /// articles as far as the reader can tell.
        let picture: URL?
        /// The writer the reader asked about who signed it, when that is why it
        /// is here at all.
        ///
        /// `nil` for an article that arrived because of its source. It is never
        /// the whole byline : what the notice names is the person the reader
        /// asked about, and a piece signed by four people where they asked
        /// about one is news about that one.
        let author: String?

        /// The person the reader asked about whom the article names, when that
        /// is why it is here at all.
        ///
        /// `nil` for an article that arrived because of its source or its
        /// byline. A piece naming four people where the reader asked about one
        /// is news about that one. See ``Newsmaker``.
        let newsmaker: String?

        /// What the reader asked about, which is what a notice about several of
        /// these counts them under.
        ///
        /// A person where there is one, since a person is the more precise of
        /// the answers and the one the reader chose to follow across every
        /// paper. The writer before the subject where an article is somehow
        /// both : a byline is what the feed itself stated, and who a piece is
        /// about is what Flong read out of it.
        var subject: String { author ?? newsmaker ?? source }

        /// Written out rather than left to the memberwise one, so that the two
        /// people are optional at the call site : an arrival brought in by its
        /// source names neither, which is the ordinary case.
        init(
            id: UUID,
            title: String,
            source: String,
            picture: URL? = nil,
            author: String? = nil,
            newsmaker: String? = nil
        ) {
            self.id = id
            self.title = title
            self.source = source
            self.picture = picture
            self.author = author
            self.newsmaker = newsmaker
        }
    }

    /// What the reader asked to be told about has published since a moment,
    /// oldest first.
    ///
    /// **One question and not three, which is what keeps an article from being
    /// announced twice.** A writer the reader follows very often writes for a
    /// source they follow as well, and writes about somebody they follow on top
    /// of that ; asking the questions separately would put that article in
    /// every answer, and the reader would be told about one piece three times
    /// over. It is one row here whichever of the three brought it, and a person
    /// leads the wording since asking about somebody is the most particular of
    /// the requests.
    ///
    /// **When it arrived here, and not when it was published.** A source that
    /// backfills a month of articles published them a month ago and served them
    /// tonight, and a notice about the ones dated today would be silent about
    /// everything the reader actually just received.
    ///
    /// **And what another device has read is what keeps a synchronization
    /// quiet.** An exchange with another of the reader's devices, or a repair
    /// that reads the shared archives again, writes a fortnight of articles in
    /// one go, and they did all reach this device just now. Almost every one of
    /// them was read on the device that fetched them, so `is_read = 0` takes
    /// them out ; what is left is news the reader has not seen anywhere, which
    /// is exactly what a notice is for. Holding them to a floor on their own
    /// date instead would silence a backfilled feed, which the paragraph above
    /// exists to prevent.
    ///
    /// What is hidden, what is a second copy of an article already here and
    /// what another device has already read are all left out : a rule the
    /// reader wrote to never see something is not undone by a notification, the
    /// same article arriving through two of one newsroom's feeds is one piece
    /// of news, and being told about what they read on the iPad an hour ago is
    /// worse than not being told.
    ///
    /// **Every feed, where the reader asked for every feed.** The switch on a
    /// source is the finer instrument and stays exactly as it was ; the panel's
    /// own switch says the same thing about all of them at once, and passing it
    /// here is what keeps the two one question rather than two answers to
    /// reconcile.
    ///
    /// **What has not been told yet, and never what arrived after a moment.**
    /// The watermark was right for one sentence about everything a pass
    /// brought : the pass read the arrivals, said one thing, and moved the
    /// mark. Said one at a time it cannot be : the read is bounded against
    /// absurdity, and a mark moved past what the bound left behind loses the
    /// rest for good. `entry.announced_at` is the queue, so nothing is lost
    /// and nothing is said twice by construction rather than by arithmetic.
    ///
    /// - Parameter limit: how many are posted at most in one go. A bound on the
    ///   burst rather than on the news : what it does not reach stays in the
    ///   queue and is said by the next pass, which is seconds away.
    func unannounced(
        fromEveryFeed everyFeed: Bool = false,
        limit: Int = mostBeforeAnnouncing
    ) async throws -> [Arrival] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.id AS id, e.title AS title, f.title AS source,
                           e.image_url AS image_url,
                           (SELECT a.name FROM entry_author a
                            JOIN notified_author n ON n.name = a.name
                            WHERE a.entry_id = e.id
                            ORDER BY a.position LIMIT 1) AS author,
                           -- Most named first : an article about two people the
                           -- reader follows is announced under the one it is
                           -- really about.
                           (SELECT m.name FROM entry_newsmaker m
                            JOIN notified_newsmaker w ON w.name = m.name
                            WHERE m.entry_id = e.id
                            ORDER BY m.mentions DESC, m.name LIMIT 1) AS newsmaker
                    FROM entry e
                    JOIN feed f ON f.id = e.feed_id
                    WHERE e.announced_at IS NULL
                      AND e.is_hidden = 0 AND e.duplicate_of IS NULL AND e.is_read = 0
                      AND (
                            ?
                            OR f.notifies_new_articles = 1
                            OR EXISTS (
                                SELECT 1 FROM entry_author a
                                JOIN notified_author n ON n.name = a.name
                                WHERE a.entry_id = e.id
                            )
                            OR EXISTS (
                                SELECT 1 FROM entry_newsmaker m
                                JOIN notified_newsmaker w ON w.name = m.name
                                WHERE m.entry_id = e.id
                            )
                          )
                    ORDER BY e.received_at
                    LIMIT ?
                    """,
                arguments: [everyFeed, limit]
            )
            .map { row in
                Arrival(
                    id: row["id"],
                    title: row["title"],
                    source: row["source"] ?? "",
                    picture: (row["image_url"] as String?).flatMap(URL.init(string:)),
                    author: row["author"],
                    newsmaker: row["newsmaker"]
                )
            }
        }
    }

    // MARK: - Writing

    /// Says the reader has been told about these, whether a notice went out or
    /// not.
    ///
    /// **Whether or not**, exactly as the watermark it replaces moved either
    /// way. A reader looking at the page an article lands on has seen it, and
    /// being told tomorrow about what they read today is worse than not being
    /// told at all.
    func markAnnounced(_ ids: [UUID], at date: Date = Date()) async throws {
        guard !ids.isEmpty else { return }

        try await database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE entry SET announced_at = ?
                    WHERE id IN (\(databaseQuestionMarks(count: ids.count)))
                    """,
                arguments: StatementArguments([date] + ids.map { $0.databaseValue })
            )
        }
    }

    /// Says the reader has been told about everything waiting, without saying
    /// anything.
    ///
    /// What a switch turned on for the first time does : a source's back
    /// catalogue is not news, and the reader asking to hear about a publisher
    /// is asking about what that publisher does next.
    func markEverythingAnnounced(at date: Date = Date()) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE entry SET announced_at = ? WHERE announced_at IS NULL",
                arguments: [date]
            )
        }
    }

    /// Marks articles read or unread.
    ///
    /// Section 5 of the specification asks the interface never to wait on the
    /// network to reflect a tap ; nothing here does, and there is no server to
    /// wait for in the first place.
    func setRead(_ ids: [UUID], to isRead: Bool, at date: Date = Date()) async throws {
        guard !ids.isEmpty else { return }

        try await database.writer.write { db in
            _ =
                try Entry
                .filter(keys: ids)
                .updateAll(db, [Column("is_read").set(to: isRead), Column("read_at").set(to: isRead ? date : nil)])
        }
    }

    func setStarred(_ ids: [UUID], to isStarred: Bool) async throws {
        guard !ids.isEmpty else { return }

        try await database.writer.write { db in
            _ = try Entry.filter(keys: ids).updateAll(db, Column("is_starred").set(to: isStarred))
        }
    }

    /// Marks a whole view read, which is how a reader gives up on a backlog.
    @discardableResult
    func markRead(_ filter: ArticleFilter, at date: Date = Date(), now: Date = Date()) async throws -> Int {
        let (condition, arguments) = filter.condition(now: now)

        return try await database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE entry SET is_read = 1, read_at = ?
                    WHERE is_read = 0 AND id IN (
                        SELECT e.id FROM entry e JOIN feed f ON f.id = e.feed_id WHERE \(condition)
                    )
                    """,
                arguments: [date] + arguments
            )
            return db.changesCount
        }
    }
}
