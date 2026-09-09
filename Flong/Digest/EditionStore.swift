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

    /// How many stories are looked at before the ten are taken.
    ///
    /// Wider than the front page's sixty, and it can afford to be : this read
    /// happens four times a day rather than behind every render, and the order
    /// it comes back in is not the order the page wants.
    static let considered = 120

    /// The fewest stories that still make a page.
    ///
    /// Two. A quiet night is a short paper and never a blank one, and one story
    /// under a dateline is a headline rather than an edition. A period that
    /// cannot fill two publishes nothing at all, and the paper before it stays
    /// on the table.
    static let leastStories = 2

    // MARK: - Making one

    /// Opens the edition being made, and closes whatever it supersedes.
    ///
    /// **Three moments, and this is the first of them.** The page used to be
    /// opened and filled in one call, and refilled by every later one, which is
    /// what made it move under a reader. Opening writes a row and its period
    /// and nothing else, so a pass over a store where nothing has changed costs
    /// one read.
    ///
    /// The boundary is the one **in press** where the reader already has a
    /// paper on the table, and the one that has **gone** where they do not. A
    /// fresh install pressing ahead would sit on the skeleton for twenty
    /// minutes with a finished page in the store ; a device with something to
    /// read loses nothing by being twenty minutes early, and it is what buys
    /// the notice its hour.
    ///
    /// **A boundary not later than the last page that came out mints nothing.**
    /// One guard, and it answers four things at once : a slot the reader moved
    /// backwards, a flight west, a schedule that now names an hour already
    /// covered, and a duplicated minute. Each of them would otherwise be a row
    /// with an inverted period, invisible to the screen for ever and worth a
    /// model call.
    ///
    /// - Returns: the edition being made, or `nil` where the reader has
    ///   switched every one of them off.
    @discardableResult
    @concurrent
    func open(_ schedule: EditionSchedule, now: Date = Date(), calendar: Calendar = .current) async throws
        -> Edition?
    {
        try await database.writer.write { db in
            let out = try Edition.out(by: now).fetchOne(db)

            let moment: (slot: EditionSlot, opened: Date, pressed: Date)? =
                out != nil
                ? schedule.inPress(at: now, in: calendar)
                : schedule.current(at: now, in: calendar).map { ($0.slot, $0.opened, $0.opened) }
            guard let moment else { return nil }

            // The period of the last page that actually came out, which is
            // where this one picks up. A boundary the device slept through was
            // closed and never published, so its news folds forward here rather
            // than falling between two pages ; a slot the reader switched off
            // never published either, so the next period stretches back over
            // it ; and a store with nothing published takes the three days the
            // stories are held to, which is the right first page for somebody
            // who has just imported a thousand feeds.
            let lastOut =
                try Date.fetchOne(
                    db,
                    sql: """
                        SELECT COALESCE(pressed_at, opened_at) FROM edition
                        WHERE published_at IS NOT NULL
                        ORDER BY opened_at DESC LIMIT 1
                        """
                )

            if let lastOut, moment.opened <= lastOut { return nil }

            // Everything that opened before this one is over. Closed rather
            // than deleted : an edition that came out is what the archive is
            // made of, and one that never did is abandoned, which is a thing
            // the store may be asked about, and which the purge takes.
            try db.execute(
                sql: "UPDATE edition SET closed_at = ?, updated_at = ? WHERE closed_at IS NULL AND opened_at < ?",
                arguments: [now, now, moment.opened]
            )

            if let standing = try Edition.filter(Edition.Columns.openedAt == moment.opened).fetchOne(db) {
                // A closed edition is finished with. It can happen : a device
                // asleep across two boundaries opens the later one, and the
                // earlier one is history the moment it is read.
                return standing
            }

            let edition = Edition(
                slot: moment.slot,
                openedAt: moment.opened,
                coversFrom: max(moment.pressed.addingTimeInterval(-DigestStore.window), lastOut ?? .distantPast),
                pressedAt: moment.pressed,
                updatedAt: now
            )
            try edition.insert(db)
            return edition
        }
    }

    /// Chooses the ten the page leads on, and writes them down where they have
    /// moved.
    ///
    /// **Composed again on every pass, and only until it comes out.** This is
    /// the answer to an ordering problem the old rebuild solved by brute force :
    /// only a story the model has written about may stand on a page, so a page
    /// chosen once, at grouping time, was chosen before a word had been written
    /// and stayed empty for the whole of its life. Choosing again while the page
    /// is unpublished keeps that property ; what happens exactly once is the
    /// asking, which is ``BriefEditionsJob``'s business.
    ///
    /// **It writes only where the ten have moved.** The old one dropped and
    /// re-inserted ten rows on every call, on two tables the store watcher
    /// follows, so every pass cost a window reload for a page nobody had
    /// touched. Where the same ten stand in the same order wearing the same
    /// words, this is one read and no write at all.
    ///
    /// - Returns: the rows the page now holds, in the order it shows them.
    @discardableResult
    @concurrent
    func compose(_ edition: Edition, now: Date = Date()) async throws -> [EditionStory] {
        guard !edition.isPublished else { return try await rows(of: edition.id) }

        // Read afresh below as well as here. The reading of the page and the
        // writing of it are two transactions with a model call's worth of time
        // between them for whoever holds the other lane, and a page published
        // in that gap is a page frozen : rewriting its ten from a value read
        // before it came out would undo the one guarantee this all exists for.
        let chosen = try await candidates(of: edition, now: now)
        let wanted = chosen.enumerated().map { position, story in
            EditionStory(
                editionID: edition.id,
                position: position,
                storyID: story.id,
                title: story.title,
                summary: story.summary,
                isGenerated: story.isGenerated,
                isTranslated: story.isTranslated,
                imageURL: story.imageURL?.absoluteString,
                imageCredit: story.imageCredit
            )
        }

        return try await database.writer.write { db in
            // Read back inside the write : two lanes may compose one page at
            // once, and both the freeze and the cheap comparison have to be
            // against what is there now rather than against what was there when
            // this began.
            let standing = try Edition.fetchOne(db, key: edition.id)
            guard let standing, !standing.isPublished else {
                return try Self.stories(of: edition.id, in: db)
            }
            guard try Self.stories(of: edition.id, in: db) != wanted else { return wanted }

            try db.execute(sql: "DELETE FROM edition_story WHERE edition_id = ?", arguments: [edition.id])
            for row in wanted { try row.insert(db) }
            try db.execute(
                sql: "UPDATE edition SET updated_at = ? WHERE id = ?", arguments: [now, edition.id])
            return wanted
        }
    }

    /// Writes what the model said, and lets the page come out.
    ///
    /// **Guarded on the composition still being the one that was asked
    /// about.** The model call sits between the choosing and the stamping, and
    /// a foreground lane may compose the same page while a background one is
    /// waiting on an answer. Under a rule that a page is written once and never
    /// again, a list of points describing rows the page no longer holds would
    /// be final.
    ///
    /// - Returns: whether the page was published. `false` is a page that moved
    ///   underneath, and the next turn asks about it again.
    @discardableResult
    @concurrent
    func publish(
        _ editionID: UUID,
        points: [String],
        topics: [String],
        in locale: Locale,
        composedOf ids: [UUID],
        now: Date = Date()
    ) async throws -> Bool {
        try await database.writer.write { db in
            guard var edition = try Edition.fetchOne(db, key: editionID), !edition.isPublished else { return false }
            guard try Self.stories(of: editionID, in: db).map(\.storyID) == ids else { return false }

            edition.points = points
            edition.pointTopics = topics
            edition.briefLocale = locale.identifier
            edition.askedAt = now
            edition.publishedAt = now
            edition.updatedAt = now
            try edition.update(db)
            return true
        }
    }

    /// Writes down that the model was asked and said nothing usable.
    ///
    /// Two answers, and they are not the same. A refusal carries the language
    /// it was asked in, which is what makes it durable : the ten cannot move
    /// any more, so the same question would get the same answer, and only a
    /// reader changing language re-opens it. A model that was merely unusable
    /// has said nothing about this page at all, so only the moment is written
    /// and the next turn finds the page exactly as it was.
    @concurrent
    func stamp(_ editionID: UUID, refusedIn locale: Locale?, now: Date = Date()) async throws {
        try await database.writer.write { db in
            guard var edition = try Edition.fetchOne(db, key: editionID), !edition.isPublished else { return }
            if let locale { edition.briefLocale = locale.identifier }
            edition.askedAt = now
            edition.updatedAt = now
            try edition.update(db)
        }
    }

    /// Deletes the papers the reader has unmade, and says which hours went.
    ///
    /// **A page whose hour has not come has never been seen by anybody.** The
    /// rule that a published edition is never written again protects a page a
    /// reader has read ; this one has not come out, on this device or on any
    /// other, an edition being the one thing here that does not travel.
    /// Retracting the hour is retracting the paper, and leaving it would put a
    /// page on the front that the reader deleted twenty minutes earlier, under
    /// a notice the system delivers punctually for an hour that no longer
    /// exists.
    ///
    /// Two reasons for a paper to be unmade : its hour is no longer one of the
    /// reader's, and it was written in a language that is no longer theirs.
    /// Both are one act, a choice that reached this device after the press, and
    /// both are free to act on while nobody has seen the page.
    @concurrent
    func unmakeWhatIsNotWanted(
        against schedule: EditionSchedule,
        locale: Locale,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> [Date] {
        try await database.writer.write { db in
            let coming =
                try Edition
                .filter(Edition.Columns.openedAt > now)
                .fetchAll(db)

            let unwanted = coming.filter {
                !schedule.names($0.openedAt, in: calendar)
                    || ($0.briefLocale.map { $0 != locale.identifier } ?? false)
            }
            guard !unwanted.isEmpty else { return [] }

            for edition in unwanted { try edition.delete(db) }
            return unwanted.map(\.openedAt)
        }
    }

    /// The stories that may stand on this edition, best first.
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
    /// **The order is the edition's own and no longer the front page's.** The
    /// page ranks what is happening now first, which is the right question to
    /// ask at a moment and the wrong one to ask about a stretch of time that
    /// has ended : liveness would put the period's last hour above the rest of
    /// it. And the weight is the story's weight *in the period*, not over its
    /// whole life, or a story that ran all week would lead every edition of the
    /// week on its own history.
    private func candidates(of edition: Edition, now: Date) async throws -> [DigestStory] {
        let period = edition.periodStart..<edition.periodEnd
        guard period.lowerBound < period.upperBound else { return [] }

        let digest = try await DigestStore(database)
            .digest(.frontPage, now: now, limit: Self.considered, during: period)

        return
            digest
            .all
            .filter(\.isGenerated)
            .sorted {
                let left = ($0.score(digest.scores), $0.articleCount, $0.feedCount, $0.lastAt)
                let right = ($1.score(digest.scores), $1.articleCount, $1.feedCount, $1.lastAt)
                return left > right
            }
            .prefix(Self.mostStories)
            .map { $0 }
    }

    /// The rows a page holds, in the order it shows them.
    @concurrent
    func rows(of editionID: UUID) async throws -> [EditionStory] {
        try await database.writer.read { db in try Self.stories(of: editionID, in: db) }
    }

    /// Throws away the editions nobody will ever see.
    ///
    /// Two kinds. One that fell out of the window the stories underneath are
    /// held to, and one that was abandoned : a later boundary went to press
    /// while it had still not come out, so its hour has gone and it will never
    /// be written. Neither is a loss, the stories themselves being untouched by
    /// any of this and an abandoned period folding into the page that follows.
    ///
    /// **Never the paper on the table.** The rule is an age, and a quiet reader
    /// whose periods keep failing to fill two stories legitimately keeps one
    /// page for days : the age would eventually take it and leave the front
    /// page blank, which is the one thing a paper made at an hour exists to
    /// stop.
    @discardableResult
    @concurrent
    func purge(now: Date = Date()) async throws -> Int {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    DELETE FROM edition WHERE opened_at < ?
                      AND id IS NOT (SELECT id FROM edition
                                     WHERE published_at IS NOT NULL AND opened_at <= ?
                                     ORDER BY opened_at DESC LIMIT 1)
                    """,
                arguments: [now.addingTimeInterval(-Self.archived), now]
            )
            return db.changesCount
        }
    }

    // MARK: - Reading one

    /// The edition the front page shows.
    ///
    /// **The newest one that has come out, and not the newest one written.**
    /// Two things are being kept apart here. A page still being made has no
    /// points yet, and a front page that emptied while the model worked would
    /// go blank four times a day ; and a page written ahead of its hour is
    /// tomorrow's paper, which must not arrive on the table twenty minutes
    /// early under a dateline saying otherwise. ``Edition/out(by:)`` answers
    /// both, and every reader goes through it.
    @concurrent
    func current(now: Date = Date()) async throws -> PublishedEdition? {
        try await database.writer.read { db in
            guard let edition = try Edition.out(by: now).fetchOne(db) else { return nil }
            return try Self.published(edition, in: db)
        }
    }

    /// Every edition that has come out, newest first, for the archive.
    @concurrent
    func archive(now: Date = Date()) async throws -> [PublishedEdition] {
        try await database.writer.read { db in
            try Edition.out(by: now).fetchAll(db).map { try Self.published($0, in: db) }
        }
    }

    /// The newest paper off the press, whether or not it has come out.
    ///
    /// Published, and that is the difference from ``current(now:)`` : a
    /// finished page rather than a row still being filled. It exists for the
    /// one thing that has to look past the hour, which is the notice : it is
    /// lodged in the gap, for a page nobody may see yet.
    @concurrent
    func offThePress() async throws -> Edition? {
        try await database.writer.read { db in
            try Edition
                .filter(Edition.Columns.publishedAt != nil)
                .order(Edition.Columns.openedAt.desc)
                .fetchOne(db)
        }
    }

    /// One edition, its stories, and the mark each of its points wears.
    ///
    /// **The subject was frozen with the page and the glyph was not.** A point
    /// is matched to a story by the words they share, and that match used to be
    /// worked out on every read, from a live join : the marks beside a back
    /// number drifted as the filing caught up behind it, and every archive page
    /// changed its marks at once when a reader edited a subject. What each line
    /// was about is part of what the page was. The glyph is not : it belongs to
    /// the subject, so a reader who changes it sees it change everywhere.
    ///
    /// A page written before the subjects were frozen carries none, and has its
    /// match worked out here, exactly as every page used to.
    private static func published(_ edition: Edition, in db: Database) throws -> PublishedEdition {
        let stories = try Self.stories(of: edition.id, in: db)
        let symbols = try Row.fetchAll(db, sql: "SELECT name, symbol FROM topic")
            .reduce(into: [String: String]()) { found, row in
                found[row["name"]] = (row["symbol"] as String?) ?? Topic.defaultSymbol
            }

        let named: [String]
        if edition.pointTopics.count == edition.points.count {
            named = edition.pointTopics
        } else {
            named = Self.subjects(
                for: edition.points, over: stories, filedAs: try Self.filings(of: edition.id, in: db))
        }

        return PublishedEdition(
            edition: edition,
            stories: stories,
            marks: named.map { $0.isEmpty ? Topic.defaultSymbol : (symbols[$0] ?? Topic.defaultSymbol) }
        )
    }

    /// The subjects the points of a page are about, one per point.
    ///
    /// Asked once, where the page is written, and written down beside it. See
    /// ``marks(for:over:filedAs:wearing:)`` for why the two are compared rather
    /// than declared, and ``Edition/pointTopics``.
    static func subjects(
        for points: [String],
        over stories: [EditionStory],
        filedAs filings: [UUID: [String]]
    ) -> [String] {
        let named = stories.map { (story: $0, terms: Set(TextSignatures.terms(of: $0.title))) }

        return points.map { point in
            let terms = Set(TextSignatures.terms(of: point))
            let best =
                named
                .map { (story: $0.story, shared: $0.terms.intersection(terms).count) }
                .filter { $0.shared > 0 }
                .max { $0.shared < $1.shared }

            return best.flatMap { filings[$0.story.storyID]?.first } ?? ""
        }
    }

    /// The subjects each of an edition's stories was filed under, live.
    @concurrent
    func filings(of editionID: UUID) async throws -> [UUID: [String]] {
        try await database.writer.read { db in try Self.filings(of: editionID, in: db) }
    }

    private static func stories(of editionID: UUID, in db: Database) throws -> [EditionStory] {
        try EditionStory
            .filter(Column("edition_id") == editionID)
            .order(Column("position"))
            .fetchAll(db)
    }

    /// The subjects each of an edition's stories was filed under.
    ///
    /// In the order they were filed, which a query has to ask for : a `SELECT`
    /// with no `ORDER BY` answers from whichever index SQLite decided to walk,
    /// and a point whose mark is taken from the first of a story's subjects
    /// would wear a different one each time the page was read.
    private static func filings(of editionID: UUID, in db: Database) throws -> [UUID: [String]] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT es.story_id AS story_id, st.name AS name
                FROM edition_story es JOIN story_topic st ON st.story_id = es.story_id
                WHERE es.edition_id = ?
                ORDER BY st.rowid
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
        subjects(for: points, over: stories, filedAs: filings)
            .map { $0.isEmpty ? Topic.defaultSymbol : (symbols[$0] ?? Topic.defaultSymbol) }
    }
}
