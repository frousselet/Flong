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

/// Where a row in a list comes from.
nonisolated enum ArticleOrigin: String, Hashable, Sendable {
    /// The stream, which is a cache and will be purged.
    case stream
    /// The library, which is a copy and never will be.
    case library
}

/// What a list shows about an article.
///
/// The body is deliberately absent : it is what weighs in the store, and a list
/// of five hundred rows must not carry five hundred articles' worth of markup.
nonisolated struct ArticleSummary: Identifiable, Hashable, Sendable, FetchableRecord {
    let id: UUID
    let origin: ArticleOrigin
    /// The feed a stream article came from. A kept article has the name of its
    /// feed and not a row to point at, the feed itself being unsubscribable.
    let feedID: UUID?
    let feedTitle: String
    let title: String
    let excerpt: String?
    let author: String?
    let date: Date
    var isRead: Bool
    var isStarred: Bool
    let hasMedia: Bool
    let url: URL?
    /// The article's picture, when it has one.
    let imageURL: URL?

    init(row: Row) {
        id = row["id"]
        origin = ArticleOrigin(rawValue: row["origin"] ?? "") ?? .stream
        feedID = row["feed_id"]
        feedTitle = row["feed_title"] ?? ""
        title = row["title"]
        excerpt = row["excerpt"]
        author = row["author"]
        date = row["date"]
        isRead = row["is_read"] ?? true
        isStarred = row["is_starred"] ?? true
        hasMedia = row["has_media"] ?? false
        url = (row["url"] as String?).flatMap(URL.init(string:))
        imageURL = (row["image_url"] as String?).flatMap(URL.init(string:))
    }
}

/// An article as the reader sees it, wherever it was read from.
nonisolated struct Article: Identifiable, Hashable, Sendable {
    let id: UUID
    let origin: ArticleOrigin
    let title: String
    let feedTitle: String
    let author: String?
    let url: URL?
    let publishedAt: Date?
    let language: String?
    var isRead: Bool
    var isStarred: Bool
    let bodyHTML: String?
    let annotation: String?

    init(
        id: UUID,
        origin: ArticleOrigin,
        title: String,
        feedTitle: String,
        author: String? = nil,
        url: URL? = nil,
        publishedAt: Date? = nil,
        language: String? = nil,
        isRead: Bool = true,
        isStarred: Bool = false,
        bodyHTML: String? = nil,
        annotation: String? = nil
    ) {
        self.id = id
        self.origin = origin
        self.title = title
        self.feedTitle = feedTitle
        self.author = author
        self.url = url
        self.publishedAt = publishedAt
        self.language = language
        self.isRead = isRead
        self.isStarred = isStarred
        self.bodyHTML = bodyHTML
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
    case folder(String)

    /// The condition and its arguments, as SQL.
    fileprivate func condition(now: Date) -> (String, StatementArguments) {
        switch self {
        case .all: ("1", [])
        case .unread: ("e.is_read = 0", [])
        case .starred: ("e.is_starred = 1", [])
        case .today: ("COALESCE(e.published_at, e.received_at) >= ?", [Calendar.current.startOfDay(for: now)])
        case .feed(let id): ("e.feed_id = ?", [id])
        case .folder(let path): ("(f.folder = ? OR f.folder LIKE ? ESCAPE '\\')", [path, Self.prefix(of: path)])
        }
    }

    /// A folder holds what is filed under it and under its subfolders.
    private static func prefix(of path: String) -> String {
        let escaped =
            path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return escaped + "/%"
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
        SELECT e.id, 'stream' AS origin, e.feed_id, e.title, e.excerpt, e.author, e.url,
               e.is_read, e.is_starred, e.has_media, e.image_url,
               COALESCE(e.published_at, e.received_at) AS date,
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
                        WHERE entry_fts MATCH ? AND e.is_hidden = 0 AND \(filterCondition)
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
                    WHERE e.is_hidden = 0 AND \(condition)
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
                origin: .stream,
                title: entry.title,
                feedTitle: feed.title,
                author: entry.author,
                url: entry.url,
                publishedAt: entry.publishedAt,
                language: entry.language,
                isRead: entry.isRead,
                isStarred: entry.isStarred,
                bodyHTML: body?.sanitizedHTML
            )
        }
    }

    /// How many unread articles each feed holds, feeds with none excluded.
    func unreadCounts() async throws -> [UUID: Int] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT feed_id, COUNT(*) AS count FROM entry
                    WHERE is_read = 0 AND is_hidden = 0 GROUP BY feed_id
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
                    WHERE e.is_hidden = 0 AND \(condition)
                    """,
                arguments: arguments
            ) ?? 0
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
