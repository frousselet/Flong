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
    /// The picture that stands for it, which the page runs across its head.
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
        }
    }
}

/// Reads and writes articles.
nonisolated struct ArticleStore: Sendable {
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
                               (SELECT i.image_url FROM entry i
                                WHERE \(ofTheCover) AND i.image_url IS NOT NULL AND i.is_hidden = 0
                                ORDER BY COALESCE(i.published_at, i.received_at) DESC LIMIT 1) AS cover
                        FROM entry e WHERE \(condition) AND e.is_hidden = 0 AND e.duplicate_of IS NULL
                        """
                )
                guard let row, row["count"] as Int > 0 else { return nil }
                return Counted(kind: kind, count: row["count"], cover: row["cover"])
            }
        }

        return counted.map { ArticleCollection(kind: .builtIn($0.kind), count: $0.count, cover: $0.cover) }
    }

    /// Articles served by a publisher the reader singled out.
    ///
    /// A subquery rather than a join : the two callers below count over `entry`
    /// alone, and a condition that needed `feed` at the other end of a join
    /// could not be dropped into either of them.
    private static func fromAFavouriteSource(_ table: String) -> String {
        "\(table).feed_id IN (SELECT id FROM feed WHERE is_favourite = 1)"
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

    /// An article the reader has marked, as the indexer needs it.
    ///
    /// What makes an article worth handing to Spotlight is that the reader did
    /// something to it : starred it, wrote on it, or filed it. Everything else
    /// is a cache, and a system-wide index of a cache is an index of things
    /// nobody chose.
    nonisolated struct Marked: Hashable, Sendable {
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

    /// Every article the reader has marked, for the indexer.
    ///
    /// Narrowed to a few of them when only a few changed, so that starring one
    /// article does not read every mark there is back out of the database.
    func marked(_ ids: [UUID]? = nil) async throws -> [Marked] {
        let narrowing = ids.map { " AND e.id IN (\(databaseQuestionMarks(count: $0.count)))" } ?? ""
        let arguments = StatementArguments(ids ?? [])

        return try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.id AS id, e.title AS title, b.plain_text AS plain_text, e.url AS url,
                           e.author AS author, f.title AS feed_title, f.site_url AS site_url,
                           f.url AS feed_url, e.published_at AS published_at,
                           e.received_at AS received_at
                    FROM entry e
                    JOIN feed f ON f.id = e.feed_id
                    LEFT JOIN entry_body b ON b.entry_id = e.id
                    WHERE e.is_hidden = 0 AND e.duplicate_of IS NULL
                      AND (e.is_starred = 1 OR COALESCE(e.annotation, '') <> ''
                           OR e.id IN (SELECT target_id FROM tag_binding WHERE target_kind = 'entry'))
                    \(narrowing)
                    """,
                arguments: arguments
            )
            .map { row in
                Marked(
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
        var cover: URL?
    }

    private static func condition(for kind: ArticleCollection.Kind) -> (String, StatementArguments) {
        switch kind {
        case .builtIn(.starred): ("e.is_starred = 1", [])
        case .builtIn(.annotated): ("COALESCE(e.annotation, '') <> ''", [])
        case .builtIn(.favouriteSources): (Self.fromAFavouriteSource("e"), [])
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
        }
    }

    // MARK: - Writing

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
