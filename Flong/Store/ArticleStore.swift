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
    let feedID: UUID
    let feedTitle: String
    let title: String
    let excerpt: String?
    let author: String?
    let date: Date
    var isRead: Bool
    var isStarred: Bool
    let hasMedia: Bool
    let url: URL?

    init(row: Row) {
        id = row["id"]
        feedID = row["feed_id"]
        feedTitle = row["feed_title"]
        title = row["title"]
        excerpt = row["excerpt"]
        author = row["author"]
        date = row["date"]
        isRead = row["is_read"]
        isStarred = row["is_starred"]
        hasMedia = row["has_media"]
        url = (row["url"] as String?).flatMap(URL.init(string:))
    }
}

/// An article as the reader sees it.
nonisolated struct Article: Identifiable, Hashable, Sendable {
    let entry: Entry
    let feedTitle: String
    let bodyHTML: String?

    var id: UUID { entry.id }
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

    /// The articles of a view, newest first.
    ///
    /// Hidden articles never appear : hiding is what a rule does to something
    /// the reader said they never want to see.
    func summaries(
        _ filter: ArticleFilter,
        limit: Int = 500,
        now: Date = Date()
    ) async throws -> [ArticleSummary] {
        let (condition, arguments) = filter.condition(now: now)

        return try await database.writer.read { db in
            try ArticleSummary.fetchAll(
                db,
                sql: """
                    SELECT e.id, e.feed_id, e.title, e.excerpt, e.author, e.url,
                           e.is_read, e.is_starred, e.has_media,
                           COALESCE(e.published_at, e.received_at) AS date,
                           f.title AS feed_title
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

    /// One article, with its body and the feed it came from.
    func article(id: UUID) async throws -> Article? {
        try await database.writer.read { db in
            guard let entry = try Entry.fetchOne(db, key: id),
                let feed = try Feed.fetchOne(db, key: entry.feedID)
            else { return nil }

            let body = try EntryBody.fetchOne(db, key: id)
            return Article(entry: entry, feedTitle: feed.title, bodyHTML: body?.sanitizedHTML)
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

    func count(_ filter: ArticleFilter, now: Date = Date()) async throws -> Int {
        let (condition, arguments) = filter.condition(now: now)

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
