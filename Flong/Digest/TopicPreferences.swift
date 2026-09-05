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
import OSLog

/// Where a subject came from.
///
/// Two natures, and what tells them apart is who decided : a century of
/// newspapers, or the reader. There was a third, the model's own, coined when
/// nothing it was shown covered a story ; what came of it was a drift of near
/// synonyms of the sections that already existed, so the model names nothing
/// now and the catalogue was widened instead.
///
/// The difference is what the reader may do to it. A standard one cannot be
/// deleted, since it is not a thing that was made ; the reader's own are theirs
/// to add and to remove.
///
/// One of theirs becomes standard where the catalogue takes up the name they
/// wrote : two spellings of one subject is what folding exists to prevent, and
/// of the two it is the section that carries a mark of its own and reads the
/// same on every device.
nonisolated enum TopicKind: String, Hashable, Sendable, Codable, CaseIterable {
    case standard
    case own
}

/// One subject of the vocabulary.
nonisolated struct Topic: Hashable, StoredRecord {
    static let databaseTableName = "topic"

    enum CodingKeys: String, CodingKey {
        case name
        case isOwn = "is_own"
        case kind
        case symbol
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

    /// The mark it wears, or `nil` where nothing has said one.
    ///
    /// A row of pills reading four words is four words a reader has to read ;
    /// the same row with a glyph in front of each is four shapes they
    /// recognize. The sections take theirs from the catalogue and a subject the
    /// reader wrote takes the one they picked, which is why this is a column
    /// and not a lookup : theirs is not in any catalogue.
    var symbol: String?

    var createdAt: Date

    /// What a subject wears when nothing has said otherwise.
    ///
    /// A tag, which is what a subject is : a word somebody has attached to a
    /// story. It stands for the reader's own subjects until they pick one, and
    /// for anything in the store from before there were marks at all.
    static let defaultSymbol = "tag"

    /// The mark, or the one everything falls back to.
    var mark: String { symbol ?? Self.defaultSymbol }

    init(name: String, kind: TopicKind, symbol: String? = nil, createdAt: Date = Date()) {
        self.name = name
        self.kind = kind
        self.isOwn = kind == .own
        self.symbol = symbol
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
        /// The mark it wears, never empty : see ``Topic/defaultSymbol``.
        let symbol: String

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
                    SELECT t.name AS name, t.is_own AS is_own, t.kind AS kind, t.symbol AS symbol,
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
                    kind: TopicKind(rawValue: $0["kind"] ?? "") ?? .standard,
                    symbol: ($0["symbol"] as String?) ?? Topic.defaultSymbol
                )
            }

            // **The alphabet, and nothing else.** It led with what the reader
            // had spoken about and then with what covered the most of the page,
            // which is an order that reads well on a front page and badly in a
            // list somebody is editing : a subject nudged up moved out from
            // under their finger, and a reader looking for `Météo` among the
            // sections had to know how much of the page it covers to guess
            // where it is.
            //
            // The reader's own locale rather than byte order, so `Écologie`
            // files under E rather than after Z.
            return rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// The subjects the model must choose from, which is the whole vocabulary.
    ///
    /// It used to exclude a third kind, the ones the model had coined itself :
    /// offering those back to it turned a page into a drift of near synonyms,
    /// since it reached for whatever was nearest and what was nearest was
    /// whatever it said last. It coins nothing now, so there is nothing to
    /// exclude.
    ///
    /// The reader's own come first. They wrote them, so they are the ones they
    /// will look for a story under.
    func settled() async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM topic ORDER BY kind = 'own' DESC, created_at")
        }
    }

    /// Writes down the sections every reader has, once.
    ///
    /// Idempotent, and folded like everything else : a reader who had already
    /// written `Photographie` themselves does not get a second one beside it.
    /// Theirs becomes the section, under the catalogue's spelling and mark,
    /// keeping the stories filed under it and what they said about it.
    ///
    /// **A section that has been renamed takes its stories and the reader's
    /// opinion with it.** A section is known by its name and by nothing else,
    /// so renaming one without moving the filings and the preference leaves the
    /// stories under a name that no longer exists and the reader's word
    /// attached to it.
    ///
    /// - Returns: whether the vocabulary changed, which is what tells the
    ///   caller the stories filed against the old one deserve another look.
    @discardableResult
    func seedStandards(
        _ names: [String] = StandardTopics.names(),
        renaming renamings: [(String, String)] = StandardTopics.renamings(),
        marks symbols: [String: String] = StandardTopics.symbols(),
        at date: Date = Date()
    ) async throws -> Bool {
        try await database.writer.write { db in
            var changed = false

            for (was, now) in renamings where try Self.rename(was, to: now, in: db) {
                changed = true
            }

            for name in names {
                guard let written = try Self.folded(name, in: db) else {
                    try Topic(name: name, kind: .standard, symbol: symbols[name], createdAt: date).insert(db)
                    changed = true
                    continue
                }
                if try Self.adopt(written, as: name, wearing: symbols[name], in: db) { changed = true }
            }

            // **The marks are filled in on a store that already has the
            // sections.** Every reader who was using Flong before there were
            // marks has every section already and needs none of them
            // inserted, so a seeding that only ever wrote new rows would leave
            // every one of them wearing the default for good. It is not a change to the
            // vocabulary : nothing is renamed, nothing is added, and no story
            // is asked about again, so it does not set `changed`.
            for (name, symbol) in symbols {
                try db.execute(
                    sql: "UPDATE topic SET symbol = ? WHERE name = ? AND symbol IS NULL",
                    arguments: [symbol, name]
                )
            }

            guard changed else { return false }
            try Self.reopenStoriesUnderNoSection(db)
            return true
        }
    }

    /// Moves a section, its filings and what the reader said about it onto a
    /// new name.
    ///
    /// Nothing happens where the old name is not there, or where the new one
    /// already is : the second would merge two sections, which is a different
    /// decision and not one a rename may take by itself.
    private static func rename(_ was: String, to now: String, in db: Database) throws -> Bool {
        guard try folded(was, in: db) != nil, try folded(now, in: db) == nil else { return false }

        try move(was, to: now, in: db)

        Log.enrich.notice("A section was renamed, with its stories and what was said about it")
        return true
    }

    /// Takes a subject the reader wrote into the catalogue.
    ///
    /// **The section wins, and the reader loses nothing.** A catalogue that
    /// grows a name somebody had already written meets one subject under two
    /// spellings, and leaving theirs as it was is a section that cannot be
    /// filed under, wearing the tag, sitting where the model will not find the
    /// mark. Theirs takes the catalogue's spelling and mark instead, and its
    /// stories and what they said about it come with the name.
    ///
    /// Only the reader's own : a section already standard is where seeding
    /// leaves off, which is what makes a second seeding cost nothing.
    private static func adopt(_ written: String, as name: String, wearing symbol: String?, in db: Database) throws
        -> Bool
    {
        let isOwn = try Bool.fetchOne(
            db,
            sql: "SELECT kind = ? FROM topic WHERE name = ?",
            arguments: [TopicKind.own.rawValue, written]
        )
        guard isOwn == true else { return false }

        if written != name { try move(written, to: name, in: db) }

        // The mark comes from the catalogue, which is what makes it the same on
        // every device ; where the catalogue names none, the one they picked
        // stands rather than being wiped for nothing.
        try db.execute(
            sql: "UPDATE topic SET kind = ?, is_own = 0, symbol = COALESCE(?, symbol) WHERE name = ?",
            arguments: [TopicKind.standard.rawValue, symbol, name]
        )

        Log.enrich.notice("A subject the reader wrote is a section of the catalogue now")
        return true
    }

    /// Moves a subject, its filings and what the reader said about it onto
    /// another name.
    ///
    /// The name is the only handle any of the three have, so all three move or
    /// none do. `OR IGNORE` and then a delete, since the far side may already
    /// hold a row for the same story or the same preference and a union is what
    /// is wanted there.
    private static func move(_ was: String, to now: String, in db: Database) throws {
        try db.execute(sql: "UPDATE topic SET name = ? WHERE name = ?", arguments: [now, was])
        try db.execute(sql: "UPDATE OR IGNORE story_topic SET name = ? WHERE name = ?", arguments: [now, was])
        try db.execute(sql: "DELETE FROM story_topic WHERE name = ?", arguments: [was])
        try db.execute(sql: "UPDATE OR IGNORE topic_preference SET name = ? WHERE name = ?", arguments: [now, was])
        try db.execute(sql: "DELETE FROM topic_preference WHERE name = ?", arguments: [was])
    }

    /// Asks again about the stories the vocabulary has caught up with.
    ///
    /// A story is asked about once and stamped as asked, which is right :
    /// asking again would get the same answer. It stops being right when the
    /// answer was decided by a vocabulary that has since changed. A story filed
    /// before the sections existed was shown nothing to choose from and was
    /// stamped all the same, so seeding them changed nothing for a reader
    /// already using Flong : the sections were dead names holding nothing, the
    /// page kept the model's older drift, and there was no gesture anywhere
    /// that could put it right.
    ///
    /// Only the ones under no section and none of the reader's own. A story
    /// already filed under something settled keeps it : it was asked a question
    /// the vocabulary could answer, and the answer stands.
    private static func reopenStoriesUnderNoSection(_ db: Database) throws {
        try db.execute(
            sql: """
                UPDATE story SET topics_asked_at = NULL
                WHERE topics_asked_at IS NOT NULL
                  AND id NOT IN (
                      SELECT s.story_id FROM story_topic s JOIN topic t ON t.name = s.name
                  )
                """
        )
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
    func add(_ name: String, symbol: String? = nil, at date: Date = Date()) async throws -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        return try await database.writer.write { db in
            if let existing = try Self.folded(name, in: db) { return existing }
            try Topic(name: name, kind: .own, symbol: symbol, createdAt: date).insert(db)
            return name
        }
    }

    /// Changes the mark a subject the reader wrote wears.
    ///
    /// Theirs only. A section's mark comes from the catalogue and is the same
    /// on every device : one the reader could change here would be one more
    /// thing to carry between them, for a glyph nobody chose in the first place.
    func setSymbol(_ symbol: String, of name: String) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE topic SET symbol = ? WHERE name = ? AND kind = 'own'",
                arguments: [symbol, name]
            )
        }
    }

    /// The mark each subject wears, by name.
    ///
    /// What the pills are drawn from. One read of a table of fifty-odd rows,
    /// beside the scores the page already reads.
    func symbols() async throws -> [String: String] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT name, symbol FROM topic")
                .reduce(into: [String: String]()) { found, row in
                    found[row["name"]] = (row["symbol"] as String?) ?? Topic.defaultSymbol
                }
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
            // a preference the reader can never find again to take back, since
            // the screen that manages them reads the vocabulary and nothing
            // else. It becomes theirs : they pressed it, so it is a name they
            // should be able to remove, and only their own may be removed.
            let name = try Self.folded(name, in: db) ?? name
            try Topic(name: name, kind: .own, createdAt: date).insert(db, onConflict: .ignore)

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
