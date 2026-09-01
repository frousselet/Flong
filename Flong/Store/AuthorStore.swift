//
//  AuthorStore.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB

/// Who has signed what, and which of them the reader singled out.
///
/// **The list of authors is not stored anywhere.** It is a question the
/// articles answer about themselves, asked of the `author` column and grouped,
/// exactly as the starred articles are a question and not a list. Nothing has
/// to be kept in step, nothing goes stale when a source is removed, and a
/// writer whose last article was purged simply stops being one.
///
/// **What is stored is the favourite**, one row per writer the reader singled
/// out, and only for those. A table of every byline there is would be a second
/// copy of something the articles already say, and the first spelling change
/// from a publisher would leave a row standing for nobody.
nonisolated struct AuthorStore: Sendable {
    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    // MARK: - Who there is

    /// Every writer this device has read, and the favourites among them.
    ///
    /// A favourite with nothing left to their name is in the list all the same,
    /// with a count of nothing. It is a decision the reader made, and a
    /// decision does not disappear because a purge took the last article it was
    /// about, or because it reached this device before the articles did.
    func all() async throws -> [Author] {
        try await database.writer.read { db in
            var found = try Row.fetchAll(db, sql: Self.grouped).map(Self.author(from:))

            let known = Set(found.map(\.name))
            found += try String.fetchAll(db, sql: "SELECT name FROM favourite_author")
                .filter { !known.contains($0) }
                .map { Author(name: $0, count: 0, isFavourite: true) }

            return found.sorted(by: Author.before)
        }
    }

    /// One writer, for the page about them.
    ///
    /// Answers for a favourite with nothing to their name too, for the same
    /// reason ``all()`` lists them : the page is about a decision the reader
    /// made, and it has to be able to show it and to undo it.
    func author(named name: String) async throws -> Author? {
        try await database.writer.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT (SELECT COUNT(*) FROM entry e WHERE e.author = ? AND \(Self.shown("e"))) AS count,
                           EXISTS(SELECT 1 FROM favourite_author a WHERE a.name = ?) AS favourite
                    """,
                arguments: [name, name]
            )
            guard let row else { return nil }

            let author = Author(name: name, count: row["count"], isFavourite: (row["favourite"] as Int) == 1)
            // Nobody : no article and no decision carries this name, so there
            // is no page to draw.
            return author.count == 0 && !author.isFavourite ? nil : author
        }
    }

    // MARK: - The reader's own

    /// Singles a writer out, or stops.
    ///
    /// It stars nothing, exactly as a favourite source stars nothing. Section
    /// 13 of the specification keeps the star a judgement about one article ;
    /// this is a judgement about who wrote it, and the articles underneath keep
    /// whatever the reader said about them, which for almost all of them is
    /// nothing.
    func setFavourite(_ raw: String, _ isFavourite: Bool, at date: Date = Date()) async throws {
        guard let name = Author.name(from: raw) else { return }

        try await database.writer.write { db in
            if isFavourite {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO favourite_author (id, name, created_at) VALUES (?, ?, ?)",
                    arguments: [UUID.v7(), name, date]
                )
            } else {
                try db.execute(sql: "DELETE FROM favourite_author WHERE name = ?", arguments: [name])
            }
        }
    }

    func isFavourite(_ name: String) async throws -> Bool {
        try await database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM favourite_author WHERE name = ?)",
                arguments: [name]
            ) == 1
        }
    }

    /// Every writer the reader singled out, in the order a page shows them.
    ///
    /// What synchronizing sends. The articles are never in it : a favourite is
    /// a name, and what that name has written is worked out wherever it lands.
    func favourites() async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM favourite_author")
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }

    // MARK: - The two squares

    /// The squares the writers fill on the collections page.
    ///
    /// **Two, and they are different in kind.** One is a directory of people,
    /// and it is the only square on that page that opens on something other
    /// than a list of articles ; the other is a collection like any other,
    /// holding what the writers the reader singled out have written.
    ///
    /// Neither is drawn when it holds nothing, which is how every built-in
    /// square behaves : a reader whose feeds sign nothing is not shown an empty
    /// shelf of authors.
    func collections() async throws -> [ArticleCollection] {
        try await database.writer.read { db in
            var found: [ArticleCollection] = []

            let writers = try Row.fetchOne(
                db,
                sql: """
                    SELECT (SELECT COUNT(*) FROM (SELECT 1 FROM entry e
                                                  WHERE \(Self.signed("e")) AND \(Self.shown("e"))
                                                  GROUP BY e.author)) AS signing,
                           (SELECT COUNT(*) FROM favourite_author a
                            WHERE NOT EXISTS (SELECT 1 FROM entry e
                                              WHERE e.author = a.name AND \(Self.shown("e")))) AS forgotten,
                           \(Self.cover(where: Self.signed("i"))) AS cover
                    """
            )
            // The people, counted, and never their articles : this square is a
            // way in to a list of writers, so the number under it is the number
            // of rows the reader will find there.
            let people = (writers?["signing"] as Int? ?? 0) + (writers?["forgotten"] as Int? ?? 0)
            if people > 0 {
                found.append(ArticleCollection(kind: .builtIn(.authors), count: people, cover: writers?["cover"]))
            }

            let favourites = try Row.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) AS count, \(Self.cover(where: Self.byAFavouriteAuthor("i"))) AS cover
                    FROM entry e WHERE \(Self.byAFavouriteAuthor("e")) AND \(Self.shown("e"))
                    """
            )
            if let favourites, (favourites["count"] as Int) > 0 {
                found.append(
                    ArticleCollection(
                        kind: .builtIn(.favouriteAuthors),
                        count: favourites["count"],
                        cover: favourites["cover"]
                    )
                )
            }

            return found
        }
    }

    // MARK: - The conditions, written once

    /// An article somebody put their name to.
    ///
    /// Empty is not a byline. The column is normalized on the way in, so this
    /// is the whole of what has to be excluded.
    static func signed(_ table: String) -> String {
        "\(table).author IS NOT NULL AND \(table).author <> ''"
    }

    /// An article by somebody the reader singled out.
    ///
    /// A subquery rather than a join, so it drops into a count over `entry`
    /// alone exactly as the favourite sources one does.
    static func byAFavouriteAuthor(_ table: String) -> String {
        "\(table).author IN (SELECT name FROM favourite_author)"
    }

    /// What is not a duplicate and was not hidden by a rule.
    private static func shown(_ table: String) -> String {
        "\(table).is_hidden = 0 AND \(table).duplicate_of IS NULL"
    }

    /// The newest picture among the articles a condition holds, for a square.
    private static func cover(where condition: String) -> String {
        """
        (SELECT i.image_url FROM entry i
         WHERE \(condition) AND i.image_url IS NOT NULL AND \(shown("i"))
         ORDER BY COALESCE(i.published_at, i.received_at) DESC LIMIT 1)
        """
    }

    private static func author(from row: Row) -> Author {
        Author(name: row["name"], count: row["count"], isFavourite: (row["favourite"] as Int) == 1)
    }

    /// Every byline, with what it signed and whether it is one of the reader's.
    private static let grouped = """
        SELECT e.author AS name, COUNT(*) AS count,
               EXISTS(SELECT 1 FROM favourite_author a WHERE a.name = e.author) AS favourite
        FROM entry e
        WHERE \(signed("e")) AND \(shown("e"))
        GROUP BY e.author
        """
}
