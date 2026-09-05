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

/// Every collection there is, of all three natures.
///
/// **One place that answers what the collections are**, because the answer
/// comes from three different tables and a page should not have to know that.
/// The built-in ones are columns on the article, the made ones are tags under
/// a `collection/` root, and the dynamic ones are the saved queries section 12
/// described and v1 put in the schema.
///
/// **Nothing new was needed in the store for any of it.** A tag applies to an
/// article by section 4, and a saved query is a name and a query by section 5.
/// Both had been sitting there unused.
nonisolated struct CollectionStore: Sendable {
    /// The root every made collection's tag hangs off.
    ///
    /// Tags will be used for other things, and a tag `Typographie` and a
    /// collection of that name are not the same thing. A name carrying the
    /// separator is refused rather than allowed to invent a level.
    static let root = "collection"

    private let database: AppDatabase
    private let articles: ArticleStore
    private let authors: AuthorStore
    private let newsmakers: NewsmakerStore

    init(_ database: AppDatabase) {
        self.database = database
        self.articles = ArticleStore(database)
        self.authors = AuthorStore(database)
        self.newsmakers = NewsmakerStore(database)
    }

    // MARK: - Names

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

    /// The order a reader expects their own names in.
    ///
    /// Not the order SQLite puts them in : `ORDER BY` is byte order, where
    /// `Thèse` comes before `À lire` because a capital A with a grave accent
    /// starts with a higher byte than a T.
    static func before(_ first: String, _ second: String) -> Bool {
        first.localizedStandardCompare(second) == .orderedAscending
    }

    // MARK: - Every collection there is

    /// All three natures, in the order the page shows them.
    @concurrent
    func all() async throws -> [ArticleCollection] {
        try await builtIn() + made() + dynamic()
    }

    /// The ones every reader has, which are the state of their own articles.
    ///
    /// Four of them are about people rather than about articles, and they are
    /// asked of the two stores that know about people. ``AuthorStore`` answers
    /// for who signed a piece : a directory of every byline there is, and what
    /// the writers the reader singled out have written. ``NewsmakerStore``
    /// answers the same two questions about who a piece is *about*. The lot is
    /// put back in the order of ``ArticleCollection/BuiltIn``, which is the
    /// order of the page, so that where a square sits does not depend on which
    /// store happened to answer it.
    @concurrent
    func builtIn() async throws -> [ArticleCollection] {
        let found =
            try await articles.builtInCollections() + authors.collections() + newsmakers.collections()
        return found.sorted { first, second in
            guard case .builtIn(let one) = first.kind, case .builtIn(let other) = second.kind else { return false }
            return one.rank < other.rank
        }
    }

    // MARK: - Made, article by article

    @discardableResult
    @concurrent
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

    @concurrent
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

    /// Takes a made collection away, and its memberships with it.
    ///
    /// The articles stay. A collection is a way of looking at what was kept,
    /// and putting a way of looking away is not throwing anything out.
    @concurrent
    func delete(_ name: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM tag WHERE path = ?", arguments: [Self.path(of: name)])
        }
    }

    @concurrent
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
                    arguments: [tag, Self.targetKind, id, date]
                )
            }
        }
    }

    @concurrent
    func remove(_ itemIDs: [UUID], from name: String) async throws {
        guard !itemIDs.isEmpty else { return }

        try await database.writer.write { db in
            try db.execute(
                sql: """
                    DELETE FROM tag_binding
                    WHERE target_kind = ? AND target_id IN (\(databaseQuestionMarks(count: itemIDs.count)))
                      AND tag_id IN (SELECT id FROM tag WHERE path = ?)
                    """,
                arguments: StatementArguments([Self.targetKind] + itemIDs.map { $0.databaseValue })
                    + StatementArguments([Self.path(of: name)])
            )
        }
    }

    /// Which made collections one article is in.
    @concurrent
    func collections(of itemID: UUID) async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT t.path FROM tag t
                    JOIN tag_binding b ON b.tag_id = t.id
                    WHERE b.target_kind = ? AND b.target_id = ? AND t.path LIKE ?
                    """,
                arguments: [Self.targetKind, itemID, Self.root + "/%"]
            )
            .compactMap(Self.name(ofPath:))
            .sorted(by: Self.before)
        }
    }

    /// Says which collections an article belongs to, and only those.
    ///
    /// What arrives from another device is the whole truth about that article :
    /// a collection missing from the list is one it was taken out of, so the
    /// difference is applied rather than the additions alone.
    @concurrent
    func set(_ names: [String], of itemID: UUID, at date: Date = Date()) async throws {
        let wanted = Set(names.compactMap { Self.name(from: $0) })
        let current = Set(try await collections(of: itemID))

        for name in wanted.subtracting(current) { try await add([itemID], to: name, at: date) }
        for name in current.subtracting(wanted) { try await remove([itemID], from: name) }
    }

    /// Which made collections every filed article is in, keyed by the article.
    ///
    /// One pass rather than one query per article : synchronizing walks every
    /// mark there is, and a few thousand of them asked one at a time is a few
    /// thousand statements for an answer one join already holds.
    @concurrent
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
                arguments: [Self.targetKind, Self.root + "/%"]
            )
            .compactMap { row in
                (row["path"] as String?).flatMap(Self.name(ofPath:)).map {
                    Pair(item: row["item"], name: $0)
                }
            }
        }

        return rows.reduce(into: [:]) { all, pair in all[pair.item, default: []].append(pair.name) }
    }

    /// Every made collection, with what is in it, the empty ones included.
    ///
    /// An empty one is still a collection : the reader made it, and a page that
    /// hid it until something was put in it would lose the one they made a
    /// moment ago for exactly that purpose.
    @concurrent
    func made() async throws -> [ArticleCollection] {
        let counted: [Counted] = try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT t.path AS path, COUNT(i.id) AS count,
                           \(
                               CollectionCovers.sql(
                                   where: """
                                       i.id IN (SELECT c.target_id FROM tag_binding c
                                                WHERE c.tag_id = t.id AND c.target_kind = ?)
                                       """
                               )
                           ) AS covers
                    FROM tag t
                    LEFT JOIN tag_binding b ON b.tag_id = t.id AND b.target_kind = ?
                    -- Counting the articles and not the bindings. A binding
                    -- carries no foreign key, since it points at one of three
                    -- tables, so nothing removes it when what it names goes.
                    LEFT JOIN entry i ON i.id = b.target_id
                    WHERE t.path LIKE ?
                    GROUP BY t.path
                    """,
                arguments: [Self.targetKind, Self.targetKind, Self.root + "/%"]
            )
            .compactMap { row in
                (row["path"] as String?).map {
                    Counted(name: $0, count: row["count"], covers: CollectionCovers.read(row["covers"]))
                }
            }
        }

        return
            counted
            .compactMap { counted in
                Self.name(ofPath: counted.name).map {
                    ArticleCollection(kind: .made($0), count: counted.count, covers: counted.covers)
                }
            }
            .sorted { Self.before($0.name ?? "", $1.name ?? "") }
    }

    /// Every made collection's name, empty ones included.
    @concurrent
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

    // MARK: - Dynamic, described rather than filled

    /// Makes a collection out of a description.
    ///
    /// The description is the query language of section 12, so everything a
    /// reader can search for is something they can keep a collection of. It is
    /// parsed before it is stored : a description nothing can be made of is
    /// refused where the reader wrote it, rather than accepted and found to be
    /// empty for ever.
    @discardableResult
    @concurrent
    func createDynamic(_ raw: String, matching query: String, at date: Date = Date()) async throws -> String? {
        guard let name = Self.name(from: raw), Self.isUsable(query) else { return nil }

        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO saved_query (id, name, query, position, created_at) VALUES (?, ?, ?, 0, ?)
                    ON CONFLICT(name) DO UPDATE SET query = excluded.query
                    """,
                arguments: [UUID.v7(), name, query, date]
            )
        }
        return name
    }

    @concurrent
    func deleteDynamic(_ name: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM saved_query WHERE name = ?", arguments: [name])
        }
    }

    /// Every description the reader has written, by the name they gave it.
    ///
    /// What synchronizing sends. The articles are never in it.
    @concurrent
    func descriptions() async throws -> [String: String] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT name, query FROM saved_query")
                .reduce(into: [:]) { all, row in
                    if let name = row["name"] as String? { all[name] = row["query"] as String }
                }
        }
    }

    /// What one dynamic collection is looking for.
    @concurrent
    func query(of name: String) async throws -> String? {
        try await database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT query FROM saved_query WHERE name = ?", arguments: [name])
        }
    }

    /// Every description the reader has written, and how many articles answer
    /// it at this moment.
    ///
    /// The count is asked of the articles rather than kept anywhere : a dynamic
    /// collection holds no list, and a number written down would be a list of
    /// one that goes stale the next time anything arrives.
    @concurrent
    func dynamic(now: Date = Date()) async throws -> [ArticleCollection] {
        let described: [Described] = try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT name, query FROM saved_query")
                .compactMap { row in
                    (row["name"] as String?).map { Described(name: $0, query: row["query"]) }
                }
        }

        var found: [ArticleCollection] = []
        for one in described {
            let node = QueryParser.parse(one.query, now: now)
            let count = (try? await articles.count(.all, matching: node, now: now)) ?? 0
            // The newest few, for the four pictures the square is drawn from :
            // asking for all of them to find four would be reading a whole
            // collection to draw a thumbnail. See ``CollectionCovers``.
            let newest = (try? await articles.summaries(.all, matching: node, limit: CollectionCovers.pool, now: now))
            let covers = CollectionCovers.of((newest ?? []).compactMap(\.imageURL))

            found.append(ArticleCollection(kind: .dynamic(one.name), count: count, covers: covers))
        }
        return found.sorted { Self.before($0.name ?? "", $1.name ?? "") }
    }

    /// Whether a description is one the query language can make anything of.
    static func isUsable(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return QueryParser.parse(trimmed) != .all
    }

    private struct Described: Sendable {
        var name: String
        var query: String
    }

    private struct Pair: Sendable {
        var item: UUID
        var name: String
    }

    private struct Counted: Sendable {
        var name: String
        var count: Int
        var covers: [URL]
    }

    /// What a binding points at, which is an article.
    ///
    /// Not private : the kind is what tells a filing of an article from a
    /// filing of anything else, so whoever removes articles has to name it too,
    /// and two spellings of it would be a filing nothing ever clears.
    static let targetKind = "entry"
}
