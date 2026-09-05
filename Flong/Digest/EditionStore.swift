//
//  EditionStore.swift
//  Flong
//
//  Created by François Rousselet on 04/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import OSLog

/// Makes the editions, and reads them back.
///
/// **Ten stories, and the rest is the wire.** A front page that grew with the
/// day was a page nobody could finish, and one that reordered itself under the
/// reader on every fetch was a page nobody could return to. Ten is what a
/// person reads over a coffee ; what did not fit is not hidden, it is in the
/// section next door, and the next edition may well lead on it.
nonisolated struct EditionStore: Sendable {
    /// How many stories an edition carries.
    static let mostStories = 10

    /// How far back the archive goes.
    ///
    /// The same three days the front page reads, and for the same reason : the
    /// stories underneath are held to that window, so an edition older than it
    /// would be a page of headlines whose articles have gone.
    static let archived: TimeInterval = DigestStore.window

    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    // MARK: - Making one

    /// Opens the edition of the moment, closes whatever came before it, and
    /// fills it with the ten best stories the model has written about.
    ///
    /// **Only stories the model has written about are eligible**, which is what
    /// makes the rule that every edition is written a rule and not an
    /// aspiration. A story both voices declined would otherwise sit at the top
    /// of a page that could never be published, and one refusal would silence
    /// the whole front page for a day. It stays in the wire, where everything
    /// that is not a story stays.
    ///
    /// It follows that a device with no model builds no editions at all. That
    /// is section 14's no-model path answered honestly : the page says there is
    /// no edition and why, rather than showing one with somebody else's
    /// headline at the top of it and calling it written.
    ///
    /// - Returns: the edition of the moment, or `nil` where the reader has
    ///   switched every one of them off.
    @discardableResult
    @concurrent
    func build(_ schedule: EditionSchedule, now: Date = Date(), calendar: Calendar = .current) async throws
        -> Edition?
    {
        guard let moment = schedule.current(at: now, in: calendar) else { return nil }

        let chosen = try await candidates(now: now)

        return try await database.writer.write { db in
            // Everything that opened before this one is over. Closed rather
            // than deleted : an edition that was published is what the archive
            // is made of, and one that never was is tidied by the purge below.
            try db.execute(
                sql: "UPDATE edition SET closed_at = ?, updated_at = ? WHERE closed_at IS NULL AND opened_at < ?",
                arguments: [now, now, moment.opened]
            )

            var edition =
                try Edition.filter(Edition.Columns.openedAt == moment.opened).fetchOne(db)
                ?? Edition(slot: moment.slot, openedAt: moment.opened, updatedAt: now)

            // A closed edition is finished with. It can happen : a device
            // asleep across two boundaries opens the later one, and the earlier
            // one is history the moment it is read.
            guard edition.closedAt == nil else { return edition }

            edition.updatedAt = now
            try edition.save(db)

            try db.execute(sql: "DELETE FROM edition_story WHERE edition_id = ?", arguments: [edition.id])
            for (position, story) in chosen.enumerated() {
                try EditionStory(
                    editionID: edition.id,
                    position: position,
                    storyID: story.id,
                    title: story.title,
                    summary: story.summary,
                    isGenerated: story.isGenerated,
                    isTranslated: story.isTranslated,
                    imageURL: story.imageURL?.absoluteString
                ).insert(db)
            }
            return edition
        }
    }

    /// The stories that may stand on an edition, best first.
    ///
    /// The page's own order, and the page's own window : an edition is the
    /// front page at an hour, not a different ranking of the same stories.
    private func candidates(now: Date) async throws -> [DigestStory] {
        try await DigestStore(database).digest(.frontPage, now: now)
            .all
            .filter(\.isGenerated)
            .prefix(Self.mostStories)
            .map { $0 }
    }

    /// Throws away the editions nobody will ever see.
    ///
    /// Two kinds. One that fell out of the window the stories underneath are
    /// held to, and one that closed without ever being written : the model was
    /// unavailable for the whole of its life, and an edition with no headline
    /// of its own is not an edition. Neither is a loss, the stories themselves
    /// being untouched by any of this.
    @discardableResult
    @concurrent
    func purge(now: Date = Date()) async throws -> Int {
        try await database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM edition WHERE opened_at < ?",
                arguments: [now.addingTimeInterval(-Self.archived)]
            )
            return db.changesCount
        }
    }

    // MARK: - Reading one

    /// The edition the front page shows.
    ///
    /// **The newest published one, and not the newest one.** The edition of the
    /// moment is being written for the first minutes of its life, and a page
    /// that emptied while the model worked would be a front page that goes
    /// blank four times a day. Last night's edition stands until this morning's
    /// is written, which is what a paper on a table does.
    @concurrent
    func current(now: Date = Date()) async throws -> PublishedEdition? {
        try await database.writer.read { db in
            guard
                let edition =
                    try Edition
                    .filter(Edition.Columns.publishedAt != nil)
                    .order(Edition.Columns.openedAt.desc)
                    .fetchOne(db)
            else { return nil }

            return try Self.published(edition, in: db)
        }
    }

    /// Every published edition, newest first, for the archive.
    @concurrent
    func archive(now: Date = Date()) async throws -> [PublishedEdition] {
        try await database.writer.read { db in
            try Edition
                .filter(Edition.Columns.publishedAt != nil)
                .order(Edition.Columns.openedAt.desc)
                .fetchAll(db)
                .map { try Self.published($0, in: db) }
        }
    }

    /// One edition, its stories, and the mark each of its points wears.
    private static func published(_ edition: Edition, in db: Database) throws -> PublishedEdition {
        let stories = try Self.stories(of: edition.id, in: db)
        let filings = try Self.filings(of: edition.id, in: db)
        let symbols = try Row.fetchAll(db, sql: "SELECT name, symbol FROM topic")
            .reduce(into: [String: String]()) { found, row in
                found[row["name"]] = (row["symbol"] as String?) ?? Topic.defaultSymbol
            }

        return PublishedEdition(
            edition: edition,
            stories: stories,
            marks: Self.marks(for: edition.points, over: stories, filedAs: filings, wearing: symbols)
        )
    }

    private static func stories(of editionID: UUID, in db: Database) throws -> [EditionStory] {
        try EditionStory
            .filter(Column("edition_id") == editionID)
            .order(Column("position"))
            .fetchAll(db)
    }

    /// The subjects each of an edition's stories was filed under.
    private static func filings(of editionID: UUID, in db: Database) throws -> [UUID: [String]] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT es.story_id AS story_id, st.name AS name
                FROM edition_story es JOIN story_topic st ON st.story_id = es.story_id
                WHERE es.edition_id = ?
                """,
            arguments: [editionID]
        )
        .reduce(into: [UUID: [String]]()) { found, row in
            found[row["story_id"], default: []].append(row["name"])
        }
    }

    /// The mark each point wears.
    ///
    /// **A point is matched to the story it is about, by the words they
    /// share.** The model writes three to five sentences over ten stories and
    /// nothing links one to the other : it is free to say one thing about two
    /// of them, and asking it for a story identifier alongside each point would
    /// be index bookkeeping, which a small model does badly and which the
    /// filing already learnt not to ask for.
    ///
    /// So the two are compared rather than declared. It uses the grouping's own
    /// notion of a term, folded, split and stripped of the words every article
    /// uses, so what counts as a word here and what counts as one there cannot
    /// come to differ. The story sharing the most of them is the one the point
    /// is about, and the first subject it was filed under is the mark.
    ///
    /// **A point that matches nothing wears the tag.** Half a mark on a row of
    /// marks would read worse than a neutral one, and a point about something
    /// the filing never reached is an ordinary state rather than a fault.
    static func marks(
        for points: [String],
        over stories: [EditionStory],
        filedAs filings: [UUID: [String]],
        wearing symbols: [String: String]
    ) -> [String] {
        let named = stories.map { (story: $0, terms: Set(TextSignatures.terms(of: $0.title))) }

        return points.map { point in
            let terms = Set(TextSignatures.terms(of: point))
            let best =
                named
                .map { (story: $0.story, shared: $0.terms.intersection(terms).count) }
                .filter { $0.shared > 0 }
                .max { $0.shared < $1.shared }

            guard let subject = best.flatMap({ filings[$0.story.storyID]?.first }) else {
                return Topic.defaultSymbol
            }
            return symbols[subject] ?? Topic.defaultSymbol
        }
    }
}
