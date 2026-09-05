//
//  DigestJobs.swift
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

/// Names and summarizes the stories that have no brief yet.
///
/// A batch is small on purpose : each one is a call to the model, which takes a
/// second or two, and this runs while a reader is looking at the screen.
/// Files stories under the subjects the reader has.
///
/// **Only the ones with no subject.** A story keeps the subjects it was given
/// for as long as it lives : sorting the whole page afresh on every rebuild made
/// the subjects drift, and a preference the reader attached to a name that no
/// longer exists is a preference silently thrown away.
///
/// One story per call, each against the vocabulary the reader already has,
/// which is the seeded catalogue of sections plus whatever they wrote. The
/// model adds nothing to it.
///
/// Re-reading what is already filed is what `rewrite` is for, and it is the
/// reader who asks for it.
nonisolated struct FileStoriesJob: ResumableJob {
    let name = "file-stories"
    static let batchSize = 4

    /// What the model is asked about a story, as the store spells it.
    ///
    /// The headline and the head of the standfirst, which is the whole of the
    /// prompt. Written beside the stamp so that a story asked about under one
    /// headline and given another is asked again : the filing outruns the
    /// writing, so that is the ordinary case and not the exception.
    static let question = "s.title || char(10) || COALESCE(substr(s.summary, 1, 240), '')"

    private let database: AppDatabase
    private let locale: Locale
    private let since: Date

    init(_ database: AppDatabase, locale: Locale = .current, now: Date = Date()) {
        self.database = database
        self.locale = locale
        self.since = now.addingTimeInterval(-DigestStore.window)
    }

    /// How many stories are waiting to be filed.
    ///
    /// **The true count, whether the model can be asked or not.** It answered
    /// nought without one, so a backlog of stories waiting for Apple
    /// Intelligence to finish downloading was indistinguishable from no backlog
    /// at all, and the interface had nothing it could say about the wait.
    /// Whether anything can be done about the queue is ``step()``'s business.
    func remaining() async throws -> Int {
        let since = self.since

        return try await database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM story s
                    LEFT JOIN story_topic t ON t.story_id = s.id
                    WHERE s.last_at >= ? AND t.story_id IS NULL
                      AND (
                            s.topics_asked_at IS NULL
                            OR s.topics_asked_for IS NULL
                            OR s.topics_asked_for <> \(Self.question)
                          )
                    """,
                arguments: [since]
            ) ?? 0
        }
    }

    func step() async throws -> Int {
        guard OnDeviceModel.isAvailable else { return 0 }
        let since = self.since

        let stories = try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT s.id AS id, s.title AS title, s.summary AS summary FROM story s
                    LEFT JOIN story_topic t ON t.story_id = s.id
                    WHERE s.last_at >= ? AND t.story_id IS NULL
                      AND (
                            s.topics_asked_at IS NULL
                            OR s.topics_asked_for IS NULL
                            OR s.topics_asked_for <> \(Self.question)
                          )
                    -- **Briefed first.** A brief costs three model calls to a
                    -- filing's one, so the filing runs ahead and would decide
                    -- the one durable answer on the raw headline of whichever
                    -- article was nearest the middle of the group. Deferred and
                    -- never blocked : a story that never gets a standfirst is
                    -- still filed, behind the ones that have one.
                    ORDER BY (s.summary IS NULL), s.last_at DESC
                    LIMIT \(Self.batchSize)
                    """,
                arguments: [since]
            )
            .map { (id: $0["id"] as UUID, title: $0["title"] as String, summary: $0["summary"] as String?) }
        }
        guard !stories.isEmpty else { return 0 }

        let preferences = TopicPreferences(database)
        let namer = TopicNamer(locale: locale)

        // Read once, and allowed to throw. It was read afresh inside the loop
        // and its failure swallowed, so a read that went wrong put the model in
        // front of an empty list and every story of the batch was stamped as
        // answered by a question that was never put. Nothing a filing does
        // changes the vocabulary, so once per batch is once too often rather
        // than too few.
        let settled = try await preferences.settled()
        guard !settled.isEmpty else {
            Log.enrich.notice("No subject to file a story under yet, so nothing was asked")
            return 0
        }

        var asked = 0

        for story in stories {
            guard OnDeviceModel.isAvailable else { break }

            // **One pass, and one question.** There were two : the story was
            // filed under something a reader recognizes, and then the model was
            // let name what the story was actually about. What came of the
            // second was a drift of near synonyms of the first, in whichever
            // language the articles happened to be in. The catalogue of
            // sections is fifty-two names deep now, which is what the second pass
            // was really reaching for.
            let filed: [String]

            switch await namer.file(story.title, summary: story.summary, into: settled) {
            case .chosen(let chosen):
                filed = chosen

            case .declined:
                // The model will not write about this story, and will not next
                // time either. It keeps the subjects of its own articles and
                // the asking stops.
                filed = []

            case .unusable:
                // Not this story's fault, so it does not pay for it. Nothing is
                // stamped and the pass stops : the model is not usable now, so
                // the stories behind this one would fail the same way, and the
                // next pass finds them all still waiting.
                //
                // This is what was losing them. Every failure used to look
                // alike, the story was stamped as asked whatever had happened,
                // and one guardrail refusal or one rate limit left a fil with
                // no thématique for good.
                return asked
            }

            // Asked, and answered. A story the model answered about, even to
            // say nothing fits, is not asked again : the answer would be the
            // same, and the unfiled are taken newest first, so it would sit at
            // the head of the queue and stop everything behind it.
            try await database.writer.write { db in
                // The question beside the answer, computed by the store so the
                // two sides cannot spell it differently.
                try db.execute(
                    sql: """
                        UPDATE story
                        SET topics_asked_at = ?,
                            topics_asked_for = title || char(10) || COALESCE(substr(summary, 1, 240), '')
                        WHERE id = ?
                        """,
                    arguments: [Date(), story.id]
                )
                for name in filed {
                    try StoryTopic(storyID: story.id, name: name).insert(db, onConflict: .ignore)
                }
            }
            asked += 1
        }

        // What was asked, not what was filed : the runner stops when there is
        // nothing left to ask, which is a queue that empties rather than one
        // that stalls on whatever it cannot answer.
        return asked
    }
}

nonisolated struct BriefStoriesJob: ResumableJob {
    let name = "brief-stories"
    static let batchSize = 3

    private let database: AppDatabase
    private let summarizer: StorySummarizer
    private let since: Date

    init(_ database: AppDatabase, summarizer: StorySummarizer = StorySummarizer(), now: Date = Date()) {
        self.database = database
        self.summarizer = summarizer
        self.since = now.addingTimeInterval(-DigestStore.window)
    }

    /// The articles the model is shown, named as one value the store can compare.
    ///
    /// **The newest, because that is the list the reader is looking at.** They
    /// were the most central ones, which is a different set : the model was
    /// briefed on the heart of the group while the page showed its head, so the
    /// headline could be about articles nobody could see under it.
    ///
    /// Sorted by identifier rather than by date, so the key is a set : the same
    /// six in another order is the same question, and a newcomer displacing the
    /// oldest of them is a new one.
    static let membersKey = """
        (SELECT group_concat(id) FROM (
            SELECT hex(m.entry_id) AS id FROM story_member m JOIN entry e ON e.id = m.entry_id
            WHERE m.story_id = story.id AND e.duplicate_of IS NULL
            ORDER BY COALESCE(e.published_at, e.received_at) DESC LIMIT \(StorySummarizer.articlesShown))
         ORDER BY id)
        """

    func remaining() async throws -> Int {
        let work = self.work
        return try await database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM story WHERE \(work.sql)",
                arguments: work.arguments
            ) ?? 0
        }
    }

    func step() async throws -> Int {
        let work = self.work
        let stories = try await database.writer.read { db in
            try Story.fetchAll(
                db,
                sql: "SELECT * FROM story WHERE \(work.sql) ORDER BY last_at DESC LIMIT \(Self.batchSize)",
                arguments: work.arguments
            )
        }
        guard !stories.isEmpty else { return 0 }

        var changed = 0
        for story in stories {
            let articles = try await self.articles(of: story.id)
            let brief = await summarizer.brief(forArticles: articles)

            // **Every story looked at is written down, answer or not.** The key
            // is what takes it out of the work set, so a story whose articles
            // changed and whose model then answered word for word the same
            // would be asked again at every pass, for ever, and the runner
            // stops the whole phase on a batch that reports nothing done : the
            // stories behind it would never be reached at all.
            try await save(brief, for: story.id)
            changed += 1
        }
        return changed
    }

    /// Which stories want a brief.
    ///
    /// The rule is one thing : **has the model been asked about this story, in
    /// this language?** A story it was never asked about is asked as soon as a
    /// model appears ; one it answered, refused, or answered in the wrong
    /// language has been asked, and asking again in the same language would
    /// get the same answer ; and a reader who changes language has changed the
    /// question, so every story is asked again.
    ///
    /// That is why it is the language asked in rather than the language
    /// written in : a refusal has no language, and counting it as unanswered
    /// asked about it for ever.
    ///
    /// Without a model the summary is filled from the article's own standfirst,
    /// so the count reaches zero and the job stops rather than asking for ever.
    private var work: (sql: String, arguments: StatementArguments) {
        Self.work(locale: summarizer.locale, hasModel: OnDeviceModel.isAvailable, since: since)
    }

    static func work(locale: Locale, hasModel: Bool, since: Date) -> (
        sql: String, arguments: StatementArguments
    ) {
        guard hasModel else {
            return ("brief_locked = 0 AND summary IS NULL", [])
        }
        // **And whether it is still about the same articles.** Held to the
        // window the page reads, so what is asked again is what the reader can
        // actually open ; a story nobody can reach is not worth a model call.
        // **The language asked in, and not whether there is a summary.** A
        // brief may honestly have no standfirst : the model wrote a headline
        // and its line was a paragraph, or the story's articles carry no line
        // a publisher wrote. Asked on `summary IS NULL`, every one of those
        // came back at every pass for ever, and three of them in one batch
        // stopped the whole phase.
        return (
            """
            brief_locked = 0 AND last_at >= ? AND (
                brief_locale IS NULL OR brief_locale <> ?
                OR brief_members IS NOT \(membersKey)
            )
            """,
            [since, locale.identifier]
        )
    }

    /// What the model is shown, which is what the reader is shown.
    ///
    /// **Newest first, and not most central first.** The two are different
    /// lists : the page is a story shown for where it has got to rather than
    /// for where it started, exactly as its photograph is, and a headline
    /// written about the heart of the group is a headline about articles that
    /// may have dropped out of the three days the page reads. The same six the
    /// key above names.
    private func articles(of storyID: UUID) async throws -> [(title: String, excerpt: String?)] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.title AS title, e.excerpt AS excerpt
                    FROM story_member m JOIN entry e ON e.id = m.entry_id
                    WHERE m.story_id = ? AND e.duplicate_of IS NULL
                    ORDER BY COALESCE(e.published_at, e.received_at) DESC
                    LIMIT \(StorySummarizer.articlesShown)
                    """,
                arguments: [storyID]
            )
            .map { (title: $0["title"] as String, excerpt: $0["excerpt"] as String?) }
        }
    }

    private func save(_ brief: StoryBrief, for storyID: UUID) async throws {
        try await database.writer.write { db in
            guard var story = try Story.fetchOne(db, key: storyID) else { return }

            story.title = brief.title.isEmpty ? story.title : brief.title
            story.summary = brief.summary
            story.isGenerated = brief.isGenerated
            story.isTranslated = brief.isTranslated
            story.briefLocale = brief.askedIn?.identifier
            story.updatedAt = Date()
            try story.update(db)

            // Written in the same transaction as the brief it belongs to, and
            // written whatever the answer was : it is what says this story has
            // been asked about *these* articles, and a story left without it
            // comes back at the next pass however the model answered.
            try db.execute(
                sql: "UPDATE story SET brief_members = \(Self.membersKey) WHERE id = ?",
                arguments: [storyID]
            )
        }
    }
}

/// Names the editions and writes the lines under them.
///
/// A job like the briefs and the filings, and resumable for the same reason :
/// one call to the model apiece, and what one turn does not get through the
/// next one does.
nonisolated struct BriefEditionsJob: ResumableJob {
    let name = "brief-editions"

    /// One at a time. There are four editions a day and at most one of them is
    /// being written at any moment, so a batch is a formality ; what it buys is
    /// that a model which has gone unusable stops the job after one call rather
    /// than after ten.
    static let batchSize = 1

    private let database: AppDatabase
    private let summarizer: EditionSummarizer
    private let since: Date

    init(_ database: AppDatabase, summarizer: EditionSummarizer = EditionSummarizer(), now: Date = Date()) {
        self.database = database
        self.summarizer = summarizer
        self.since = now.addingTimeInterval(-EditionStore.archived)
    }

    /// Every article of every story on the page, as one value to compare.
    ///
    /// **Every article, and not the six the model was shown.** A story's own
    /// brief is invalidated by the articles it was written from ; an edition is
    /// invalidated by anything at all changing underneath it, which is what was
    /// asked for : an article joining any story on the page makes it a slightly
    /// different page, and the sentence over it is a question worth putting
    /// again.
    ///
    /// Sorted, so the key is a set : the same articles in another order is the
    /// same page and costs nothing, and one arriving anywhere is a new question.
    static let membersKey = """
        (SELECT group_concat(id) FROM (
            SELECT DISTINCT hex(m.entry_id) AS id
            FROM edition_story es
            JOIN story_member m ON m.story_id = es.story_id
            JOIN entry e ON e.id = m.entry_id
            WHERE es.edition_id = edition.id AND e.duplicate_of IS NULL
            ORDER BY id))
        """

    /// Which editions want a headline of their own.
    ///
    /// The same rule the stories are held to : has the model been asked about
    /// this page, in this language? One it answered, refused, or answered in
    /// the wrong language has been asked ; a reader who changes language has
    /// changed the question ; and a page whose stories have moved is a new one.
    ///
    /// Held to the window the archive keeps, so an edition nobody can reach any
    /// more is not worth a model call.
    static func work(locale: Locale, since: Date) -> (sql: String, arguments: StatementArguments) {
        (
            """
            opened_at >= ? AND (
                brief_locale IS NULL OR brief_locale <> ?
                OR brief_members IS NOT \(membersKey)
            )
            """,
            [since, locale.identifier]
        )
    }

    private var work: (sql: String, arguments: StatementArguments) {
        Self.work(locale: summarizer.locale, since: since)
    }

    func remaining() async throws -> Int {
        guard OnDeviceModel.isAvailable else { return 0 }
        let work = self.work
        return try await database.writer.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM edition WHERE \(work.sql)", arguments: work.arguments) ?? 0
        }
    }

    func step() async throws -> Int {
        guard OnDeviceModel.isAvailable else { return 0 }
        let work = self.work

        // The one being made first, then whatever closed without ever being
        // written : a reader is looking at the current page, and last night's
        // is only worth writing so the archive is not full of holes.
        let editions = try await database.writer.read { db in
            try Edition.fetchAll(
                db,
                sql: "SELECT * FROM edition WHERE \(work.sql) ORDER BY opened_at DESC LIMIT \(Self.batchSize)",
                arguments: work.arguments
            )
        }
        guard !editions.isEmpty else { return 0 }

        var asked = 0
        for edition in editions {
            let stories = try await heads(of: edition.id)
            guard stories.count > 1 else {
                // A page of one story is not a page. It is stamped all the
                // same, or the job would offer it again at every turn.
                try await stamp(edition.id, brief: nil)
                asked += 1
                continue
            }

            switch await summarizer.brief(over: stories, of: edition.slot) {
            case .wrote(let brief):
                try await stamp(edition.id, brief: brief)
                asked += 1
            case .declined:
                // The model has read this page and will not write about it.
                // A durable answer about this page, so it is stamped : asking
                // again about the same ten would get the same refusal, and the
                // page changing is what re-opens the question.
                try await stamp(edition.id, brief: nil)
                asked += 1
            case .unusable:
                // Not an answer about this page at all. Nothing is stamped and
                // the next turn finds it still waiting.
                Log.enrich.notice("An edition was left unwritten : the model was not usable")
                return asked
            }
        }
        return asked
    }

    /// The ten heads, in the order the page shows them.
    private func heads(of editionID: UUID) async throws -> [(title: String, summary: String?)] {
        try await database.writer.read { db in
            try EditionStory
                .filter(Column("edition_id") == editionID)
                .order(Column("position"))
                .fetchAll(db)
                .map { (title: $0.title, summary: $0.summary) }
        }
    }

    /// Writes what came back, and the key that says what it was written from.
    ///
    /// **`published_at` is set once and never cleared.** An edition whose
    /// stories move is re-asked and its headline is replaced, and clearing the
    /// moment would take the page off the screen while the model wrote the next
    /// one : the front page would go blank several times a day, which is
    /// exactly what a page made at an hour exists to stop.
    private func stamp(_ editionID: UUID, brief: EditionBrief?) async throws {
        try await database.writer.write { db in
            guard var edition = try Edition.fetchOne(db, key: editionID) else { return }

            if let brief {
                edition.points = brief.points
                edition.briefLocale = brief.askedIn.identifier
                if edition.publishedAt == nil { edition.publishedAt = Date() }
            } else {
                edition.briefLocale = summarizer.locale.identifier
                edition.points = []
            }
            edition.updatedAt = Date()
            try edition.update(db)

            // Written in the same transaction and written whatever the answer
            // was : it is what says this page has been asked about, and one
            // left without it comes back at every turn.
            try db.execute(
                sql: "UPDATE edition SET brief_members = \(Self.membersKey) WHERE id = ?",
                arguments: [editionID]
            )
        }
    }
}

/// Puts the digest together : vectors, then stories, then briefs.
nonisolated struct DigestService: Sendable {
    private let database: AppDatabase
    /// The language the model writes the headlines and the subjects in.
    private let locale: Locale

    init(_ database: AppDatabase, locale: Locale = .current) {
        self.database = database
        self.locale = locale
    }

    /// Brings the digest up to date, within the time it is given.
    ///
    /// The order matters and is not negotiable : a story with no articles has
    /// nothing to be named after.
    /// Groups what has arrived. Fast, and what the screen waits for.
    @discardableResult
    @concurrent
    func buildStories(now: Date = Date()) async -> StoryBuilder.Summary {
        (try? await StoryBuilder(database).build(now: now)) ?? StoryBuilder.Summary()
    }

    /// Makes the edition of the moment, and closes whatever came before it.
    ///
    /// Cheap : one read of the front page and ten rows. It runs wherever the
    /// stories are grouped, so an edition is never later than the moment its
    /// boundary passed plus however long it takes the reader to open Flong.
    @discardableResult
    @concurrent
    func buildEditions(_ schedule: EditionSchedule, now: Date = Date()) async -> Edition? {
        let store = EditionStore(database)
        do {
            let edition = try await store.build(schedule, now: now)
            try await store.purge(now: now)
            return edition
        } catch {
            Log.enrich.error("The edition could not be made : \(error, privacy: .public)")
            return nil
        }
    }

    /// Names the editions. One call to the model per page.
    @discardableResult
    @concurrent
    func briefEditions(
        until deadline: Date? = nil,
        now: Date = Date(),
        onProgress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> Int {
        await JobRunner(BriefEditionsJob(database, summarizer: EditionSummarizer(locale: locale), now: now))
            .run(until: deadline, onProgress: onProgress).done
    }

    /// Names and summarizes. Slow, and what the screen does not wait for : a
    /// story with no headline of its own still has its article's.
    @discardableResult
    @concurrent
    func brief(
        until deadline: Date? = nil,
        onProgress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> Int {
        await JobRunner(BriefStoriesJob(database)).run(until: deadline, onProgress: onProgress).done
    }

    /// How long one turn of the model's work is given when nobody named a
    /// limit.
    ///
    /// The jobs are resumable and the window follows the store, so a turn that
    /// runs out carries on at the next one. What a bound buys is that both
    /// halves get a turn at all.
    static let enrichmentTurn: TimeInterval = 120

    /// How long either half gets before the other has a go.
    static let enrichmentSlice: TimeInterval = 15

    /// Writes the headlines and files the subjects, turn about.
    ///
    /// **Turn about, and not one after the other.** A written headline says
    /// what a story is about better than the title of whichever article was
    /// nearest its middle, so the briefs still go first ; but they went first
    /// over the whole backlog, with no deadline, and a night that brought sixty
    /// stories spent every call the model would take on headlines and left the
    /// page with no subjects at all. That is the page the reader reported : the
    /// stories were written and none of them was filed under anything.
    ///
    /// A slice each, in turn, until there is nothing left to do or no time left
    /// to do it in. Neither half can starve the other, and both stop cleanly on
    /// a batch that changed nothing.
    /// - Parameter schedule: when the reader's editions come out. The page is
    ///   filled again between the briefs and the naming, and it has to be : a
    ///   story is only eligible for an edition once the model has written about
    ///   it, and the pass that builds the page runs before the pass that
    ///   writes. Built once at grouping time it found nothing eligible, stayed
    ///   empty for the whole of its life, and was stamped as a page the model
    ///   declined to name. Filling it here is what closes the circle.
    @concurrent
    func enrich(
        until deadline: Date? = nil,
        now: Date = Date(),
        schedule: EditionSchedule = .standard,
        onWriting: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        onFiling: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        onNaming: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        onPhase: @Sendable (WorkPhase) -> Void = { _ in }
    ) async {
        let end = deadline ?? Date().addingTimeInterval(Self.enrichmentTurn)

        while !Task.isCancelled, Date() < end {
            onPhase(.writing)
            let slice = min(Date().addingTimeInterval(Self.enrichmentSlice), end)
            let written = await brief(until: slice, onProgress: onWriting)

            onPhase(.filing)
            let next = min(Date().addingTimeInterval(Self.enrichmentSlice), end)
            let filed = await nameTopics(until: next, now: now, onProgress: onFiling)

            // **Last of the three, and it has to be.** The page is named over
            // the headlines of the stories on it, so a page named before they
            // were written would be named over the titles of whichever articles
            // happened to be nearest the middle of each group. It is also the
            // cheapest of the three, being one call for the whole page, so
            // going last costs it nothing : what the other two leave it is
            // always enough for one ask.
            //
            // The page is filled again first. Only a story the model has
            // written about may stand on an edition, and the pass that fills
            // the page runs at grouping time, before a word has been written :
            // built once and never again, the morning edition found nothing
            // eligible, stayed empty for the whole of its life, and was stamped
            // as a page the model had declined to name.
            await buildEditions(schedule, now: now)

            onPhase(.naming)
            let named = await briefEditions(
                until: min(Date().addingTimeInterval(Self.enrichmentSlice), end), now: now, onProgress: onNaming)

            guard written > 0 || filed > 0 || named > 0 else { break }
        }
    }

    @discardableResult
    @concurrent
    func rebuild(
        until deadline: Date? = nil,
        now: Date = Date(),
        schedule: EditionSchedule = .standard,
        onWriting: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        onFiling: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        onPhase: @Sendable (WorkPhase) -> Void = { _ in }
    ) async -> StoryBuilder.Summary {
        let summary = await buildStories(now: now)
        await enrich(
            until: deadline, now: now, schedule: schedule,
            onWriting: onWriting, onFiling: onFiling, onPhase: onPhase)
        return summary
    }

    /// Files the stories nobody has filed yet, until there are none left.
    ///
    /// A job like the others rather than a fixed handful : filing twelve stories
    /// a run left a reader with a backlog of them permanently unfiled, since a
    /// page brings in more than twelve between two openings. It runs until the
    /// backlog is empty, the time runs out, or the model gives up.
    @discardableResult
    @concurrent
    func nameTopics(
        until deadline: Date? = nil,
        now: Date = Date(),
        onProgress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> Int {
        await JobRunner(FileStoriesJob(database, locale: locale, now: now))
            .run(until: deadline, onProgress: onProgress).done
    }

    /// **`@concurrent`, and it is the whole point of this line.** The target
    /// builds with approachable concurrency, where a `nonisolated async`
    /// function runs on the actor that called it : called from the window, as
    /// this always is, the whole of reading a page ran on the main thread. The
    /// SQL itself hops to the database's own queue, but the decoding, the
    /// scoring and the sorting of sixty stories did not, and the store changes
    /// on every batch a synchronization brings in. A reader scrolling while
    /// iCloud caught up was scrolling against that.
    @concurrent
    func digest(_ topic: DigestTopic = .frontPage, now: Date = Date()) async throws -> Digest {
        try await DigestStore(database).digest(topic, now: now)
    }

    /// The edition the front page shows, and every one the archive holds.
    /// What is worth suggesting to somebody searching, out of the headlines on
    /// the page.
    ///
    /// **Here rather than at the call site, for the isolation.** It is a
    /// named-entity pass over every headline, and it was run straight from the
    /// window, which under approachable concurrency means on the main thread.
    /// `@concurrent` puts it on the global executor and hands back the words.
    @concurrent
    func subjects(in headlines: [String]) async -> [String] {
        SearchSubjects.subjects(in: headlines)
    }

    @concurrent
    func editions(now: Date = Date()) async throws -> (current: PublishedEdition?, archive: [PublishedEdition]) {
        let store = EditionStore(database)
        let archive = try await store.archive(now: now)
        return (archive.first, archive)
    }

    /// Clears the headlines, the summaries and the subjects the model wrote,
    /// leaving alone the stories whose headline the reader settled.
    @concurrent
    func discardWhatTheModelWrote() async {
        try? await database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE story
                    SET summary = NULL, is_generated = 0, is_translated = 0,
                        brief_locale = NULL, brief_members = NULL
                    WHERE brief_locked = 0
                    """
            )
            try db.execute(
                sql: """
                    DELETE FROM story_topic
                    WHERE story_id IN (SELECT id FROM story WHERE brief_locked = 0)
                    """
            )
            // Asked again means asked again : the stamp goes with the filing.
            try db.execute(sql: "UPDATE story SET topics_asked_at = NULL WHERE brief_locked = 0")
        }
    }

    @concurrent
    func dropBrief(of storyID: UUID) async {
        let articles = try? await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.title AS title, e.excerpt AS excerpt
                    FROM story_member m JOIN entry e ON e.id = m.entry_id
                    WHERE m.story_id = ? ORDER BY m.similarity DESC LIMIT 1
                    """,
                arguments: [storyID]
            )
            .map { (title: $0["title"] as String, excerpt: $0["excerpt"] as String?) }
        }

        let brief = StorySummarizer.fallback(for: articles ?? [], readIn: locale)
        try? await database.writer.write { db in
            guard var story = try Story.fetchOne(db, key: storyID) else { return }
            story.title = brief.title.isEmpty ? story.title : brief.title
            story.summary = brief.summary
            // Marked as the reader's choice, so the job does not write over it.
            story.isGenerated = false
            story.isTranslated = false
            story.briefLocked = true
            story.updatedAt = Date()
            try story.update(db)
        }
    }

    /// The articles of one story, newest first, for the list beneath a card.
    @concurrent
    func articles(of storyID: UUID) async throws -> [ArticleSummary] {
        try await database.writer.read { db in
            try ArticleSummary.fetchAll(
                db,
                sql: """
                    \(ArticleStore.columns)
                    FROM story_member m
                    JOIN entry e ON e.id = m.entry_id
                    JOIN feed f ON f.id = e.feed_id
                    WHERE m.story_id = ? AND e.duplicate_of IS NULL
                    ORDER BY date DESC
                    """,
                arguments: [storyID]
            )
        }
    }
}
