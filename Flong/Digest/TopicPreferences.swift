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

/// Where a subject came from.
///
/// Three natures, and what tells them apart is who decided. A standard one was
/// decided by a century of newspapers ; a reader's own by the reader ; a smart
/// one by the model, when nothing it was shown covered a story.
///
/// The difference is what the reader may do to it and what the model is asked
/// for. A standard one cannot be deleted, since it is not a thing that was
/// made ; the reader's own are theirs to add and to remove ; a smart one is the
/// model's and goes when its stories do.
nonisolated enum TopicKind: String, Hashable, Sendable, Codable, CaseIterable {
    case standard
    case own
    case smart
}

/// One subject of the vocabulary.
nonisolated struct Topic: Hashable, StoredRecord {
    static let databaseTableName = "topic"

    enum CodingKeys: String, CodingKey {
        case name
        case isOwn = "is_own"
        case kind
        case createdAt = "created_at"
    }

    var name: String
    /// Whether the reader wrote it themselves, which is what makes it theirs
    /// to delete.
    ///
    /// The column the kind was carried in before there were three of them. It
    /// is derived from the kind rather than passed, so the two cannot come to
    /// disagree, and it stays true for anything still reading it.
    var isOwn: Bool
    var kind: TopicKind
    var createdAt: Date

    init(name: String, kind: TopicKind, createdAt: Date = Date()) {
        self.name = name
        self.kind = kind
        self.isOwn = kind == .own
        self.createdAt = createdAt
    }
}

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
        /// Whether the reader wrote it themselves.
        let isOwn: Bool
        let kind: TopicKind

        var id: String { name }
    }

    /// Every subject there is, whether it is on the page today or not.
    ///
    /// From the vocabulary, so a subject the reader has just written is there
    /// before any story has been sorted into it, and a subject the model has
    /// stopped using is still there for the reader to take back what they said
    /// about it. A preference nobody can find is a preference nobody can undo.
    func known() async throws -> [Known] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT t.name AS name, t.is_own AS is_own, t.kind AS kind,
                           (SELECT COUNT(*) FROM story_topic s WHERE s.name = t.name) AS stories,
                           COALESCE((SELECT p.score FROM topic_preference p WHERE p.name = t.name), 0) AS score
                    FROM topic t
                    """
            )
            .map {
                Known(
                    name: $0["name"],
                    stories: $0["stories"] ?? 0,
                    score: $0["score"] ?? 0,
                    isOwn: $0["is_own"] ?? false,
                    kind: TopicKind(rawValue: $0["kind"] ?? "") ?? .smart
                )
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

    /// The subjects the model must choose from : the sections every reader has
    /// and the ones this reader wrote.
    ///
    /// **Not the smart ones.** Those are what the model came up with for one
    /// story, and offering them back to it turns a page into a drift of near
    /// synonyms : the model reaches for whatever is nearest, and what is
    /// nearest is whatever it said last. A story is filed under something a
    /// reader recognizes first, and given a smart subject afterwards.
    func settled() async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM topic WHERE kind IN ('standard', 'own')
                    ORDER BY kind = 'own' DESC, created_at
                    """
            )
        }
    }

    /// Writes down the sections every reader has, once.
    ///
    /// Idempotent, and folded like everything else : a reader who had already
    /// written `Écologie` themselves keeps theirs, and the standard one is not
    /// added beside it.
    func seedStandards(_ names: [String] = StandardTopics.names(), at date: Date = Date()) async throws {
        try await database.writer.write { db in
            for name in names {
                guard try Self.folded(name, in: db) == nil else { continue }
                try Topic(name: name, kind: .standard, createdAt: date).insert(db)
            }
        }
    }

    /// The subjects the reader wrote themselves.
    ///
    /// They are on the page whether anything has been filed under them yet or
    /// not : a reader who has just written one and cannot see it has no way of
    /// knowing it took.
    func ownNames() async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM topic WHERE is_own = 1 ORDER BY created_at")
        }
    }

    /// The subjects the model named itself.
    func smartNames() async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM topic WHERE kind = 'smart'")
        }
    }

    /// The vocabulary the model is shown, most used first.
    func vocabulary(limit: Int = 40) async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT t.name FROM topic t
                    LEFT JOIN story_topic s ON s.name = t.name
                    GROUP BY t.name
                    ORDER BY COUNT(s.story_id) DESC, t.created_at
                    LIMIT \(limit)
                    """
            )
        }
    }

    /// Adds a subject the reader wrote themselves.
    ///
    /// Folded against what is already there : a reader writing `cybersécurité`
    /// where `Cybersécurité` exists meant the one that exists.
    @discardableResult
    func add(_ name: String, at date: Date = Date()) async throws -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        return try await database.writer.write { db in
            if let existing = try Self.folded(name, in: db) { return existing }
            try Topic(name: name, kind: .own, createdAt: date).insert(db)
            return name
        }
    }

    /// Records a subject the model came up with, when nothing it was shown fit.
    @discardableResult
    func record(_ name: String, at date: Date = Date()) async throws -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        return try await database.writer.write { db in
            if let existing = try Self.folded(name, in: db) { return existing }
            try Topic(name: name, kind: .smart, createdAt: date).insert(db)
            return name
        }
    }

    /// Removes a subject the reader wrote, and everything hanging off it.
    func remove(_ name: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM story_topic WHERE name = ?", arguments: [name])
            try db.execute(sql: "DELETE FROM topic_preference WHERE name = ?", arguments: [name])
            // A standard one is not a thing that was made, so there is
            // nothing there to unmake.
            try db.execute(sql: "DELETE FROM topic WHERE name = ? AND kind = 'own'", arguments: [name])
        }
    }

    /// The subject already in the vocabulary that this name means.
    ///
    /// Case and accents folded : a model that answers `cybersecurite` where
    /// `Cybersécurité` is already a subject has not found a new one, and a
    /// vocabulary that grows a near-twin every week is a vocabulary nobody can
    /// hold an opinion about.
    static func folded(_ name: String, in db: Database) throws -> String? {
        let wanted = fold(name)
        return try String.fetchAll(db, sql: "SELECT name FROM topic").first { fold($0) == wanted }
    }

    static func fold(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
            // A preference on a subject the vocabulary does not have would be
            // a preference the reader can never find again to take back.
            let name = try Self.folded(name, in: db) ?? name
            try Topic(name: name, kind: .smart, createdAt: date).insert(db, onConflict: .ignore)

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
