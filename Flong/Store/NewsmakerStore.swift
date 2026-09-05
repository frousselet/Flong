//
//  NewsmakerStore.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB

/// Who the articles are about, and which of them the reader singled out.
///
/// **The list of people is not stored anywhere.** It is a question the articles
/// answer about themselves, asked of the row per person v32 puts beside each
/// article and grouped, exactly as the writers are a question and not a list.
/// Nothing has to be kept in step by hand, and somebody whose last article was
/// purged simply stops being in the directory.
///
/// **The rows are written by a job and not by the write that stores the
/// article.** A byline is a field and splitting it is a handful of string
/// operations, so ``AuthorStore/index(_:byline:in:)`` runs inside the ingestion
/// transaction. This is a model over the whole text of a piece : run there it
/// would hold the writer lock for as long as the model took, on every article
/// of every refresh. It is the resumable work of section 15 instead, and
/// ``unread(limit:)`` is its queue.
///
/// **What is stored is the reader's own**, one row per person they singled out
/// and one per person they asked to hear about, and only for those. A table of
/// everybody an article ever named would be a second copy of what the articles
/// already say.
nonisolated struct NewsmakerStore: Sendable {
    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    // MARK: - Reading the people out of the articles

    /// One article, as much of it as the reading needs.
    nonisolated struct Reading: Identifiable, Sendable {
        let id: UUID
        let title: String
        let excerpt: String?
        let text: String?
        let language: String?
        /// The byline, so that whoever signed the piece is not also counted as
        /// somebody it is about. See ``Newsmaker/people(inTitle:excerpt:text:language:signedBy:)``.
        let byline: String?
    }

    /// How many articles one batch reads.
    ///
    /// Small, because each one is a pass of a model over a whole text. The
    /// batch is read, the model is run outside any transaction, and the rows go
    /// in at the end : a large batch would hold the bodies of a hundred
    /// articles in memory for no gain, and a batch is the unit that is allowed
    /// to be interrupted.
    static let batchSize = 32

    /// The most a foreground pass reads before it announces anything.
    ///
    /// A refresh brings tens of articles and reading tens of articles is
    /// milliseconds, so the ordinary case is well under this. What the cap
    /// stops is the pass that follows an import of a thousand feeds : that
    /// backlog belongs to the job running behind the page, not to the moment
    /// between a fetch and a notification.
    static let mostBeforeAnnouncing = 200

    /// The articles nobody has been read out of yet, newest first.
    ///
    /// **Newest first, and two things depend on it.** The first is that what
    /// has just arrived is what the reader is looking at, so the directory
    /// fills from the front page backwards rather than from a corpus they read
    /// last spring. The second matters more : ``AppModel`` reads what a refresh
    /// brought before it announces anything, and it asks for that by taking the
    /// head of this queue. Oldest first, that head would be the backlog and the
    /// articles just fetched would be announced before anybody had been read
    /// out of them.
    ///
    /// Nothing is left behind either way. An article is read exactly once and
    /// is out of the queue whether it named somebody or not, so the tail is
    /// reached as surely as the head.
    ///
    /// A duplicate and a hidden article are not read : neither is shown
    /// anywhere, so a person named in one would be a row leading to nothing. A
    /// duplicate whose original is later purged stops being one, and its date
    /// is still `nil`, so it is read then.
    @concurrent
    func unread(limit: Int = batchSize) async throws -> [Reading] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.id AS id, e.title AS title, e.excerpt AS excerpt, e.author AS author,
                           e.language AS language, b.plain_text AS text
                    FROM entry e
                    LEFT JOIN entry_body b ON b.entry_id = e.id
                    WHERE e.newsmakers_at IS NULL AND \(Self.shown("e"))
                    ORDER BY e.received_at DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            )
            .map {
                Reading(
                    id: $0["id"],
                    title: $0["title"],
                    excerpt: $0["excerpt"],
                    text: $0["text"],
                    language: $0["language"],
                    byline: $0["author"]
                )
            }
        }
    }

    /// How many articles are still waiting to be read.
    @concurrent
    func outstandingCount() async throws -> Int {
        try await database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM entry e WHERE e.newsmakers_at IS NULL AND \(Self.shown("e"))"
            ) ?? 0
        }
    }

    /// Reads a batch and writes the people down beside each article.
    ///
    /// **The model runs outside the transaction and the rows go in after it.**
    /// One write per article rather than one for the batch, so a job stopped
    /// halfway keeps every article it had finished : the batch is what may be
    /// interrupted, and an article is what may not.
    ///
    /// Returns how many articles were read, which is what the runner counts.
    @discardableResult
    @concurrent
    func read(_ items: [Reading], at date: Date = Date()) async throws -> Int {
        for item in items {
            let people = Newsmaker.people(
                inTitle: item.title,
                excerpt: item.excerpt,
                text: item.text,
                language: item.language,
                signedBy: item.byline
            )

            try await database.writer.write { db in
                try Self.index(item.id, people: people, at: date, in: db)
            }
        }
        return items.count
    }

    /// Says who one article is about, and only them.
    ///
    /// The old rows go first, so an article a publisher rewrote keeps nobody it
    /// no longer names, and so that reading it twice says it once.
    ///
    /// The date is written in the same statement, which is what takes the
    /// article out of the queue : an article that named nobody is read once and
    /// never asked about again.
    static func index(
        _ entryID: UUID,
        people: [Newsmaker.Mention],
        at date: Date = Date(),
        in db: Database
    ) throws {
        try db.execute(sql: "DELETE FROM entry_newsmaker WHERE entry_id = ?", arguments: [entryID])

        for person in people {
            try db.execute(
                sql: "INSERT OR IGNORE INTO entry_newsmaker (entry_id, name, mentions) VALUES (?, ?, ?)",
                arguments: [entryID, person.name, person.times]
            )
        }
        try db.execute(sql: "UPDATE entry SET newsmakers_at = ? WHERE id = ?", arguments: [date, entryID])
    }

    /// Puts an article back in the queue, because its prose changed.
    ///
    /// What a publisher rewrote may name somebody it did not name before, and
    /// may have dropped somebody it did. Nothing is read here : this is called
    /// from the ingestion write, which is exactly where the model may not run.
    static func reread(_ entryID: UUID, in db: Database) throws {
        try db.execute(sql: "UPDATE entry SET newsmakers_at = NULL WHERE id = ?", arguments: [entryID])
    }

    // MARK: - Who there is

    /// The people the directory lists : everybody five articles name, and the
    /// reader's own whatever their count.
    ///
    /// **The threshold is applied here and never on the way in.** Every name an
    /// article gives is stored, because somebody at four articles becomes
    /// somebody at five the moment the next one lands. See
    /// ``Newsmaker/leastArticles`` for what the number is and what it was
    /// measured against.
    ///
    /// A favourite with nothing to their name is in the list all the same, with
    /// a count of nothing, and so is one with three articles. It is a decision
    /// the reader made, and a decision does not disappear because the purge
    /// took the last article it was about, because it reached this device
    /// before the articles did, or because the press has not written enough
    /// about them yet.
    func all() async throws -> [Newsmaker] {
        try await database.writer.read { db in
            let favourites = Set(try String.fetchAll(db, sql: "SELECT name FROM favourite_newsmaker"))
            let notified = Set(try String.fetchAll(db, sql: "SELECT name FROM notified_newsmaker"))

            // One row per person and per source, added up here rather than in
            // SQL : the count is over the people and the marks are over the
            // publishers, which are two groupings of the same rows, and asking
            // twice would walk the corpus twice.
            var tallies: [String: Tally] = [:]
            for row in try Row.fetchAll(db, sql: Self.grouped) {
                let count = row["count"] as Int
                tallies[row["name"], default: Tally()].add(count, of: Self.publisher(of: row))
            }

            var found = tallies.compactMap { name, tally -> Newsmaker? in
                let isFavourite = favourites.contains(name)
                let notifies = notified.contains(name)
                // Too few articles name them, and nobody asked after them : the
                // long tail is people one piece mentioned once, and a directory
                // nobody can read is a directory nobody opens.
                guard tally.count >= Newsmaker.leastArticles || isFavourite || notifies else { return nil }

                return Newsmaker(
                    name: name,
                    count: tally.count,
                    isFavourite: isFavourite,
                    notifies: notifies,
                    publishers: tally.ranked
                )
            }
            found += favourites.union(notified).subtracting(tallies.keys)
                .map {
                    Newsmaker(
                        name: $0,
                        count: 0,
                        isFavourite: favourites.contains($0),
                        notifies: notified.contains($0)
                    )
                }

            return found.sorted(by: Newsmaker.before)
        }
    }

    /// One person, for the page about them.
    ///
    /// Answers for a favourite with nothing to their name too, for the same
    /// reason ``all()`` lists them : the page is about a decision the reader
    /// made, and it has to be able to show it and to undo it.
    func newsmaker(named name: String) async throws -> Newsmaker? {
        try await database.writer.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT (SELECT COUNT(*) FROM entry_newsmaker m JOIN entry e ON e.id = m.entry_id
                            WHERE m.name = ? AND \(Self.shown("e"))) AS count,
                           EXISTS(SELECT 1 FROM favourite_newsmaker f WHERE f.name = ?) AS favourite,
                           EXISTS(SELECT 1 FROM notified_newsmaker n WHERE n.name = ?) AS notified
                    """,
                arguments: [name, name, name]
            )
            guard let row else { return nil }

            var tally = Tally()
            for source in try Row.fetchAll(db, sql: Self.sources, arguments: [name]) {
                tally.add(source["count"] as Int, of: Self.publisher(of: source))
            }

            let person = Newsmaker(
                name: name,
                count: row["count"],
                isFavourite: (row["favourite"] as Int) == 1,
                notifies: (row["notified"] as Int) == 1,
                publishers: tally.ranked
            )
            // Nobody : no article and no decision carries this name, so there
            // is no page to draw.
            return person.count == 0 && !person.isFavourite && !person.notifies ? nil : person
        }
    }

    // MARK: - The reader's own

    /// Singles somebody out, or stops.
    ///
    /// It stars nothing, exactly as a favourite writer and a favourite source
    /// star nothing. Section 13 keeps the star a judgement about one article ;
    /// this is a judgement about who the article is about, and the articles
    /// underneath keep whatever the reader said about them.
    func setFavourite(_ name: String, _ isFavourite: Bool, at date: Date = Date()) async throws {
        guard let name = Self.name(from: name) else { return }

        try await database.writer.write { db in
            if isFavourite {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO favourite_newsmaker (id, name, created_at) VALUES (?, ?, ?)",
                    arguments: [UUID.v7(), name, date]
                )
            } else {
                try db.execute(sql: "DELETE FROM favourite_newsmaker WHERE name = ?", arguments: [name])
            }
        }
    }

    /// Asks to be told when an article names somebody, or stops asking.
    ///
    /// **The same shape as the favourite above, and a different question.** The
    /// row is the request and its deletion is the `no`, so there is nothing
    /// stored about the thousands of people nobody has an opinion on.
    func setNotifies(_ name: String, _ notifies: Bool, at date: Date = Date()) async throws {
        guard let name = Self.name(from: name) else { return }

        try await database.writer.write { db in
            if notifies {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO notified_newsmaker (id, name, created_at) VALUES (?, ?, ?)",
                    arguments: [UUID.v7(), name, date]
                )
            } else {
                try db.execute(sql: "DELETE FROM notified_newsmaker WHERE name = ?", arguments: [name])
            }
        }
    }

    func isFavourite(_ name: String) async throws -> Bool {
        try await database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM favourite_newsmaker WHERE name = ?)",
                arguments: [name]
            ) == 1
        }
    }

    /// Everybody the reader singled out, in the order a page shows them.
    ///
    /// What synchronizing sends. The articles are never in it : a favourite is
    /// a name, and what names that name is worked out wherever it lands.
    func favourites() async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM favourite_newsmaker")
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }

    /// Everybody the reader asked to be told about, in the order a list shows
    /// them.
    func notified() async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM notified_newsmaker")
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }

    /// What a name has to be to stand for somebody.
    ///
    /// Only the whitespace, since what reaches here is either a name the reader
    /// tapped, which came out of ``Newsmaker`` already cleaned, or one that
    /// arrived from another device, which came out of the same rules there.
    static func name(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - The two squares

    /// The squares the people fill on the collections page.
    ///
    /// **Two, and they are different in kind**, exactly as the writers' two
    /// are. One is a directory of people and opens on a list of names ; the
    /// other is a collection like any other, holding the articles about the
    /// people the reader singled out.
    ///
    /// Neither is drawn when it holds nothing. A reader on their first launch,
    /// whose articles have not been read yet, is not shown an empty shelf.
    func collections() async throws -> [ArticleCollection] {
        try await database.writer.read { db in
            var found: [ArticleCollection] = []

            let directory = try Row.fetchOne(
                db,
                sql: """
                    SELECT (SELECT COUNT(*) FROM (
                                SELECT m.name FROM entry_newsmaker m
                                JOIN entry e ON e.id = m.entry_id
                                WHERE \(Self.shown("e"))
                                GROUP BY m.name
                                HAVING COUNT(*) >= ?
                                    OR m.name IN (SELECT name FROM favourite_newsmaker)
                                    OR m.name IN (SELECT name FROM notified_newsmaker)
                            )) AS listed,
                           (SELECT COUNT(*) FROM (
                                SELECT name FROM favourite_newsmaker
                                UNION SELECT name FROM notified_newsmaker
                            ) d
                            WHERE NOT EXISTS (SELECT 1 FROM entry_newsmaker m
                                              JOIN entry e ON e.id = m.entry_id
                                              WHERE m.name = d.name AND \(Self.shown("e")))) AS decided,
                           \(Self.covers(where: Self.aboutSomebody("i"))) AS covers
                    """,
                arguments: [Newsmaker.leastArticles]
            )
            // **The same question ``all()`` answers, asked as a count.** The
            // number under a square that opens on a list has to be the length
            // of that list : one saying six hundred over a page showing
            // twenty-three would have told the reader the wrong thing before
            // they touched it. So the threshold is here too, and so are the
            // people the reader singled out whatever their count.
            let people = (directory?["listed"] as Int? ?? 0) + (directory?["decided"] as Int? ?? 0)
            if people > 0 {
                found.append(
                    ArticleCollection(
                        kind: .builtIn(.newsmakers),
                        count: people,
                        covers: CollectionCovers.read(directory?["covers"])
                    )
                )
            }

            let favourites = try Row.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) AS count, \(Self.covers(where: Self.aboutAFavourite("i"))) AS covers
                    FROM entry e WHERE \(Self.aboutAFavourite("e")) AND \(Self.shown("e"))
                    """
            )
            if let favourites, (favourites["count"] as Int) > 0 {
                found.append(
                    ArticleCollection(
                        kind: .builtIn(.favouriteNewsmakers),
                        count: favourites["count"],
                        covers: CollectionCovers.read(favourites["covers"])
                    )
                )
            }

            return found
        }
    }

    // MARK: - The conditions, written once

    /// An article that names somebody at all.
    static func aboutSomebody(_ table: String) -> String {
        "EXISTS (SELECT 1 FROM entry_newsmaker m WHERE m.entry_id = \(table).id)"
    }

    /// An article that names one person. See ``Newsmaker`` for why the name is
    /// matched exactly.
    static func about(_ table: String) -> String {
        "\(table).id IN (SELECT m.entry_id FROM entry_newsmaker m WHERE m.name = ?)"
    }

    /// An article about somebody the reader singled out.
    ///
    /// A subquery rather than a join, so it drops into a count over `entry`
    /// alone as the favourite sources one does, and so an article naming two
    /// favourites is counted once rather than twice.
    static func aboutAFavourite(_ table: String) -> String {
        """
        \(table).id IN (SELECT m.entry_id FROM entry_newsmaker m
                        WHERE m.name IN (SELECT name FROM favourite_newsmaker))
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

    /// What one person is written about, and where.
    ///
    /// The publishers are counted rather than collected, so the paper that
    /// writes about somebody most is the mark a row shows first when there is
    /// only room for a few of them.
    private struct Tally {
        var count = 0
        private var publishers: [String: Int] = [:]

        mutating func add(_ articles: Int, of publisher: String?) {
            count += articles
            guard let publisher else { return }
            publishers[publisher, default: 0] += articles
        }

        /// Most written in first, and alphabetically where two are equal so
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

    /// Everybody, by the source that wrote about them.
    private static let grouped = """
        SELECT m.name AS name, COUNT(*) AS count, f.site_url AS site_url, f.url AS feed_url
        FROM entry_newsmaker m
        JOIN entry e ON e.id = m.entry_id
        JOIN feed f ON f.id = e.feed_id
        WHERE \(shown("e"))
        GROUP BY m.name, f.id
        """

    /// The same, for one person.
    private static let sources = """
        SELECT COUNT(*) AS count, f.site_url AS site_url, f.url AS feed_url
        FROM entry_newsmaker m
        JOIN entry e ON e.id = m.entry_id
        JOIN feed f ON f.id = e.feed_id
        WHERE m.name = ? AND \(shown("e"))
        GROUP BY f.id
        """
}
