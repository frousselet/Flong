//
//  TopicPreferences.swift
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

/// What the reader has said they want more or less of.
///
/// A subject starts at nought, which is the reader saying nothing. Asking for
/// more of it raises it by one, less by one, and it stops at three either way :
/// past that the reader is no longer expressing a preference, they are hiding
/// things from themselves, and the front page is not the place to do that.
///
/// The key is the name of the subject, because a subject has nothing else to be
/// known by : it is written afresh by the model on each rebuild, and the reader
/// pressed on a word rather than on a row of a table. A model that renames
/// `Cybercriminalité` to `Cybersécurité` loses the preference attached to it,
/// which is the price of a name being the only handle there is.
nonisolated struct TopicPreferences: Sendable {
    /// How far a reader may push a subject in either direction.
    static let limit = 3

    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    /// Every subject the reader has an opinion about.
    func scores() async throws -> [String: Int] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT name, score FROM topic_preference WHERE score <> 0")
            return Dictionary(uniqueKeysWithValues: rows.map { ($0["name"] as String, $0["score"] as Int) })
        }
    }

    func score(of name: String) async throws -> Int {
        try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT score FROM topic_preference WHERE name = ?", arguments: [name]) ?? 0
        }
    }

    /// Moves a subject up or down, and gives back where it landed.
    @discardableResult
    func adjust(_ name: String, by delta: Int, at date: Date = Date()) async throws -> Int {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return 0 }

        return try await database.writer.write { db in
            let current =
                try Int.fetchOne(db, sql: "SELECT score FROM topic_preference WHERE name = ?", arguments: [name]) ?? 0
            let score = min(max(current + delta, -Self.limit), Self.limit)

            // Nought is the absence of an opinion, and an absence is not a row.
            guard score != 0 else {
                try db.execute(sql: "DELETE FROM topic_preference WHERE name = ?", arguments: [name])
                return 0
            }

            try db.execute(
                sql: """
                    INSERT INTO topic_preference (name, score, updated_at) VALUES (?, ?, ?)
                    ON CONFLICT (name) DO UPDATE SET score = excluded.score, updated_at = excluded.updated_at
                    """,
                arguments: [name, score, date]
            )
            return score
        }
    }

    /// Forgets what was said about a subject.
    func clear(_ name: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM topic_preference WHERE name = ?", arguments: [name])
        }
    }
}
