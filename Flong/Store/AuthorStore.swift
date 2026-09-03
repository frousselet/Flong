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
/// articles answer about themselves, asked of the row per person v26 puts
/// beside each article and grouped, exactly as the starred articles are a
/// question and not a list. Nothing has to be kept in step by hand, nothing
/// goes stale when a source is removed, and a writer whose last article was
/// purged simply stops being one.
///
/// **The row per person exists because a byline names more than one.** The
/// `author` column holds what the publisher wrote, `Claire Ancelin et Paul
/// Rey` included, and grouping on it would make those two into a third person.
/// ``index(_:byline:in:)`` writes the people out beside the article as it is
/// stored, which is the one place the two are ever put in step.
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

    // MARK: - Writing the people out beside the article

    /// Says who signed one article, and only them.
    ///
    /// **Called wherever an article's byline is written**, which is the two
    /// paths in ``FeedRefresh`` and the one in ``StreamBlock``. A path that
    /// forgot this would leave an article out of its own authors' pages, which
    /// is why `AuthorIndexTests` walks an ingestion end to end rather than
    /// trusting the call sites.
    ///
    /// The old rows go first, so an article whose byline a publisher rewrote
    /// keeps no writer it no longer names, and so that saying it twice says it
    /// once.
    static func index(_ entryID: UUID, byline: String?, in db: Database) throws {
        try db.execute(sql: "DELETE FROM entry_author WHERE entry_id = ?", arguments: [entryID])

        for (position, person) in Author.people(in: byline).enumerated() {
            try db.execute(
                sql: "INSERT OR IGNORE INTO entry_author (entry_id, name, position) VALUES (?, ?, ?)",
                arguments: [entryID, person, position]
            )
        }
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
            let favourites = Set(try String.fetchAll(db, sql: "SELECT name FROM favourite_author"))
            let notified = Set(try String.fetchAll(db, sql: "SELECT name FROM notified_author"))

            // One row per writer and per source, added up here rather than in
            // SQL : the count is over the people and the marks are over the
            // publishers, which are two different groupings of the same rows,
            // and asking twice would walk the corpus twice.
            var tallies: [String: Tally] = [:]
            for row in try Row.fetchAll(db, sql: Self.grouped) {
                let count = row["count"] as Int
                tallies[row["name"], default: Tally()].add(count, of: Self.publisher(of: row))
            }

            var found = tallies.map { name, tally in
                Author(
                    name: name,
                    count: tally.count,
                    isFavourite: favourites.contains(name),
                    notifies: notified.contains(name),
                    publishers: tally.ranked
                )
            }
            // A decision with nothing to its name is still a decision, and
            // asking to be told about somebody is one of them : a writer asked
            // about on another device may have signed nothing this one holds.
            found += favourites.union(notified).subtracting(tallies.keys)
                .map {
                    Author(
                        name: $0,
                        count: 0,
                        isFavourite: favourites.contains($0),
                        notifies: notified.contains($0)
                    )
                }

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
                    SELECT (SELECT COUNT(*) FROM entry_author a JOIN entry e ON e.id = a.entry_id
                            WHERE a.name = ? AND \(Self.shown("e"))) AS count,
                           EXISTS(SELECT 1 FROM favourite_author f WHERE f.name = ?) AS favourite,
                           EXISTS(SELECT 1 FROM notified_author n WHERE n.name = ?) AS notified
                    """,
                arguments: [name, name, name]
            )
            guard let row else { return nil }

            var tally = Tally()
            for source in try Row.fetchAll(db, sql: Self.sources, arguments: [name]) {
                tally.add(source["count"] as Int, of: Self.publisher(of: source))
            }

            let author = Author(
                name: name,
                count: row["count"],
                isFavourite: (row["favourite"] as Int) == 1,
                notifies: (row["notified"] as Int) == 1,
                publishers: tally.ranked
            )
            // Nobody : no article and no decision carries this name, so there
            // is no page to draw.
            return author.count == 0 && !author.isFavourite && !author.notifies ? nil : author
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

    /// Asks to be told when a writer publishes, or stops asking.
    ///
    /// **The same shape as the favourite above, and a different question.** The
    /// row is the request and its deletion is the `no`, so there is nothing
    /// stored about the thousands of writers nobody has an opinion on.
    ///
    /// It singles nobody out : a reader may want to hear from somebody they
    /// have no wish to gather a page about, and the other way round.
    func setNotifies(_ raw: String, _ notifies: Bool, at date: Date = Date()) async throws {
        guard let name = Author.name(from: raw) else { return }

        try await database.writer.write { db in
            if notifies {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO notified_author (id, name, created_at) VALUES (?, ?, ?)",
                    arguments: [UUID.v7(), name, date]
                )
            } else {
                try db.execute(sql: "DELETE FROM notified_author WHERE name = ?", arguments: [name])
            }
        }
    }

    /// Every writer the reader asked to be told about, in the order a page
    /// shows them.
    func notified() async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM notified_author")
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
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
                    SELECT (SELECT COUNT(DISTINCT a.name) FROM entry_author a
                            JOIN entry e ON e.id = a.entry_id
                            WHERE \(Self.shown("e"))) AS signing,
                           (SELECT COUNT(*) FROM favourite_author f
                            WHERE NOT EXISTS (SELECT 1 FROM entry_author a
                                              JOIN entry e ON e.id = a.entry_id
                                              WHERE a.name = f.name AND \(Self.shown("e")))) AS forgotten,
                           \(Self.covers(where: Self.signed("i"))) AS covers
                    """
            )
            // The people, counted, and never their articles : this square is a
            // way in to a list of writers, so the number under it is the number
            // of rows the reader will find there.
            let people = (writers?["signing"] as Int? ?? 0) + (writers?["forgotten"] as Int? ?? 0)
            if people > 0 {
                found.append(
                    ArticleCollection(
                        kind: .builtIn(.authors),
                        count: people,
                        covers: CollectionCovers.read(writers?["covers"])
                    )
                )
            }

            let favourites = try Row.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) AS count, \(Self.covers(where: Self.byAFavouriteAuthor("i"))) AS covers
                    FROM entry e WHERE \(Self.byAFavouriteAuthor("e")) AND \(Self.shown("e"))
                    """
            )
            if let favourites, (favourites["count"] as Int) > 0 {
                found.append(
                    ArticleCollection(
                        kind: .builtIn(.favouriteAuthors),
                        count: favourites["count"],
                        covers: CollectionCovers.read(favourites["covers"])
                    )
                )
            }

            return found
        }
    }

    // MARK: - The conditions, written once

    /// An article somebody put their name to.
    ///
    /// Asked of the people beside it rather than of the column : a byline that
    /// named nobody this could name leaves no rows, which is the same answer
    /// and the only one that stays true for `A and B`.
    static func signed(_ table: String) -> String {
        "EXISTS (SELECT 1 FROM entry_author a WHERE a.entry_id = \(table).id)"
    }

    /// An article one named writer signed. See ``Author`` for why the name is
    /// matched exactly.
    static func signedBy(_ table: String) -> String {
        "\(table).id IN (SELECT a.entry_id FROM entry_author a WHERE a.name = ?)"
    }

    /// An article somebody the reader singled out signed.
    ///
    /// A subquery rather than a join, so it drops into a count over `entry`
    /// alone exactly as the favourite sources one does, and so an article two
    /// favourites wrote together is counted once rather than twice.
    static func byAFavouriteAuthor(_ table: String) -> String {
        """
        \(table).id IN (SELECT a.entry_id FROM entry_author a
                        WHERE a.name IN (SELECT name FROM favourite_author))
        """
    }

    /// What is not a duplicate and was not hidden by a rule.
    private static func shown(_ table: String) -> String {
        "\(table).is_hidden = 0 AND \(table).duplicate_of IS NULL"
    }

    /// The newest picture among the articles a condition holds, for a square.
    private static func covers(where condition: String) -> String {
        CollectionCovers.sql(where: "\(condition) AND \(shown("i"))")
    }

    /// What one writer has signed, and where.
    ///
    /// The publishers are counted rather than collected, so the one a writer
    /// mostly writes for is the mark a row shows first when there is only room
    /// for a few of them.
    private struct Tally {
        var count = 0
        private var publishers: [String: Int] = [:]

        mutating func add(_ articles: Int, of publisher: String?) {
            count += articles
            guard let publisher else { return }
            publishers[publisher, default: 0] += articles
        }

        /// Most published in first, and alphabetically where two are equal so
        /// that a row does not reshuffle itself between two readings.
        var ranked: [String] {
            publishers
                .sorted { first, second in
                    first.value == second.value ? first.key < second.key : first.value > second.value
                }
                .map(\.key)
        }
    }

    /// Who published a row's feed, named the way the whole application names a
    /// publisher : the group and never the desk it arrived through.
    private static func publisher(of row: Row) -> String? {
        FeedURL.publisher(
            site: (row["site_url"] as String?).flatMap(URL.init(string:)),
            feed: (row["feed_url"] as String?).flatMap(URL.init(string:))
        )
    }

    /// Every writer, by the source they signed in.
    ///
    /// One row per pair rather than one per writer : a byline is what a page
    /// shows and where it appeared is what the marks beside it say, and both
    /// fall out of the same walk.
    private static let grouped = """
        SELECT a.name AS name, COUNT(*) AS count, f.site_url AS site_url, f.url AS feed_url
        FROM entry_author a
        JOIN entry e ON e.id = a.entry_id
        JOIN feed f ON f.id = e.feed_id
        WHERE \(shown("e"))
        GROUP BY a.name, f.id
        """

    /// The same, for one writer.
    private static let sources = """
        SELECT COUNT(*) AS count, f.site_url AS site_url, f.url AS feed_url
        FROM entry_author a
        JOIN entry e ON e.id = a.entry_id
        JOIN feed f ON f.id = e.feed_id
        WHERE a.name = ? AND \(shown("e"))
        GROUP BY f.id
        """
}
