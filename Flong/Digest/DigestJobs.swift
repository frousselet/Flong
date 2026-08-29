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
        try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM story WHERE \(Self.condition)") ?? 0
        }
    }

    func step() async throws -> Int {
        let stories = try await database.writer.read { db in
            try Story.fetchAll(
                db,
                sql: "SELECT * FROM story WHERE \(Self.condition) ORDER BY last_at DESC LIMIT \(Self.batchSize)"
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
            else { continue }

            try await save(brief, for: story.id)
            changed += 1
        }
        return changed
    }

    /// A story wants a brief when it has none, and again when a model turns up
    /// after one was written without one.
    ///
    /// Without a model the summary is filled from the article's own standfirst,
    /// so the count reaches zero and the job stops rather than asking for ever.
    private static var condition: String {
        StorySummarizer.isAvailable
            ? "brief_locked = 0 AND (summary IS NULL OR is_generated = 0)"
            : "brief_locked = 0 AND summary IS NULL"
    }

    private func articles(of storyID: UUID) async throws -> [(title: String, excerpt: String?)] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.title AS title, e.excerpt AS excerpt
                    FROM story_member m JOIN entry e ON e.id = m.entry_id
                    WHERE m.story_id = ?
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
            story.updatedAt = Date()
            try story.update(db)
        }
    }
}

/// Puts the digest together : vectors, then stories, then briefs.
nonisolated struct DigestService: Sendable {
    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
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
        return summary
    }

    func digest(_ period: DigestPeriod, now: Date = Date()) async throws -> Digest {
        try await DigestStore(database).digest(period, now: now)
    }

    /// Gives a story back the headline of its own most central article.
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
                    WHERE m.story_id = ?
                    ORDER BY date DESC
                    """,
                arguments: [storyID]
            )
        }
    }

    /// The articles of the period that made no story.
    func looseArticles(_ period: DigestPeriod, now: Date = Date(), limit: Int = 200) async throws -> [ArticleSummary] {
        let since = now.addingTimeInterval(-period.duration)

        return try await database.writer.read { db in
            try ArticleSummary.fetchAll(
                db,
                sql: """
                    \(ArticleStore.columns)
                    FROM entry e
                    JOIN feed f ON f.id = e.feed_id
                    LEFT JOIN story_member m ON m.entry_id = e.id
                    WHERE m.entry_id IS NULL AND e.is_hidden = 0
                      AND COALESCE(e.published_at, e.received_at) >= ?
                    ORDER BY date DESC
                    LIMIT \(limit)
                    """,
                arguments: [since]
            )
        }
    }
}
