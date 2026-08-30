//
//  Retention.swift
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
import OSLog

/// How much of the stream is worth keeping.
///
/// **Nothing is thrown away unless a limit says so.** Both bounds are optional
/// and both are absent by default : the reader keeps everything that has ever
/// arrived, on every device, and section 13 was amended to say so. The purge
/// is not gone, it is simply not asked for : a reader who wants their disk back
/// asks for it, with ``bounded``.
nonisolated struct RetentionPolicy: Hashable, Sendable {
    /// Articles older than this go, whatever else is true. `nil` keeps them all.
    var maximumAge: TimeInterval?
    /// The cap the store is held under, in bytes. `nil` is no cap.
    var maximumBytes: Int?

    /// Keep everything.
    static let `default` = RetentionPolicy()

    /// What the reader gets when they ask for their disk back : a month, and
    /// half a gigabyte, which is what the stream was held to before they were
    /// given the choice.
    static let bounded = RetentionPolicy(maximumAge: 30 * 24 * 60 * 60, maximumBytes: 500 * 1024 * 1024)
}

/// What a purge removed.
nonisolated struct PurgeSummary: Hashable, Sendable {
    var byAge = 0
    var byVolume = 0
    var bytesAfter = 0

    var removed: Int { byAge + byVolume }
}

/// Keeps the stream bounded, when the reader asks for it to be.
///
/// The stream was a cache purged by age and by volume, and that was what
/// bounded disk usage. It is kept whole now, so nothing here runs unless a
/// policy carries a limit. What the reader kept is never touched either way : a
/// starred article survives every purge, and so does a library item.
nonisolated struct Retention: Sendable {
    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    @discardableResult
    func purge(_ policy: RetentionPolicy = .default, now: Date = Date()) async throws -> PurgeSummary {
        var summary = PurgeSummary()

        if let age = policy.maximumAge {
            summary.byAge = try await purgeByAge(before: now.addingTimeInterval(-age))
        }
        if let bytes = policy.maximumBytes {
            summary.byVolume = try await purgeByVolume(under: bytes)
        }
        summary.bytesAfter = try await size()

        if summary.removed > 0 {
            Log.store.notice("Purged \(summary.removed) articles, store now \(summary.bytesAfter / 1024) kB")
        }
        return summary
    }

    /// The size of the store on disk.
    func size() async throws -> Int {
        try await database.writer.read { db in
            let pages = try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0
            let pageSize = try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 0
            return pages * pageSize
        }
    }

    private func purgeByAge(before cutoff: Date) async throws -> Int {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    DELETE FROM entry
                    WHERE is_starred = 0 AND COALESCE(published_at, received_at) < ?
                    """,
                arguments: [cutoff]
            )
            return db.changesCount
        }
    }

    /// Removes the oldest articles until the store fits.
    ///
    /// A batch at a time, so a store that is far over the cap does not hold one
    /// enormous transaction, and so the loop can stop as soon as it is enough.
    private func purgeByVolume(under limit: Int, batch: Int = 500) async throws -> Int {
        var removed = 0

        while try await size() > limit {
            let deleted = try await database.writer.write { db in
                try db.execute(
                    sql: """
                        DELETE FROM entry WHERE id IN (
                            SELECT id FROM entry WHERE is_starred = 0
                            ORDER BY COALESCE(published_at, received_at) ASC LIMIT ?
                        )
                        """,
                    arguments: [batch]
                )
                return db.changesCount
            }

            guard deleted > 0 else { break }
            removed += deleted

            // Deleted rows leave their pages behind, so the file only shrinks
            // once it is rewritten.
            try await database.writer.writeWithoutTransaction { db in try db.execute(sql: "VACUUM") }
        }

        return removed
    }
}
