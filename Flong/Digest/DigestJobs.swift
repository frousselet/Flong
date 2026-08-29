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
nonisolated struct BriefStoriesJob: ResumableJob {
    let name = "brief-stories"
    static let batchSize = 3

    private let database: AppDatabase
    private let summarizer: StorySummarizer

    init(_ database: AppDatabase, summarizer: StorySummarizer = StorySummarizer()) {
        self.database = database
        self.summarizer = summarizer
    }

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

            // A batch that changes nothing will change nothing next time
            // either, and saying so is what stops the runner.
            guard
                brief.title != story.title || brief.summary != story.summary
                    || brief.isGenerated != story.isGenerated
                    || brief.askedIn?.identifier != story.briefLocale
            else { continue }

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
        Self.work(locale: summarizer.locale, hasModel: OnDeviceModel.isAvailable)
    }

    static func work(locale: Locale, hasModel: Bool) -> (sql: String, arguments: StatementArguments) {
        guard hasModel else {
            return ("brief_locked = 0 AND summary IS NULL", [])
        }
        return (
            """
            brief_locked = 0 AND (
                summary IS NULL OR brief_locale IS NULL OR brief_locale <> ?
            )
            """,
            [locale.identifier]
        )
    }

    private func articles(of storyID: UUID) async throws -> [(title: String, excerpt: String?)] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.title AS title, e.excerpt AS excerpt
                    FROM story_member m JOIN entry e ON e.id = m.entry_id
                    WHERE m.story_id = ? AND e.duplicate_of IS NULL
                    ORDER BY m.similarity DESC
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
            story.briefLocale = brief.askedIn?.identifier
            story.updatedAt = Date()
            try story.update(db)
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
    func buildStories(now: Date = Date()) async -> StoryBuilder.Summary {
        (try? await StoryBuilder(database).build(now: now)) ?? StoryBuilder.Summary()
    }

    /// Names and summarizes. Slow, and what the screen does not wait for : a
    /// story with no headline of its own still has its article's.
    func brief(until deadline: Date? = nil) async {
        await JobRunner(BriefStoriesJob(database)).run(until: deadline)
    }

    @discardableResult
    func rebuild(until deadline: Date? = nil, now: Date = Date()) async -> StoryBuilder.Summary {
        let summary = await buildStories(now: now)
        await brief(until: deadline)
        await nameTopics(now: now)
        return summary
    }

    /// Files the stories nobody has filed yet.
    ///
    /// **Only the ones with no subject.** A story keeps the subjects it was
    /// given for as long as it lives : sorting the whole page afresh on every
    /// rebuild made the subjects drift, and a preference the reader attached to
    /// a name that no longer exists is a preference silently thrown away.
    ///
    /// The model is shown the vocabulary the reader already has, its own past
    /// answers and its own additions alike, and reaches for those first. What it
    /// answers is folded against that vocabulary, so `cybersecurite` is filed
    /// under `Cybersécurité` rather than beside it, and only a genuinely new
    /// name is added.
    ///
    /// Re-reading what is already filed is what `rewrite` is for, and it is the
    /// reader who asks for it.
    func nameTopics(now: Date = Date()) async {
        let since = now.addingTimeInterval(-DigestStore.window)

        let stories = try? await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT s.id AS id, s.title AS title FROM story s
                    LEFT JOIN story_topic t ON t.story_id = s.id
                    WHERE s.last_at >= ? AND t.story_id IS NULL
                    ORDER BY s.last_at DESC
                    LIMIT \(TopicNamer.headlinesShown)
                    """,
                arguments: [since]
            )
            .map { (id: $0["id"] as UUID, title: $0["title"] as String) }
        }
        guard let stories, !stories.isEmpty else { return }

        let preferences = TopicPreferences(database)
        let vocabulary = (try? await preferences.vocabulary()) ?? []

        // No answer leaves the page as it is : see `TopicNamer.topics(of:)`.
        guard let assigned = await TopicNamer(locale: locale).topics(of: stories, vocabulary: vocabulary) else {
            return
        }

        // Every name is either one the reader already has, spelled some other
        // way, or a new one worth keeping.
        var filed: [UUID: [String]] = [:]
        for (id, names) in assigned {
            for name in names {
                guard let settled = try? await preferences.record(name) else { continue }
                if !(filed[id] ?? []).contains(settled) { filed[id, default: []].append(settled) }
            }
        }

        try? await database.writer.write { db in
            for (id, names) in filed {
                for name in names {
                    try StoryTopic(storyID: id, name: name).insert(db, onConflict: .ignore)
                }
            }
        }
    }

    func digest(_ topic: DigestTopic = .frontPage, now: Date = Date()) async throws -> Digest {
        try await DigestStore(database).digest(topic, now: now)
    }

    /// Throws away what the model wrote and asks it again.
    ///
    /// Nothing normally needs this : a brief is rewritten when a model turns
    /// up, and again when the reader's language changes. It is here for the
    /// case neither covers, which is a reader who simply wants a fresh reading
    /// of the page, and it forgets the refusals on the way so a model that
    /// failed earlier in the run is asked once more.
    ///
    /// A story whose headline the reader settled themselves is left alone.
    func rewrite(now: Date = Date()) async {
        OnDeviceModel.reconsider()
        await discardWhatTheModelWrote()
        await rebuild(now: now)
    }

    /// Clears the headlines, the summaries and the subjects the model wrote,
    /// leaving alone the stories whose headline the reader settled.
    func discardWhatTheModelWrote() async {
        try? await database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE story
                    SET summary = NULL, is_generated = 0, brief_locale = NULL
                    WHERE brief_locked = 0
                    """
            )
            try db.execute(
                sql: """
                    DELETE FROM story_topic
                    WHERE story_id IN (SELECT id FROM story WHERE brief_locked = 0)
                    """
            )
        }
    }

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

        let brief = StorySummarizer.fallback(for: articles ?? [])
        try? await database.writer.write { db in
            guard var story = try Story.fetchOne(db, key: storyID) else { return }
            story.title = brief.title.isEmpty ? story.title : brief.title
            story.summary = brief.summary
            // Marked as the reader's choice, so the job does not write over it.
            story.isGenerated = false
            story.briefLocked = true
            story.updatedAt = Date()
            try story.update(db)
        }
    }

    /// The articles of one story, newest first, for the list beneath a card.
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

    /// The articles of the window that made no story.
    func looseArticles(now: Date = Date(), limit: Int = 200) async throws -> [ArticleSummary] {
        let since = now.addingTimeInterval(-DigestStore.window)

        return try await database.writer.read { db in
            try ArticleSummary.fetchAll(
                db,
                sql: """
                    \(ArticleStore.columns)
                    FROM entry e
                    JOIN feed f ON f.id = e.feed_id
                    LEFT JOIN story_member m ON m.entry_id = e.id
                    WHERE m.entry_id IS NULL AND e.is_hidden = 0 AND e.duplicate_of IS NULL
                      AND COALESCE(e.published_at, e.received_at) >= ?
                    ORDER BY date DESC
                    LIMIT \(limit)
                    """,
                arguments: [since]
            )
        }
    }
}
