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

/// The stream, as CloudKit records.
///
/// **The near end of the reader's history, and only that.** It began as the
/// bounded answer of section 7 to a narrower problem, and it now carries whole
/// articles with no window, which is what the reader asked for. What it cannot
/// do is carry all of it for ever : the record count is feeds multiplied by the
/// days they published on, which reaches six figures for a reader following
/// three hundred feeds over several years, and CloudKit charges by the record.
/// ``StreamArchive`` carries the bulk, in files, where bytes are what is
/// charged for. This is the fast half : a record is pushed and arrives in
/// seconds, where a file in iCloud Documents arrives when it arrives.
///
/// One record per feed, per day, per chunk. Never one record per article : a
/// wire service publishing two hundred pieces a day is two hundred records a
/// day the other way and one this way. A day that has passed never changes
/// again, so a block is written once and not rewritten, which is the other half
/// of what rate limiting punishes.
nonisolated enum CatchUpHeaders {
    /// How much of a record the articles may fill.
    ///
    /// Comfortably under CloudKit's own limit : the rest of the record is a
    /// feed address and a date, and a margin costs nothing next to a save that
    /// is refused for being eleven bytes too big.
    static let chunkLimit = 700 * 1024

    // MARK: - Sending

    static func records(
        in database: AppDatabase,
        since: Date = .distantPast,
        zone: CKRecordZone.ID
    ) async throws -> [CKRecord] {
        try await StreamBlock.groups(in: database, since: since).flatMap { chunked($0, in: zone) }
    }

    /// One day of one feed, cut into as many records as its bytes need.
    private static func chunked(_ group: StreamBlock.Group, in zone: CKRecordZone.ID) -> [CKRecord] {
        var records: [CKRecord] = []
        var batch: [StreamBlock.Header] = []
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
            let weight = StreamBlock.weight(of: header)
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

    /// Nothing expires any more.
    ///
    /// The window was what capped the cost of the mechanism, and the reader
    /// asked for the cost instead. The function stays so that the engine's
    /// shape does not change and so that a bound can be put back in one place
    /// if it is ever wanted.
    static func expiredNames(in database: AppDatabase, now: Date = Date()) async throws -> [String] {
        []
    }

    // MARK: - Receiving

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
            let headers = try? JSONDecoder().decode([StreamBlock.Header].self, from: payload)
        else { return 0 }

        return try await StreamBlock.apply(headers, from: feedURL, into: database, read: read, at: now)
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
