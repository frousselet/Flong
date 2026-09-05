//
//  ReadStateStore.swift
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

/// Keeps the read states in the shape they travel in.
///
/// Locally the truth is a column on the article. Between devices it is a set of
/// fingerprints per month, and this is what turns one into the other : it
/// compacts what was read here into blocks to send, and applies the blocks that
/// arrive from elsewhere.
///
/// A block that arrives is also **kept**, not merely applied. An article read on
/// another device may not have been fetched here yet ; when it arrives, it has
/// to arrive read, and the only way to know that is to have remembered the
/// fingerprint in the meantime.
nonisolated struct ReadStateStore: Sendable {
    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    // MARK: - Blocks

    /// One block, as it stands locally.
    func block(period: String, kind: ReadStateKind = .read) async throws -> ReadStateBlock {
        try await database.writer.read { db in Self.block(period: period, kind: kind, in: db) }
    }

    /// Every block, which is what a first synchronization sends.
    func blocks() async throws -> [ReadStateBlock] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT period, kind, fingerprints FROM read_state_block")
                .compactMap(Self.block)
        }
    }

    /// Folds a block into what is stored, and applies it to the articles.
    ///
    /// Returns how many articles it actually marked read, which is what a
    /// synchronization has to report to be worth trusting.
    @discardableResult
    func merge(_ block: ReadStateBlock, at date: Date = Date()) async throws -> Int {
        try await database.writer.write { db in
            let merged = Self.block(period: block.period, kind: block.kind, in: db).merged(with: block)
            try Self.save(merged, at: date, in: db)
            return try Self.apply(merged, in: db)
        }
    }

    /// Rebuilds the blocks from what has been read here.
    ///
    /// Returns the blocks that changed, which are the ones worth sending. A
    /// block whose set did not grow is not sent : that is what keeps a device
    /// that reads nothing from writing to CloudKit every hour.
    @discardableResult
    func compact(at date: Date = Date()) async throws -> [ReadStateBlock] {
        try await database.writer.write { db in
            var built: [String: ReadStateBlock] = [:]

            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT f.url AS url, e.guid AS guid, e.published_at AS published_at
                    FROM entry e JOIN feed f ON f.id = e.feed_id
                    WHERE e.is_read = 1
                    """
            )

            for row in rows {
                guard let url = (row["url"] as String?).flatMap(URL.init(string:)) else { continue }
                let period = ReadStateBlock.period(for: row["published_at"] as Date?)
                let fingerprint = ArticleFingerprint(feedURL: url, guid: row["guid"])

                built[period, default: ReadStateBlock(period: period)].insert([fingerprint])
            }

            var changed: [ReadStateBlock] = []
            for (period, block) in built {
                let stored = Self.block(period: period, kind: .read, in: db)
                let merged = stored.merged(with: block)
                guard merged.fingerprints.count != stored.fingerprints.count else { continue }

                try Self.save(merged, at: date, in: db)
                changed.append(merged)
            }
            return changed
        }
    }

    // MARK: - Arriving articles

    /// The fingerprints of every period, for the ingestion of new articles.
    ///
    /// An article fetched today may have been read on another device last week,
    /// and it has to land read rather than announce itself as new.
    @concurrent
    func fingerprints() async throws -> Set<ArticleFingerprint> {
        try await blocks().reduce(into: Set<ArticleFingerprint>()) { $0.formUnion($1.fingerprints) }
    }

    // MARK: - Rows

    private static func block(period: String, kind: ReadStateKind, in db: Database) -> ReadStateBlock {
        let data = try? Data.fetchOne(
            db,
            sql: "SELECT fingerprints FROM read_state_block WHERE period = ? AND kind = ?",
            arguments: [period, kind.rawValue]
        )
        guard let data else { return ReadStateBlock(period: period, kind: kind) }
        return ReadStateBlock.decode(data, period: period, kind: kind)
    }

    private static func block(_ row: Row) -> ReadStateBlock? {
        guard let kind = ReadStateKind(rawValue: row["kind"]) else { return nil }
        return ReadStateBlock.decode(row["fingerprints"], period: row["period"], kind: kind)
    }

    private static func save(_ block: ReadStateBlock, at date: Date, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO read_state_block (period, kind, fingerprints, updated_at) VALUES (?, ?, ?, ?)
                ON CONFLICT (period, kind) DO UPDATE SET fingerprints = excluded.fingerprints,
                                                         updated_at = excluded.updated_at
                """,
            arguments: [block.period, block.kind.rawValue, block.encoded(), date]
        )
    }

    /// Marks the articles of a period that the block names.
    private static func apply(_ block: ReadStateBlock, in db: Database) throws -> Int {
        guard !block.isEmpty else { return 0 }

        let condition =
            block.period == "undated"
            ? "e.published_at IS NULL"
            : "SUBSTR(e.published_at, 1, 7) = ?"
        let arguments: StatementArguments = block.period == "undated" ? [] : [block.period]

        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT e.id AS id, f.url AS url, e.guid AS guid
                FROM entry e JOIN feed f ON f.id = e.feed_id
                WHERE e.is_read = 0 AND \(condition)
                """,
            arguments: arguments
        )

        let ids = rows.compactMap { row -> UUID? in
            guard let url = (row["url"] as String?).flatMap(URL.init(string:)) else { return nil }
            let fingerprint = ArticleFingerprint(feedURL: url, guid: row["guid"])
            return block.contains(fingerprint) ? row["id"] as UUID : nil
        }

        guard !ids.isEmpty else { return 0 }
        _ = try Entry.filter(keys: ids).updateAll(db, Column("is_read").set(to: true))
        return ids.count
    }
}
