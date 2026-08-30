//
//  CollectionStore.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import OSLog

/// The collections a reader made, which are albums by another name.
///
/// **They are tags, and that was already the plan.** Section 4 says a tag
/// applies to an article, a feed or a library item, and section 5 put `tag` and
/// `tag_binding` in the schema at v1 for it. A collection is a tag under one
/// root and a membership is a binding : nothing new in the store, and folders,
/// rules and saved queries all inherit the same mechanism when their turn
/// comes.
///
/// **The root is what keeps them apart.** Tags will be used for other things,
/// and a collection called `ios` and a tag called `ios` are not the same thing.
/// Everything here lives under `collection/`, which is the namespacing the
/// specification already describes, and a name with a slash in it is refused
/// rather than allowed to invent a level nobody asked for.
nonisolated struct CollectionStore: Sendable {
    static let root = "collection"

    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    /// What the reader may not call a collection.
    ///
    /// A name is trimmed, and it may not be empty and may not carry the
    /// separator the namespace is built on.
    static func name(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else { return nil }
        return trimmed
    }

    static func path(of name: String) -> String { root + "/" + name }

    static func name(ofPath path: String) -> String? {
        guard path.hasPrefix(root + "/") else { return nil }
        let name = String(path.dropFirst(root.count + 1))
        return name.isEmpty ? nil : name
    }

    // MARK: - Making and unmaking

    /// Makes a collection, or gives back the one already called that.
    ///
    /// Idempotent on purpose : two devices making the same collection have made
    /// one collection, which is what a name being the identity means.
    @discardableResult
    func create(_ raw: String, at date: Date = Date()) async throws -> String? {
        guard let name = Self.name(from: raw) else { return nil }

        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO tag (id, path, created_at) VALUES (?, ?, ?)",
                arguments: [UUID.v7(), Self.path(of: name), date]
            )
        }
        return name
    }

    func rename(_ name: String, to raw: String) async throws -> String? {
        guard let renamed = Self.name(from: raw), renamed != name else { return nil }

        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE OR IGNORE tag SET path = ? WHERE path = ?",
                arguments: [Self.path(of: renamed), Self.path(of: name)]
            )
        }
        return renamed
    }

    /// Takes a collection away, and its memberships with it.
    ///
    /// The articles stay. A collection is a way of looking at what was kept,
    /// and putting a way of looking away is not throwing anything out.
    func delete(_ name: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM tag WHERE path = ?", arguments: [Self.path(of: name)])
        }
    }

    // MARK: - Filling

    func add(_ itemIDs: [UUID], to name: String, at date: Date = Date()) async throws {
        guard !itemIDs.isEmpty else { return }

        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO tag (id, path, created_at) VALUES (?, ?, ?)",
                arguments: [UUID.v7(), Self.path(of: name), date]
            )
            guard
                let tag = try UUID.fetchOne(
                    db,
                    sql: "SELECT id FROM tag WHERE path = ?",
                    arguments: [Self.path(of: name)]
                )
            else { return }

            for id in itemIDs {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO tag_binding (tag_id, target_kind, target_id, created_at)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [tag, Self.kind, id, date]
                )
            }
        }
    }

    func remove(_ itemIDs: [UUID], from name: String) async throws {
        guard !itemIDs.isEmpty else { return }

        try await database.writer.write { db in
            try db.execute(
                sql: """
                    DELETE FROM tag_binding
                    WHERE target_kind = ? AND target_id IN (\(databaseQuestionMarks(count: itemIDs.count)))
                      AND tag_id IN (SELECT id FROM tag WHERE path = ?)
                    """,
                arguments: StatementArguments([Self.kind] + itemIDs.map { $0.databaseValue })
                    + StatementArguments([Self.path(of: name)])
            )
        }
    }

    /// Which collections one kept article is in.
    func collections(of itemID: UUID) async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT t.path FROM tag t
                    JOIN tag_binding b ON b.tag_id = t.id
                    WHERE b.target_kind = ? AND b.target_id = ? AND t.path LIKE ?
                    """,
                arguments: [Self.kind, itemID, Self.root + "/%"]
            )
            .compactMap(Self.name(ofPath:))
            .sorted(by: Self.before)
        }
    }

    /// Says which collections a kept article belongs to, and only those.
    ///
    /// What arrives from another device is the whole truth about that article :
    /// a collection missing from the list is a collection it was taken out of,
    /// so the difference is applied rather than the additions alone.
    func set(_ names: [String], of itemID: UUID, at date: Date = Date()) async throws {
        let wanted = Set(names.compactMap { Self.name(from: $0) })
        let current = Set(try await collections(of: itemID))

        for name in wanted.subtracting(current) { try await add([itemID], to: name, at: date) }
        for name in current.subtracting(wanted) { try await remove([itemID], from: name) }
    }

    // MARK: - Reading

    /// Which collections every kept article is in, keyed by the article.
    ///
    /// One pass rather than one query per article : synchronizing walks the
    /// whole library, and a few thousand items asked one at a time is a few
    /// thousand statements for an answer one join already holds.
    func memberships() async throws -> [UUID: [String]] {
        let rows: [Pair] = try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT b.target_id AS item, t.path AS path FROM tag_binding b
                    JOIN tag t ON t.id = b.tag_id
                    WHERE b.target_kind = ? AND t.path LIKE ?
                    ORDER BY t.path
                    """,
                arguments: [Self.kind, Self.root + "/%"]
            )
            .compactMap { row in
                (row["path"] as String?).flatMap(Self.name(ofPath:)).map {
                    Pair(item: row["item"], name: $0)
                }
            }
        }

        return rows.reduce(into: [:]) { all, pair in all[pair.item, default: []].append(pair.name) }
    }

    /// Every name there is, empty collections included.
    func names() async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT path FROM tag WHERE path LIKE ?",
                arguments: [Self.root + "/%"]
            )
            .compactMap(Self.name(ofPath:))
            .sorted(by: Self.before)
        }
    }

    private struct Pair: Sendable {
        var item: UUID
        var name: String
    }

    /// Every collection there is, with what is in it, emptiest included.
    ///
    /// An empty one is still a collection : the reader made it, and a page that
    /// hid it until something was put in it would lose the one they made a
    /// moment ago for exactly that purpose.
    func made() async throws -> [LibraryCollection] {
        let counted: [Counted] = try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT t.path AS path, COUNT(i.id) AS count,
                           (SELECT i.image_url FROM library_item i
                            JOIN tag_binding c ON c.target_id = i.id AND c.target_kind = ?
                            WHERE c.tag_id = t.id AND i.image_url IS NOT NULL
                            ORDER BY COALESCE(i.published_at, i.promoted_at) DESC LIMIT 1) AS cover
                    FROM tag t
                    LEFT JOIN tag_binding b ON b.tag_id = t.id AND b.target_kind = ?
                    -- Counting the articles and not the bindings. A binding
                    -- carries no foreign key, since it points at one of three
                    -- tables, so nothing removes it when what it names goes :
                    -- counting bindings is counting articles that may not be
                    -- there, and a square that says two over a page showing one
                    -- has broken the only promise a count makes.
                    LEFT JOIN library_item i ON i.id = b.target_id
                    WHERE t.path LIKE ?
                    GROUP BY t.path
                    """,
                arguments: [Self.kind, Self.kind, Self.root + "/%"]
            )
            return rows.compactMap { row in
                (row["path"] as String?).map { Counted(path: $0, count: row["count"], cover: row["cover"]) }
            }
        }

        return
            counted
            .compactMap { counted in
                Self.name(ofPath: counted.path).map {
                    LibraryCollection(kind: .made($0), count: counted.count, cover: counted.cover)
                }
            }
            .sorted { first, second in
                guard case .made(let a) = first.kind, case .made(let b) = second.kind else { return false }
                return Self.before(a, b)
            }
    }

    /// The order a reader expects their own names in.
    ///
    /// Not the order SQLite puts them in : `ORDER BY path` is byte order, where
    /// `Thèse` comes before `À lire` because a capital A with a grave accent
    /// starts with a higher byte than a T. A list of the reader's own words is
    /// sorted the way their language sorts.
    private static func before(_ first: String, _ second: String) -> Bool {
        first.localizedStandardCompare(second) == .orderedAscending
    }

    /// A row that has crossed out of the database, which a `Row` may not.
    private struct Counted: Sendable {
        var path: String
        var count: Int
        var cover: URL?
    }

    /// What a binding points at, when it points at a kept article.
    private static let kind = "library_item"
}
