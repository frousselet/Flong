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

/// What a device missed while it was switched off.
///
/// A feed holds twenty articles ; a device left off for a week comes back to
/// find that half of what its other devices saw has scrolled out of it and is
/// gone for good. Section 7 answers that with a bounded mechanism : one record
/// per feed and per day, holding identifiers, titles, links and dates and
/// nothing else, over a sliding window of thirty days.
///
/// It is metadata only. The bodies are not sent, since the stream is a cache
/// each device fills for itself, so a caught up article arrives as a title and
/// a link, which is enough to decide whether to go and read it.
nonisolated enum CatchUpHeaders {
    /// How far back the window reaches, and how long a record is kept.
    static let window: TimeInterval = 30 * 24 * 60 * 60

    /// How many articles one day of one feed may name. A feed that publishes
    /// more than this in a day is a firehose, and missing the tail of it is not
    /// what anybody is worried about.
    static let limit = 200

    /// One article, as a header.
    nonisolated struct Header: Hashable, Sendable, Codable {
        let guid: String
        let title: String
        let url: String?
        let publishedAt: Date?
    }

    // MARK: - Sending

    /// The headers of what this device fetched recently, one record per feed and
    /// per day.
    static func records(in database: AppDatabase, since: Date, zone: CKRecordZone.ID) async throws -> [CKRecord] {
        // The grouping happens inside the read : a GRDB row is not `Sendable`
        // and has no business leaving the database's own queue.
        let groups: [Group] = try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT f.url AS feed_url, e.guid AS guid, e.title AS title, e.url AS url,
                           e.published_at AS published_at,
                           SUBSTR(COALESCE(e.published_at, e.received_at), 1, 10) AS day
                    FROM entry e JOIN feed f ON f.id = e.feed_id
                    WHERE e.received_at >= ?
                    ORDER BY e.received_at DESC
                    """,
                arguments: [since]
            )

            var grouped: [String: Group] = [:]
            for row in rows {
                guard let url = (row["feed_url"] as String?).flatMap(URL.init(string:)) else { continue }
                let day: String = row["day"]
                let key = url.absoluteString + "|" + day

                var group = grouped[key] ?? Group(url: url, day: day, headers: [])
                guard group.headers.count < limit else { continue }

                group.headers.append(
                    Header(
                        guid: row["guid"],
                        title: row["title"],
                        url: row["url"],
                        publishedAt: row["published_at"]
                    )
                )
                grouped[key] = group
            }
            return Array(grouped.values)
        }

        return groups.compactMap { group in
            guard let payload = try? JSONEncoder().encode(group.headers) else { return nil }

            let record = CKRecord(
                recordType: SyncRecords.RecordType.catchUp,
                recordID: CKRecord.ID(
                    recordName: SyncRecords.name(forCatchUpFeed: group.url, day: group.day),
                    zoneID: zone
                )
            )
            record["feedURL"] = group.url.absoluteString
            record["day"] = group.day
            record["headers"] = payload
            return record
        }
    }

    /// One feed's articles for one day.
    private struct Group: Sendable {
        let url: URL
        let day: String
        var headers: [Header]
    }

    /// The records that have fallen out of the window, for the engine to delete.
    ///
    /// The cost of the whole mechanism is capped by this : without it, a reader
    /// would accumulate one record per feed per day for ever.
    static func expiredNames(in database: AppDatabase, now: Date = Date()) async throws -> [String] {
        let cutoff = dayFormatter.string(from: now.addingTimeInterval(-window))

        return try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT f.url AS feed_url,
                           SUBSTR(COALESCE(e.published_at, e.received_at), 1, 10) AS day
                    FROM entry e JOIN feed f ON f.id = e.feed_id
                    WHERE SUBSTR(COALESCE(e.published_at, e.received_at), 1, 10) < ?
                    """,
                arguments: [cutoff]
            )

            return rows.compactMap { row -> String? in
                guard let url = (row["feed_url"] as String?).flatMap(URL.init(string:)) else { return nil }
                return SyncRecords.name(forCatchUpFeed: url, day: row["day"])
            }
        }
    }

    // MARK: - Receiving

    /// Writes down what another device saw and this one missed.
    ///
    /// Only for feeds this device follows, and only for articles it does not
    /// already hold. They arrive without a body, which the next refresh fills in
    /// when the article is still in the feed.
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
                    publishedAt: header.publishedAt,
                    receivedAt: now,
                    isRead: read.contains(ArticleFingerprint(feedURL: feedURL, guid: header.guid))
                )
                entry.hasMedia = false
                try entry.insert(db)
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
