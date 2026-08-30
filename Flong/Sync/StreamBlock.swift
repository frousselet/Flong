//
//  StreamBlock.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import OSLog

/// A day of one feed, as it travels.
///
/// One definition of what an article looks like on the wire, whichever way it
/// goes : the records of section 7 and the archives of the iCloud Documents
/// container carry the same thing, and a second definition would be a second
/// chance to disagree about it.
nonisolated enum StreamBlock {
    /// One article, whole.
    ///
    /// The body travels compressed, the same way a kept article's does. Markup
    /// compresses to about a fifth, which is what makes a day of a feed fit
    /// anywhere at all.
    nonisolated struct Header: Hashable, Sendable, Codable {
        let guid: String
        let title: String
        let url: String?
        let publishedAt: Date?
        var author: String?
        var excerpt: String?
        var imageURL: String?
        var hasMedia: Bool?
        var language: String?
        /// The sanitized article, compressed.
        var body: Data?
    }

    /// One feed's articles for one day.
    nonisolated struct Group: Sendable {
        let url: URL
        let day: String
        var headers: [Header]
    }

    /// How much of the reader's own JSON one article is worth.
    ///
    /// Every field, and the body as base64 : JSON carries a `Data` at four
    /// bytes for every three, and an article's excerpt is as long as its body
    /// when nothing has trimmed it. Weighing the body alone put a chunk at
    /// twice the limit it was cut to.
    static func weight(of header: Header) -> Int {
        (header.body?.count ?? 0) * 4 / 3
            + header.title.utf8.count
            + (header.excerpt?.utf8.count ?? 0)
            + (header.author?.utf8.count ?? 0)
            + (header.url?.utf8.count ?? 0)
            + (header.imageURL?.utf8.count ?? 0)
            + header.guid.utf8.count
            + 256
    }

    // MARK: - Reading the store

    /// The articles of every day this device has touched since a moment.
    ///
    /// **The days are found first, then filled whole.** A block stands for a
    /// day, so one built from only the articles that arrived since the last
    /// push would replace a complete day with a partial one. What `since`
    /// narrows is which days are worth writing again, and each of those is then
    /// read out in full.
    static func groups(in database: AppDatabase, since: Date = .distantPast) async throws -> [Group] {
        try await database.writer.read { db in
            let touched = try Row.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT e.feed_id AS feed_id,
                           SUBSTR(COALESCE(e.published_at, e.received_at), 1, 10) AS day
                    FROM entry e
                    WHERE e.received_at >= ?
                    """,
                arguments: [since]
            )
            guard !touched.isEmpty else { return [] }

            var grouped: [String: Group] = [:]
            for pair in touched {
                let feedID: UUID = pair["feed_id"]
                let day: String = pair["day"]

                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT f.url AS feed_url, e.guid AS guid, e.title AS title, e.url AS url,
                               e.published_at AS published_at, e.author AS author, e.excerpt AS excerpt,
                               e.image_url AS image_url, e.has_media AS has_media, e.language AS language,
                               b.sanitized_html AS body
                        FROM entry e
                        JOIN feed f ON f.id = e.feed_id
                        LEFT JOIN entry_body b ON b.entry_id = e.id
                        WHERE e.feed_id = ?
                          AND SUBSTR(COALESCE(e.published_at, e.received_at), 1, 10) = ?
                          AND e.is_hidden = 0
                        ORDER BY COALESCE(e.published_at, e.received_at)
                        """,
                    arguments: [feedID, day]
                )
                guard let url = (rows.first?["feed_url"] as String?).flatMap(URL.init(string:)) else { continue }

                grouped[url.absoluteString + "|" + day] = Group(
                    url: url,
                    day: day,
                    headers: rows.map { row in
                        Header(
                            guid: row["guid"],
                            title: row["title"],
                            url: row["url"],
                            publishedAt: row["published_at"],
                            author: row["author"],
                            excerpt: row["excerpt"],
                            imageURL: row["image_url"],
                            hasMedia: row["has_media"],
                            language: row["language"],
                            body: SyncRecords.compressed(row["body"])
                        )
                    }
                )
            }
            return Array(grouped.values)
        }
    }

    // MARK: - Writing it back

    /// Writes down what another device has and this one does not.
    ///
    /// Only for feeds this device follows : a block naming a feed nobody here
    /// subscribes to is not an invitation to subscribe. An article already held
    /// is left alone, since what this device knows about its own copy, chiefly
    /// whether it has been read, is not the sending device's to overwrite.
    @discardableResult
    static func apply(
        _ headers: [Header],
        from feedURL: URL,
        into database: AppDatabase,
        read: Set<ArticleFingerprint>,
        at now: Date = Date()
    ) async throws -> Int {
        try await database.writer.write { db in
            guard let feed = try Feed.filter(Feed.Columns.url == feedURL).fetchOne(db) else { return 0 }

            var added = 0
            for header in headers {
                let exists =
                    try Entry
                    .filter(Column("feed_id") == feed.id && Column("guid") == header.guid)
                    .fetchCount(db) > 0
                guard !exists else { continue }

                var entry = Entry(
                    feedID: feed.id,
                    guid: header.guid,
                    url: header.url.flatMap(URL.init(string:)),
                    title: header.title,
                    excerpt: header.excerpt,
                    author: header.author,
                    language: header.language,
                    publishedAt: header.publishedAt,
                    receivedAt: now,
                    isRead: read.contains(ArticleFingerprint(feedURL: feedURL, guid: header.guid))
                )
                entry.hasMedia = header.hasMedia ?? false
                entry.imageURL = header.imageURL.flatMap(URL.init(string:))
                try entry.insert(db)

                if let html = SyncRecords.expanded(header.body) {
                    try EntryBody(
                        entryID: entry.id,
                        sanitizedHTML: html,
                        plainText: HTMLSanitizer.plainText(html)
                    ).insert(db)
                }
                added += 1
            }
            return added
        }
    }
}
