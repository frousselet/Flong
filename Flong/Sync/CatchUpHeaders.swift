//
//  CatchUpHeaders.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CloudKit
import Foundation
import GRDB
import OSLog

/// Every article this device has, on its way to the reader's other ones.
///
/// **The whole stream travels now, and this is what carries it.** It began as
/// the bounded answer of section 7 to a narrower problem, a device switched off
/// for a week coming back to find half of what its other devices saw had
/// scrolled out of the feeds : identifiers and titles only, over thirty days.
/// The reader asked for all of it, kept for good, and section 7 was amended.
///
/// **What did not change is the shape, and that is the point.** One record per
/// feed, per day, per chunk, carrying every article of that day with its text
/// compressed. Never one record per article : a wire service publishing two
/// hundred pieces a day is two hundred records a day the old way and one this
/// way, and the specification is blunt about which of those CloudKit survives.
/// A day that has passed never changes again either, so the record is written
/// once and never rewritten, which is the other half of what rate limiting
/// punishes.
///
/// **A record holds about a megabyte of fields.** A busy day of full articles
/// goes past that, so a day is cut into as many records as it needs, numbered
/// from zero. The cut is by encoded size rather than by article count, since
/// what the limit is about is bytes.
nonisolated enum CatchUpHeaders {
    /// How much of a record the articles may fill.
    ///
    /// Comfortably under CloudKit's own limit : the rest of the record is a
    /// feed address and a date, and a margin costs nothing next to a save that
    /// is refused for being eleven bytes too big.
    static let chunkLimit = 700 * 1024

    /// One article, whole.
    ///
    /// The body travels compressed, the same way a kept article's does. Markup
    /// compresses to about a fifth, which is what makes a day of a feed fit in
    /// a record at all.
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

    // MARK: - Sending

    /// The articles of every day this device has touched since a moment.
    ///
    /// **The days are found first, then filled whole.** A block stands for a
    /// day, so a block built from only the articles that arrived since the last
    /// push would replace a complete day with a partial one. What `since`
    /// narrows is which days are worth rewriting, and each of those is then
    /// read out in full.
    static func records(
        in database: AppDatabase,
        since: Date = .distantPast,
        zone: CKRecordZone.ID
    ) async throws -> [CKRecord] {
        let groups: [Group] = try await database.writer.read { db in
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

                let headers = rows.map { row in
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
                grouped[url.absoluteString + "|" + day] = Group(url: url, day: day, headers: headers)
            }
            return Array(grouped.values)
        }

        return groups.flatMap { chunked($0, in: zone) }
    }

    /// One day of one feed, cut into as many records as its bytes need.
    private static func chunked(_ group: Group, in zone: CKRecordZone.ID) -> [CKRecord] {
        var records: [CKRecord] = []
        var batch: [Header] = []
        var size = 0

        func flush() {
            guard !batch.isEmpty, let payload = try? JSONEncoder().encode(batch) else { return }
            let record = CKRecord(
                recordType: SyncRecords.RecordType.catchUp,
                recordID: CKRecord.ID(
                    recordName: SyncRecords.name(forCatchUpFeed: group.url, day: group.day, chunk: records.count),
                    zoneID: zone
                )
            )
            record["feedURL"] = group.url.absoluteString
            record["day"] = group.day
            record["headers"] = payload
            records.append(record)
            batch = []
            size = 0
        }

        for header in group.headers {
            // Every field, and the body as base64 : JSON carries a `Data` at
            // four bytes for every three, and an article's excerpt is as long
            // as its body when nothing has trimmed it. Weighing the body alone
            // put a chunk at twice the limit, which is a save CloudKit refuses
            // rather than trims.
            let weight =
                (header.body?.count ?? 0) * 4 / 3
                + header.title.utf8.count
                + (header.excerpt?.utf8.count ?? 0)
                + (header.author?.utf8.count ?? 0)
                + (header.url?.utf8.count ?? 0)
                + (header.imageURL?.utf8.count ?? 0)
                + header.guid.utf8.count
                + 256
            if size > 0, size + weight > chunkLimit { flush() }
            batch.append(header)
            size += weight

            // An article too big for a record of its own goes alone : the save
            // is refused either way, and refusing it alone at least lets the
            // rest of the day through.
            if size >= chunkLimit { flush() }
        }
        flush()
        return records
    }

    /// One feed's articles for one day.
    private struct Group: Sendable {
        let url: URL
        let day: String
        var headers: [Header]
    }

    /// Nothing expires any more.
    ///
    /// The window was what capped the cost of the mechanism, and the reader
    /// asked for the cost instead : they keep everything, on every device, for
    /// good. The function stays so that the engine's shape does not change and
    /// so that a bound can be put back in one place if it is ever wanted.
    static func expiredNames(in database: AppDatabase, now: Date = Date()) async throws -> [String] {
        []
    }

    // MARK: - Receiving

    /// Writes down what another device has and this one does not.
    ///
    /// Only for feeds this device follows : a block naming a feed nobody here
    /// subscribes to is not an invitation to subscribe. An article already held
    /// is left alone, since what this device knows about its own copy, chiefly
    /// whether it has been read, is not the sending device's to overwrite.
    ///
    /// The body arrives with it now, so a caught-up article is readable rather
    /// than a title and a link waiting for a fetch that may find nothing.
    @discardableResult
    static func apply(
        _ record: CKRecord, into database: AppDatabase, read: Set<ArticleFingerprint>, at now: Date = Date()
    )
        async throws -> Int
    {
        guard record.recordType == SyncRecords.RecordType.catchUp,
            let address = record["feedURL"] as? String,
            let feedURL = URL(string: address),
            let payload = record["headers"] as? Data,
            let headers = try? JSONDecoder().decode([Header].self, from: payload)
        else { return 0 }

        return try await database.writer.write { db in
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

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
