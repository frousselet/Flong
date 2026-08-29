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

    /// A subject as the reader manages it : what it is called, how much of the
    /// page it covers, and what they have said about it.
    nonisolated struct Known: Hashable, Sendable, Identifiable {
        let name: String
        let stories: Int
        let score: Int

        var id: String { name }
    }

    /// Every subject there is, whether it is on the page today or not.
    ///
    /// Subjects the model has stopped using are still listed while a
    /// preference hangs off them : a reader who asked for less of something
    /// and cannot find it again to take it back is a reader stuck with it.
    func known() async throws -> [Known] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT name, SUM(stories) AS stories, SUM(score) AS score FROM (
                        SELECT name, COUNT(*) AS stories, 0 AS score FROM story_topic GROUP BY name
                        UNION ALL
                        SELECT name, 0 AS stories, score FROM topic_preference
                    )
                    GROUP BY name
                    """
            )
            .map {
                Known(name: $0["name"], stories: $0["stories"] ?? 0, score: $0["score"] ?? 0)
            }

            // What the reader spoke about first, then what covers the most,
            // then the alphabet. The names are compared the other way round
            // so that the whole comparison stays a single descending one
            // while the names read forwards.
            return rows.sorted {
                (abs($0.score), $0.stories, $1.name) > (abs($1.score), $1.stories, $0.name)
            }
        }
    }

    /// Takes back everything the reader has said.
    func clearAll() async throws {
        try await database.writer.write { db in try db.execute(sql: "DELETE FROM topic_preference") }
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
