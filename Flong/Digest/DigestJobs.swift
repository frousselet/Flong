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
    /// Where the period running now begins, which is what puts the stories of
    /// that period at the head of the queue. `nil` is the window's own head.
    ///
    /// The period running now and not the page being made : a page stops being
    /// made the moment it comes out, and the filing goes on all the same.
    private let runningFrom: Date?
    /// The one that will be asked, held rather than made twice : the guard on
    /// availability and the ask itself have to be about the same model.
    private let namer: TopicNamer

    init(
        _ database: AppDatabase,
        locale: Locale = .current,
        namer: TopicNamer? = nil,
        now: Date = Date(),
        runningFrom: Date? = nil
    ) {
        self.database = database
        self.locale = locale
        self.namer = namer ?? TopicNamer(locale: locale)
        self.since = now.addingTimeInterval(-DigestStore.window)
        self.runningFrom = runningFrom
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
        guard namer.hand.isAvailable else { return 0 }
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
                    -- **The period running now first, and the backlog behind
                    -- it.** A pass off the mains is bounded to fifteen-second
                    -- slices, so what is written is whatever the order reaches :
                    -- the stories of the period running now come first, and the
                    -- rest drain after them rather than being shut out.
                    --
                    -- **Briefed first.** A brief costs three model calls to a
                    -- filing's one, so the filing runs ahead and would decide
                    -- the one durable answer on the raw headline of whichever
                    -- article was nearest the middle of the group. Deferred and
                    -- never blocked : a story that never gets a standfirst is
                    -- still filed, behind the ones that have one.
                    ORDER BY (s.last_at >= ?) DESC, (s.summary IS NULL), s.last_at DESC
                    LIMIT \(Self.batchSize)
                    """,
                arguments: [since, runningFrom ?? since]
            )
            .map { (id: $0["id"] as UUID, title: $0["title"] as String, summary: $0["summary"] as String?) }
        }
        guard !stories.isEmpty else { return 0 }

        let preferences = TopicPreferences(database)

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
            guard namer.hand.isAvailable else { break }

            // **One pass, and one question.** There were two : the story was
            // filed under something a reader recognizes, and then the model was
            // let name what the story was actually about. What came of the
            // second was a drift of near synonyms of the first, in whichever
            // language the articles happened to be in. The catalogue of
            // sections is fifty-two names deep now, which is what the second pass
            // was really reaching for.
            let filed: [String]

            switch await namer.file(story.title, summary: story.summary, into: settled) {
            case .wrote(let chosen):
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

    /// The stretch of time the page being made is about, when one is being made.
    ///
    /// **What the page needs before what merely arrived.** The order was
    /// `last_at DESC` inside a bucket that opened at the period's start and
    /// never closed, so everything that had come in *since* the boundary sorted
    /// above the period's own stories. On a morning that means the writer works
    /// through the day's news first and the night's last, and the page it is
    /// working for cannot reach the two stories it needs for several passes.
    /// The batch is taken from the period first now, by the same predicate the
    /// composition chooses with, and from the backlog in the same call, so
    /// nothing behind it is shut out.
    private let period: Range<Date>?

    /// Where the period running now begins, which is what holds the same story
    /// back to one re-ask inside it.
    ///
    /// It is not the same thing as ``period``, and reading it as one was
    /// costing the whole meter : the page being made stops existing the moment
    /// it comes out, and the period goes on running for hours after that.
    /// `nil` only where the reader has switched every edition off.
    private let meteredFrom: Date?

    init(
        _ database: AppDatabase,
        summarizer: StorySummarizer = StorySummarizer(),
        now: Date = Date(),
        period: Range<Date>? = nil,
        meteredFrom: Date? = nil
    ) {
        self.database = database
        self.summarizer = summarizer
        self.since = now.addingTimeInterval(-DigestStore.window)
        self.period = period
        self.meteredFrom = meteredFrom ?? period?.lowerBound
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
        let period = self.period

        let stories = try await database.writer.read { db in
            // **The coming page first, by the predicate it is composed with.**
            // The bucket was `last_at >= periodStart`, which is open at the top
            // and therefore admits the whole stretch since the boundary as
            // well : within it `last_at DESC` sorts the page's own stories,
            // which are by construction the older half, strictly last.
            if let period {
                let wanted = try Story.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM story
                        WHERE \(work.sql) AND \(DigestStore.withinThePeriod)
                        ORDER BY last_at DESC
                        LIMIT \(Self.batchSize)
                        """,
                    arguments: work.arguments + DigestStore.periodArguments(period)
                )
                if !wanted.isEmpty { return wanted }
            }

            // And the backlog behind it, in the same call, so a period already
            // written cannot shut the rest of the window out. Ordered on the
            // column alone : `(last_at >= ?) DESC, last_at DESC` says exactly
            // what `last_at DESC` says, since any row above the bound already
            // sorts above any row below it, and the expression key cost a temp
            // b-tree over every story of the window on every batch.
            return try Story.fetchAll(
                db,
                sql: """
                    SELECT * FROM story WHERE \(work.sql)
                    ORDER BY last_at DESC
                    LIMIT \(Self.batchSize)
                    """,
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
        Self.work(
            locale: summarizer.locale,
            hasModel: summarizer.hand.isAvailable,
            since: since,
            askedAgainSince: meteredFrom
        )
    }

    /// Which stories want a brief, and how often the same one may be re-asked.
    ///
    /// **And whether it is still about the same articles.** Held to the window
    /// the page reads, so what is asked again is what the reader can actually
    /// open ; a story nobody can reach is not worth a model call.
    ///
    /// **The language asked in, and not whether there is a summary.** A brief
    /// may honestly have no standfirst : the model wrote a headline and its line
    /// was a paragraph, or the story's articles carry no line a publisher wrote.
    /// Asked on `summary IS NULL`, every one of those came back at every pass
    /// for ever, and three of them in one batch stopped the whole phase.
    ///
    /// **The cadence goes inside the third arm and nowhere else.** A story that
    /// has moved was asked again on every pass that reached it, so a story the
    /// press is busy with cost a call an hour all day for a headline that
    /// changed by a word ; held to once a period, it is asked again once per
    /// page it could stand on.
    ///
    /// It is emphatically **not** put in front of the first two. A story nobody
    /// has ever asked about has no headline of its own, and it is what the wire,
    /// the story screens, the subject pages, search and Spotlight would show a
    /// publisher's raw title for : confining that arm to a period would strand
    /// such a story for good, since a period only ever moves forward. What is
    /// metered is the refresh, and never the first ask.
    static func work(locale: Locale, hasModel: Bool, since: Date, askedAgainSince: Date?) -> (
        sql: String, arguments: StatementArguments
    ) {
        guard hasModel else {
            // **Held to the window, and to one look apiece.** It was
            // `summary IS NULL`, which is a scan of every story ever grouped
            // and, worse, a set the fallback cannot empty : a group whose
            // articles carry no standfirst comes back without one, so the row
            // still matches, the same three are offered at every batch, each is
            // written again, and the runner never sees a batch that did
            // nothing. The key the save writes whatever the answer was is what
            // takes a story out of the set, here as everywhere else.
            return ("brief_locked = 0 AND last_at >= ? AND brief_members IS NOT \(membersKey)", [since])
        }
        guard let askedAgainSince else {
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
        return (
            """
            brief_locked = 0 AND last_at >= ? AND (
                brief_locale IS NULL OR brief_locale <> ?
                OR ((brief_asked_at IS NULL OR brief_asked_at < ?)
                    AND brief_members IS NOT \(membersKey))
            )
            """,
            // The date test first : SQLite reads a conjunction left to right,
            // so a story already asked about inside this period is spared the
            // correlated roll-up over its own members.
            [since, locale.identifier, askedAgainSince]
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

            // **The row is written only where the answer moved it.** A model
            // asked again about a story it had already written about answers
            // word for word the same most of the time, and rewriting six
            // columns and a timestamp to say so is work nobody asked for.
            //
            // It does not spare the store a tick, and it is not meant to : the
            // key below is written in this same transaction whatever happened,
            // since that is what says the story has been asked about *these*
            // articles. What holds the window steady under a turn is the pace
            // the watcher reads at.
            let title = brief.title.isEmpty ? story.title : brief.title
            let moved =
                story.title != title || story.summary != brief.summary
                || story.isGenerated != brief.isGenerated || story.isTranslated != brief.isTranslated
                || story.generatedBy != brief.writtenBy || story.briefLocale != brief.askedIn?.identifier

            if moved {
                story.title = title
                story.summary = brief.summary
                story.isGenerated = brief.isGenerated
                story.isTranslated = brief.isTranslated
                story.generatedBy = brief.writtenBy
                story.briefLocale = brief.askedIn?.identifier
                story.updatedAt = Date()
                try story.update(db)
            }

            // Written in the same transaction as the brief it belongs to, and
            // written whatever the answer was : it is what says this story has
            // been asked about *these* articles, and a story left without it
            // comes back at the next pass however the model answered.
            try db.execute(
                sql: "UPDATE story SET brief_members = \(Self.membersKey) WHERE id = ?",
                arguments: [storyID]
            )

            // **Only where the model answered.** An unusable model has said
            // nothing about this story, and stamping it would hold the next
            // ask back for a whole period over a failure that was not the
            // story's. It is the rule ``StorySummarizer`` already keeps : a
            // brief with no language was never really asked.
            if brief.askedIn != nil {
                try db.execute(
                    sql: "UPDATE story SET brief_asked_at = ? WHERE id = ?",
                    arguments: [Date(), storyID]
                )
            }
        }
    }
}

/// Writes the few points over an edition, once, when its period has been
/// written.
///
/// A job like the briefs and the filings, and resumable for the same reason :
/// one call to the model apiece, and what one turn does not get through the
/// next one does.
///
/// **What it no longer does is ask again.** It compared every article of every
/// story on the page against a stored key, so one article joining any of the
/// ten re-opened the question and a page was written and rewritten for the
/// whole of its life : twenty to fifty asks a day for something that needs
/// four. A page about a period that has ended has nothing underneath it left to
/// change, so the key is gone and with it the question it existed to re-open.
nonisolated struct BriefEditionsJob: ResumableJob {
    let name = "brief-editions"

    /// One at a time. There are four editions a day and at most one of them is
    /// being written at any moment, so a batch is a formality ; what it buys is
    /// that a model which has gone unusable stops the job after one call rather
    /// than after ten.
    static let batchSize = 1

    /// How long an edition waits for a story of its own period that still has
    /// no headline, before going to press without it.
    ///
    /// **Without this the earliest beat wins.** Only a story the model has
    /// written about may stand on a page, and a background refresh five seconds
    /// past the press that happened to have got two stories written would
    /// freeze a two-story morning edition for five hours while forty properly
    /// written ones sat underneath it. The page is asked about when its period
    /// has been written, or when this has gone by.
    ///
    /// What makes it safe is the other half of the same test : it is skipped
    /// outright the moment nothing is outstanding, so it only bites when the
    /// model is failing, and a failing model is not made to answer by being
    /// waited on.
    static let grace: TimeInterval = 20 * 60

    /// How long a page whose model was unusable waits before being put again.
    ///
    /// ``ModelPatience/refusalPause``, deliberately and for the same reason :
    /// what stopped the last ask was the model rather than the page, and the
    /// interval a model is given to come back is the interval worth waiting
    /// before asking it anything.
    static let askAgainAfter: TimeInterval = 10 * 60

    private let database: AppDatabase
    private let summarizer: EditionSummarizer
    private let now: Date

    init(_ database: AppDatabase, summarizer: EditionSummarizer = EditionSummarizer(), now: Date = Date()) {
        self.database = database
        self.summarizer = summarizer
        self.now = now
    }

    /// Which pages could want their points written, before readiness is asked.
    ///
    /// Every clause is a decision, and together they are most of the frugality :
    ///
    /// - `published_at IS NULL` is the rule itself. A page that has come off
    ///   the press is not in the work set and can never be asked about again.
    /// - `closed_at IS NULL` is the bound on a late paper : a page whose
    ///   successor's hour has come has missed its own for good.
    /// - the hour has passed, so a page is about a period that has ended rather
    ///   than one still filling.
    /// - a language is a durable answer : asked and refused about ten stories
    ///   that can no longer move is the same answer next time, and only a
    ///   reader changing language is a different question.
    /// - the ask-again floor holds a model that was merely unusable to one
    ///   attempt per pause, inside the page's own window.
    /// - two stories at the least, so a quiet period leaves the row unstamped
    ///   and unpublished : an article arriving at twenty past can still make the
    ///   page, and the ring says nothing about a stage that will never finish.
    ///
    /// Readiness is the seventh and is not here, being a question about a row's
    /// own period : see ``isReady(_:in:)``.
    static func work(locale: Locale, now: Date = Date()) -> (sql: String, arguments: StatementArguments) {
        (
            """
            closed_at IS NULL AND published_at IS NULL
            AND opened_at <= ?
            AND (brief_locale IS NULL OR brief_locale <> ?)
            AND (asked_at IS NULL OR asked_at <= ?)
            AND (SELECT COUNT(*) FROM edition_story WHERE edition_id = edition.id) >= \(EditionStore.leastStories)
            """,
            [now, locale.identifier, now.addingTimeInterval(-askAgainAfter)]
        )
    }

    /// Whether a page's own period has been written, or has waited long enough.
    ///
    /// **Asked of the row rather than of the query.** The condition is about
    /// this page's period, and a named parameter cannot vary from row to row, so
    /// the cheap terms narrow to the one or two pages that are open at all and
    /// this is asked of each. It is the same rule ``BriefStoriesJob`` works to,
    /// read from the same function, so what counts as a story still waiting
    /// cannot come to mean two things.
    static func isReady(_ edition: Edition, in db: Database, locale: Locale, now: Date = Date()) throws -> Bool {
        guard edition.periodEnd > now.addingTimeInterval(-grace) else { return true }

        // **The writer's own question, about this page's own period.** It was
        // the unmetered one : every story of the period whose articles had
        // moved counted as still waiting, while the writer, held to one re-ask
        // a period, had already decided never to touch it again. The count
        // could not reach nought, so no page was ever ready before its grace
        // ran out and every edition came out twenty minutes after its hour,
        // four times a day.
        let stories = BriefStoriesJob.work(
            locale: locale,
            hasModel: true,
            since: now.addingTimeInterval(-DigestStore.window),
            askedAgainSince: edition.periodStart
        )

        let waiting =
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM story
                    WHERE (\(stories.sql)) AND \(DigestStore.withinThePeriod)
                    """,
                arguments: stories.arguments + DigestStore.periodArguments(of: edition)
            ) ?? 0

        return waiting == 0
    }

    /// Whether a page is waiting, without asking whether it is ready.
    ///
    /// **The cheap half, because this is asked for a number and not for work.**
    /// It ran the whole of ``due()``, and readiness is a correlated roll-up
    /// over every story of the window ; `JobRunner` asks for the count once
    /// before its loop and once after, so one turn paid for that answer three
    /// and four times over to draw a fraction. What it over-reports is a page
    /// that is waiting on its own stories, which is what the ring should be
    /// saying anyway.
    func remaining() async throws -> Int {
        guard summarizer.hand.isAvailable else { return 0 }
        let work = Self.work(locale: summarizer.locale, now: now)

        return try await database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM edition WHERE \(work.sql))",
                arguments: work.arguments
            ) ?? 0
        }
    }

    func step() async throws -> Int {
        guard summarizer.hand.isAvailable else { return 0 }
        guard let edition = try await due() else { return 0 }

        let store = EditionStore(database)
        let rows = try await store.rows(of: edition.id)
        let heads = rows.map { (title: $0.title, summary: $0.summary) }

        switch await summarizer.brief(over: heads, of: edition.slot) {
        case .wrote(let brief):
            let filings = try await store.filings(of: edition.id)
            let published = try await store.publish(
                edition.id,
                points: brief.points,
                topics: EditionStore.subjects(for: brief.points, over: rows, filedAs: filings),
                in: brief.askedIn,
                composedOf: rows.map(\.storyID)
            )
            // A page that moved under the question is a page the answer is not
            // about. Nothing is written and the next turn asks again, which is
            // one call spent rather than a page describing rows it no longer
            // holds, for ever.
            if !published {
                Log.enrich.notice("An edition moved while the model wrote about it, so it will be asked again")
            }
            return 1

        case .declined:
            // The model has read this page and will not write about it. A
            // durable answer about ten stories that can no longer move, so it
            // is stamped : asking again would get the same refusal.
            try await store.stamp(edition.id, refusedIn: summarizer.locale)
            return 1

        case .unusable:
            // Not an answer about this page at all. Only the moment is written,
            // and the next turn inside the window finds it still waiting.
            Log.enrich.notice("An edition was left unwritten : the model was not usable")
            try await store.stamp(edition.id, refusedIn: nil)
            return 0
        }
    }

    /// The page that wants writing, if any.
    ///
    /// The one being made comes first, then whatever is still open behind it :
    /// a reader is looking at the current page, and an older one is only worth
    /// writing so the archive is not full of holes.
    private func due() async throws -> Edition? {
        let work = Self.work(locale: summarizer.locale, now: now)
        let locale = summarizer.locale
        let now = self.now

        return try await database.writer.read { db in
            try Edition.fetchAll(
                db,
                sql: "SELECT * FROM edition WHERE \(work.sql) ORDER BY opened_at DESC",
                arguments: work.arguments
            )
            .first { try Self.isReady($0, in: db, locale: locale, now: now) }
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
    ///
    /// The schedule is not a courtesy : it is what cuts the stream into periods,
    /// and a story is grouped inside one of them or it is not grouped at all.
    /// See ``StoryBuilder``.
    @discardableResult
    @concurrent
    func buildStories(_ schedule: EditionSchedule, now: Date = Date()) async -> StoryBuilder.Summary {
        (try? await StoryBuilder(database).build(within: schedule, now: now)) ?? StoryBuilder.Summary()
    }

    /// Opens the edition being made, and closes whatever it supersedes.
    ///
    /// Cheap, and cheap by construction : one read, and a write only where a
    /// boundary opens or closes. It is what has to run before the model does,
    /// so the writing knows which period it is working for.
    @discardableResult
    @concurrent
    func openEdition(_ schedule: EditionSchedule, now: Date = Date()) async -> Edition? {
        do {
            return try await EditionStore(database).open(schedule, now: now)
        } catch {
            Log.enrich.error("The edition could not be opened : \(error, privacy: .public)")
            return nil
        }
    }

    /// Chooses the page and asks the model about it, once.
    ///
    /// Composing runs on every pass and writes only where the ten have moved ;
    /// the asking runs when the period has been written, and never again once
    /// the page has come out.
    @discardableResult
    @concurrent
    func makeTheEdition(
        _ schedule: EditionSchedule,
        holding size: EditionSize = .standard,
        now: Date = Date(),
        until deadline: Date? = nil,
        onNaming: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> Int {
        let store = EditionStore(database)
        do {
            // **Composed only while the page can still come out.** A row a
            // later boundary abandoned, and one the model has read and declined
            // in this language, are both finished with : composing either costs
            // a read of the whole three days and, wherever the ten have
            // shifted, ten row writes the window has to react to, for a page
            // nobody will ever see.
            if let edition = try await store.open(schedule, now: now),
                edition.closedAt == nil,
                edition.briefLocale != locale.identifier
            {
                try await store.compose(edition, holding: size, now: now)
            }
            try await store.purge(now: now)
        } catch {
            Log.enrich.error("The edition could not be made : \(error, privacy: .public)")
        }

        return await JobRunner(BriefEditionsJob(database, summarizer: EditionSummarizer(locale: locale), now: now))
            .run(until: deadline, onProgress: onNaming).done
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
        now: Date = Date(),
        page: Range<Date>? = nil,
        meteredFrom: Date? = nil,
        onProgress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> Int {
        await JobRunner(BriefStoriesJob(database, now: now, period: page, meteredFrom: meteredFrom))
            .run(until: deadline, onProgress: onProgress).done
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

    /// When the writing and the filing have to stop, which is a slice short of
    /// the end of the turn.
    ///
    /// **The naming's slice is taken, and it was left over.** The two halves
    /// above ran to the end of the turn and the naming was given whatever
    /// remained, which on the one morning it matters is nothing at all : a
    /// night's stories all want a headline, every story that gained an article
    /// wants its own again, and a hundred and twenty seconds of that leaves a
    /// deadline already gone. The page was never asked about, and the reader
    /// woke at ten to last night's paper. It is one call for a whole page, so
    /// what it costs the other two is one call apiece.
    static func writingEnds(by end: Date) -> Date { end.addingTimeInterval(-enrichmentSlice) }

    /// When the naming has to stop, which is the end of the turn or a slice
    /// from here, whichever is later.
    ///
    /// **A floor, because a slice reserved is not a slice kept.** A deadline is
    /// read before a call rather than during it, so a headline begun a moment
    /// before the writing was due to stop runs on past it and can carry the
    /// whole reservation away with it. The page is the one thing in the turn a
    /// reader is waiting for and it is a single call, so it is worth the
    /// seconds it overruns by.
    static func namingEnds(by end: Date, at now: Date = Date()) -> Date {
        max(end, now.addingTimeInterval(enrichmentSlice))
    }

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
    /// a batch that changed nothing. **And neither may starve the third**, the
    /// two of them working to a slice short of the end so the naming has one :
    /// see ``writingEnds(by:)``.
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
        holding size: EditionSize = .standard,
        onWriting: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        onFiling: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        onNaming: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        onPhase: @Sendable (WorkPhase) -> Void = { _ in }
    ) async {
        let end = deadline ?? Date().addingTimeInterval(Self.enrichmentTurn)

        // **Opened before anything is written, and made after everything is.**
        // The row and its period have to exist first, since what the writing is
        // ordered by is which stories the coming page could lead on ; and the
        // page cannot be chosen and asked about until that writing has
        // happened, only a story the model has written about being eligible.
        //
        // It used to be filled inside the loop, on every slice, which was one
        // answer to that ordering and a poor one : the ten rows were dropped
        // and written again every forty-five seconds on two tables the store
        // watcher follows, and the page went on moving under a reader for the
        // whole of its life. Once before and once after is the same ordering
        // said properly.
        //
        // **Its own clock, and not the turn's.** A turn runs for two minutes in
        // front of a reader and five behind them, and longer than that across a
        // suspension, so a boundary can pass inside one. Handed the moment the
        // turn began, both the opening and the naming worked for the period
        // before the one the device was living in.
        let coming = await openEdition(schedule)

        // **Two things, and they were read as one.** The page being made is
        // what the writing is ordered by ; the period running now is what holds
        // a busy story to one re-ask inside it, and it goes on running for
        // hours after the page has come out. Taking both from the row meant the
        // meter came off the moment an edition was published and stayed off
        // until the next boundary, which is all but the whole day : a story the
        // press was busy with cost a call on every pass, and the headline the
        // reader was looking at changed under them every few minutes.
        let page = coming.map { $0.periodStart..<$0.periodEnd }
        let metered = coming?.periodStart ?? schedule.current(at: Date())?.opened

        // A slice short of the end, and the last one belongs to the naming.
        let writing = Self.writingEnds(by: end)

        while !Task.isCancelled, Date() < writing {
            onPhase(.writing)
            let slice = min(Date().addingTimeInterval(Self.enrichmentSlice), writing)
            let written = await brief(
                until: slice, now: now, page: page, meteredFrom: metered, onProgress: onWriting)

            onPhase(.filing)
            let next = min(Date().addingTimeInterval(Self.enrichmentSlice), writing)
            let filed = await nameTopics(
                until: next, now: now, runningFrom: metered, onProgress: onFiling)

            guard written > 0 || filed > 0 else { break }
        }

        // **Last, and it has to be.** The page is named over the headlines of
        // the stories on it, so a page named before they were written would be
        // named over the titles of whichever articles happened to be nearest
        // the middle of each group. It is also the cheapest of the three, being
        // one call for a whole page, so going last costs the other two one call
        // apiece : what it works to is a slice of its own rather than whatever
        // they happened to leave, which on a morning was nothing.
        onPhase(.naming)
        await makeTheEdition(
            schedule,
            holding: size,
            until: Self.namingEnds(by: end),
            onNaming: onNaming
        )
    }

    @discardableResult
    @concurrent
    func rebuild(
        until deadline: Date? = nil,
        now: Date = Date(),
        schedule: EditionSchedule = .standard,
        holding size: EditionSize = .standard,
        onWriting: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        onFiling: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        onPhase: @Sendable (WorkPhase) -> Void = { _ in }
    ) async -> StoryBuilder.Summary {
        let summary = await buildStories(schedule, now: now)
        await enrich(
            until: deadline, now: now, schedule: schedule, holding: size,
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
        runningFrom: Date? = nil,
        onProgress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> Int {
        await JobRunner(FileStoriesJob(database, locale: locale, now: now, runningFrom: runningFrom))
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

    /// The edition the front page shows, and nothing else.
    ///
    /// Read behind every store tick, so it is one row and its ten rather than
    /// every back number there is.
    @concurrent
    func currentEdition(now: Date = Date()) async throws -> PublishedEdition? {
        try await EditionStore(database).current(now: now)
    }

    /// The back numbers, newest first, a handful at a time.
    ///
    /// - Parameter before: the hour of the oldest one already on the page.
    @concurrent
    func editionArchive(
        before boundary: Date? = nil, limit: Int = EditionStore.archivePage, now: Date = Date()
    ) async throws -> [PublishedEdition] {
        try await EditionStore(database).archive(before: boundary, limit: limit, now: now)
    }

    /// The hour of a page that is composed and still waiting to be written,
    /// which is what a second background grant is worth asking for.
    @concurrent
    func editionInThePress(now: Date = Date()) async throws -> Date? {
        try await EditionStore(database).inThePress(now: now)
    }

    /// The figures of a named handful of stories, for a page that is frozen.
    @concurrent
    func figures(of ids: [UUID], now: Date = Date()) async throws -> [UUID: DigestStory] {
        try await DigestStore(database).stories(ids, now: now)
    }

    /// The edition the front page shows, and every one the archive holds.
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
