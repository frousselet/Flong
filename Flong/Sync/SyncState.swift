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
