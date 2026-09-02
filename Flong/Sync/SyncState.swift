//
//  SyncState.swift
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

/// Where the synchronization engine keeps what it must not forget.
///
/// The engine hands back a state to store after every exchange. Losing it is not
/// a catastrophe, since the next run simply fetches everything again, but it is
/// a slow and expensive way to learn nothing new.
nonisolated struct SyncState: Sendable {
    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    private static let engineKey = "cloudkit.engine-state"

    func engineState() async throws -> Data? {
        try await value(for: Self.engineKey)
    }

    func setEngineState(_ state: Data?, at date: Date = Date()) async throws {
        try await setValue(state, for: Self.engineKey, at: date)
    }

    func value(for key: String) async throws -> Data? {
        try await database.writer.read { db in
            try Data.fetchOne(db, sql: "SELECT value FROM sync_state WHERE key = ?", arguments: [key])
        }
    }

    // MARK: - What the server said about each record

    /// The system fields of the records the server has confirmed, by name.
    func systemFields(for names: Set<String>) async throws -> [String: Data] {
        guard !names.isEmpty else { return [:] }

        return try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql:
                    "SELECT record_name, system_fields FROM sync_record WHERE record_name IN (\(placeholders(names.count)))",
                arguments: StatementArguments(Array(names))
            )
            return Dictionary(
                uniqueKeysWithValues: rows.map { ($0["record_name"] as String, $0["system_fields"] as Data) }
            )
        }
    }

    /// Keeps what the server said about these records, so the next save of
    /// each carries the tag the server expects.
    func remember(_ records: [CKRecord], at date: Date = Date()) async throws {
        guard !records.isEmpty else { return }

        let fields = records.map { record -> (String, Data) in
            let coder = NSKeyedArchiver(requiringSecureCoding: true)
            record.encodeSystemFields(with: coder)
            coder.finishEncoding()
            return (record.recordID.recordName, coder.encodedData)
        }

        try await database.writer.write { db in
            for (name, data) in fields {
                try db.execute(
                    sql: """
                        INSERT INTO sync_record (record_name, system_fields, updated_at) VALUES (?, ?, ?)
                        ON CONFLICT (record_name) DO UPDATE
                        SET system_fields = excluded.system_fields, updated_at = excluded.updated_at
                        """,
                    arguments: [name, data, date]
                )
            }
        }
    }

    /// The records this device has saved whose names begin with a prefix.
    ///
    /// **The table is the ledger of what this device actually wrote**, which is
    /// what makes the question answerable at all : record names are digests and
    /// cannot be read backwards, so nothing else can say which blocks of the
    /// stream exist for one feed. A prefix is built from a digest and carries
    /// no `%` or `_` of its own, so it needs no escaping.
    func names(startingWith prefix: String) async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT record_name FROM sync_record WHERE record_name LIKE ?",
                arguments: [prefix + "%"]
            )
        }
    }

    /// Forgets records the server no longer holds.
    func forget(_ names: [String]) async throws {
        guard !names.isEmpty else { return }

        try await database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM sync_record WHERE record_name IN (\(placeholders(names.count)))",
                arguments: StatementArguments(names)
            )
        }
    }

    /// Forgets every tag, for a zone that has gone.
    func forgetEveryRecord() async throws {
        try await database.writer.write { db in try db.execute(sql: "DELETE FROM sync_record") }
    }

    // MARK: - What has still to be deleted

    /// Writes down that these records are to go from the reader's iCloud.
    ///
    /// **The one change nothing local can re-derive.** A save is recoverable
    /// from the row it is about : whatever the engine forgets, the row is still
    /// here to be queued again, which is what a repair does. The row a deletion
    /// is about has just been removed, so the intention used to live nowhere
    /// but in the engine's pending changes, and every way of losing those lost
    /// it in silence and for good : no engine yet at the moment of the removal,
    /// an account check that failed at launch, a reset, or one refusal from the
    /// server.
    ///
    /// That is what left a source removed on one device still standing on the
    /// other, with nothing anywhere that would ever try again.
    func rememberDeletions(_ names: [String], at date: Date = Date()) async throws {
        guard !names.isEmpty else { return }

        try await database.writer.write { db in
            for name in names {
                try db.execute(
                    sql: """
                        INSERT INTO pending_deletion (record_name, queued_at) VALUES (?, ?)
                        ON CONFLICT (record_name) DO NOTHING
                        """,
                    arguments: [name, date]
                )
            }
        }
    }

    /// What this device still has to have deleted, the oldest intention first.
    func outstandingDeletions() async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT record_name FROM pending_deletion ORDER BY queued_at")
        }
    }

    /// Drops the intention, the record being gone from the server or never
    /// having been there.
    func forgetDeletions(_ names: [String]) async throws {
        guard !names.isEmpty else { return }

        try await database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM pending_deletion WHERE record_name IN (\(placeholders(names.count)))",
                arguments: StatementArguments(names)
            )
        }
    }

    /// Drops every intention, for a zone that is being taken down whole.
    func forgetEveryDeletion() async throws {
        try await database.writer.write { db in try db.execute(sql: "DELETE FROM pending_deletion") }
    }

    private func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    func setValue(_ value: Data?, for key: String, at date: Date = Date()) async throws {
        try await database.writer.write { db in
            guard let value else {
                try db.execute(sql: "DELETE FROM sync_state WHERE key = ?", arguments: [key])
                return
            }
            try db.execute(
                sql: """
                    INSERT INTO sync_state (key, value, updated_at) VALUES (?, ?, ?)
                    ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
                    """,
                arguments: [key, value, date]
            )
        }
    }
}
