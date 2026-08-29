//
//  SearchIndex.swift
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

/// The full-text index of the stream.
///
/// Triggers keep it in step with every write, so nothing here is needed for it
/// to be correct. What is here is what a trigger cannot do : rebuilding it from
/// nothing, and compacting it once it has been written to for months.
nonisolated struct SearchIndex: Sendable {
    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    /// How many articles the index holds.
    func count() async throws -> Int {
        try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_fts") ?? 0
        }
    }

    /// Rebuilds the index from the articles.
    ///
    /// Section 11 of the specification asks for this to be possible at any time,
    /// and the index is disposable by design : it holds nothing the articles do
    /// not, so throwing it away costs a minute and no data.
    ///
    /// A contentless table cannot be rebuilt by FTS5 itself, since it has no
    /// content to read : it is emptied and written again.
    @discardableResult
    func rebuild() async throws -> Int {
        let started = ContinuousClock.now

        let count = try await database.writer.write { db in
            try db.execute(sql: "INSERT INTO entry_fts(entry_fts) VALUES('delete-all')")
            try db.execute(sql: "\(AppDatabase.indexInsert) \(AppDatabase.indexSelect) WHERE 1")
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_fts") ?? 0
        }

        Log.index.notice("Rebuilt the index over \(count) articles in \(started.duration(to: .now))")
        return count
    }

    /// Merges the index into as few segments as it can.
    ///
    /// Months of small writes leave it in many pieces, and a query has to visit
    /// every one of them. This is the background work of M4, not something a
    /// reader ever waits for.
    func optimize() async throws {
        try await database.writer.write { db in
            try db.execute(sql: "INSERT INTO entry_fts(entry_fts) VALUES('optimize')")
        }
    }

    /// Whether the index and the articles agree on how many rows there are.
    ///
    /// A mismatch means a trigger was bypassed, which is worth knowing before a
    /// reader concludes that Flong lost an article.
    func isConsistent() async throws -> Bool {
        try await database.writer.read { db in
            let entries = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry") ?? 0
            let indexed = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_fts") ?? 0
            return entries == indexed
        }
    }
}
