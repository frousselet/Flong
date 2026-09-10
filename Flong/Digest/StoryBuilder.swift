//
//  StoryBuilder.swift
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

/// Groups the articles of a window into stories.
///
/// The rule is one line long : an article joins the story it shares the most
/// vocabulary with, if it shares enough, and otherwise waits for another article
/// to share enough with it. Everything else is thresholds and bookkeeping.
///
/// Stories **grow, and only inside their own period**. An article that arrives
/// an hour later joins the story that is already there rather than starting a
/// new one, which is what lets the interface say that something has been
/// running for two hours and is still going. That is why they are stored rather
/// than recomputed on each render. What it stops at is the next boundary : an
/// article on the far side of one starts a story of its own, however much
/// vocabulary it shares with the last, so a story is always about one paper's
/// stretch of time and never about two.
nonisolated struct StoryBuilder: Sendable {
    /// How much vocabulary two articles must share to start a story between
    /// them.
    ///
    /// Stricter than joining : the first pair decides what a story is about, and
    /// a pair joined by chance drags everything near it into a story about
    /// nothing.
    static let seedThreshold = 0.30

    /// How much an article must share with a story that already exists.
    static let joinThreshold = 0.22

    /// How far back a story is looked at at all.
    ///
    /// **An outer bound, and never what closes a story.** It read as though it
    /// were : beyond it, an article about the same subject starts a new story.
    /// It is a filter on which stored rows are fetched, `last_at >= now - this`,
    /// and `last_at` is pushed forward by every article that joins, so a story
    /// taking one article every few hours never closed and grew for as long as
    /// the press kept at it. What closes a story is the boundary its period ends
    /// at ; this only spares the reads of the ones no candidate could reach.
    static let linkWindow: TimeInterval = 3 * 24 * 60 * 60

    /// What the digest looks back over at most.
    static let defaultWindow: TimeInterval = 30 * 24 * 60 * 60

    /// How many articles are let go of in one statement, SQLite binding a few
    /// hundred values to one and a changed schedule freeing a whole window.
    static let releasedAtOnce = 400

    /// What one run came to.
    nonisolated struct Summary: Hashable, Sendable {
        var created = 0
        var joined = 0
        var unassigned = 0
    }

    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    /// An article waiting to be placed.
    private struct Candidate: Sendable {
        let id: UUID
        let feedID: UUID
        let date: Date
        let title: String
        let terms: [String]
        /// The boundary closing the period it belongs to, or nothing where the
        /// reader has switched every edition off.
        let period: Date?
        var signature = TextSignature(weights: [:])
    }

    /// A story being built up in memory.
    private struct Cluster {
        var id: UUID
        var title: String
        var signature: TextSignature
        var signatures: [TextSignature]
        var members: [(id: UUID, similarity: Double)]
        var feeds: Set<UUID>
        var firstAt: Date
        var lastAt: Date
        /// The boundary closing the period it belongs to, which is the hour of
        /// the edition it may stand on.
        ///
        /// For a story already in the store it is taken from its newest
        /// article, and what falls outside it is handed back : see
        /// ``openClusters(since:within:in:)``.
        var period: Date?
        var isNew: Bool

        mutating func add(_ candidate: Candidate, similarity: Double) {
            signatures.append(candidate.signature)
            // The signature is the mean of its articles', so a story that
            // develops follows what it is actually about.
            signature = TextSignature.mean(of: signatures)

            members.append((candidate.id, similarity))
            feeds.insert(candidate.feedID)
            firstAt = min(firstAt, candidate.date)
            lastAt = max(lastAt, candidate.date)
        }
    }

    // MARK: - Building

    /// Groups what has arrived, one period at a time.
    ///
    /// - Parameter schedule: the hours the reader's editions come out at, which
    ///   is what cuts the stream into periods. Nothing is cut where every one of
    ///   them is switched off : there are no boundaries then, and no editions
    ///   for a story to be held to the shape of.
    @discardableResult
    func build(
        within schedule: EditionSchedule? = nil,
        window: TimeInterval = StoryBuilder.defaultWindow,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> Summary {
        let since = now.addingTimeInterval(-window)

        // **The stories are read first, and what a boundary has taken out from
        // under them is let go before anything is placed.** A story is cut to
        // one period as it is built, and that is not the only way one comes to
        // straddle a boundary : the reader may move an hour or switch a slot
        // off, and every story that was whole under the old schedule is a
        // straddler under the new one. Held only where it is built, the rule
        // would be true of what arrives next and false of what is already
        // there, which is a page that disagrees with itself about what a story
        // is. Let go here, the pieces are candidates again in this same pass
        // and regroup with the articles of their own period.
        var (clusters, released) = try await openClusters(
            since: now.addingTimeInterval(-Self.linkWindow), within: schedule, in: calendar)
        if !released.isEmpty { try await release(released) }

        var candidates = try await unassignedCandidates(since: since, within: schedule, in: calendar)
        guard !candidates.isEmpty else {
            // A story the cut left with one article is no longer a story, and
            // saying so cannot wait for the next arrival.
            if !released.isEmpty { try await removeEmptyStories() }
            return Summary()
        }

        // Rarity is measured over the window being built, so a word that is
        // everywhere this month counts for nothing this month.
        let corpus = candidates.map(\.terms) + clusters.flatMap { _ in [[String]]() }
        let frequencies = TextSignatures.documentFrequencies(of: corpus)

        for index in candidates.indices {
            candidates[index].signature = TextSignatures.signature(
                of: candidates[index].terms,
                documentFrequencies: frequencies,
                documentCount: corpus.count
            )
        }

        var summary = Summary()

        for candidate in candidates where !candidate.signature.isEmpty {
            if let index = Self.nearest(candidate, in: clusters) {
                let similarity = clusters[index].signature.similarity(to: candidate.signature)
                clusters[index].add(candidate, similarity: similarity)
                summary.joined += 1
                continue
            }
            // Nothing to join, so it waits : the next article close enough to it
            // will start a story with it.
            clusters.append(Self.seed(from: candidate))
        }

        // A cluster of one is not a story. It goes back to the tail, where the
        // interface shows it as the ordinary article it is.
        let stories = clusters.filter { $0.members.count > 1 }
        summary.created = stories.filter(\.isNew).count
        summary.unassigned = clusters.count - stories.count

        try await save(stories, at: now)
        try await removeEmptyStories()

        if summary.created > 0 || summary.joined > 0 {
            Log.enrich.notice("Digest : \(summary.created) stories opened, \(summary.joined) articles joined one")
        }
        return summary
    }

    /// The cluster sharing the most with an article, when that is enough and
    /// when the two belong to one and the same period.
    ///
    /// **The period is tested before the vocabulary, and it is not a
    /// threshold.** Nothing here compared an article to the story's dates at
    /// all : it was signature against signature and a bar, so a bulletin a
    /// publisher repeats every three hours became one story of seventeen
    /// airings across three days, and a page made at noon led on articles from
    /// the night before. Vocabulary says what two articles are about ; it
    /// cannot say whether they are the same news, and across a boundary they
    /// are not.
    private static func nearest(_ candidate: Candidate, in clusters: [Cluster]) -> Int? {
        var best: (index: Int, similarity: Double)?

        for (index, cluster) in clusters.enumerated() {
            guard cluster.period == candidate.period else { continue }
            let similarity = cluster.signature.similarity(to: candidate.signature)

            // A cluster of one is still only a candidate pair, and pairs are
            // held to the stricter threshold.
            let bar = cluster.members.count == 1 ? seedThreshold : joinThreshold
            guard similarity >= bar else { continue }
            if similarity > (best?.similarity ?? 0) { best = (index, similarity) }
        }

        return best?.index
    }

    private static func seed(from candidate: Candidate) -> Cluster {
        Cluster(
            id: .v7(),
            title: candidate.title,
            signature: candidate.signature,
            signatures: [candidate.signature],
            members: [(candidate.id, 1)],
            feeds: [candidate.feedID],
            firstAt: candidate.date,
            lastAt: candidate.date,
            period: candidate.period,
            isNew: true
        )
    }

    // MARK: - The store

    private func unassignedCandidates(
        since: Date, within schedule: EditionSchedule?, in calendar: Calendar
    ) async throws -> [Candidate] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.id AS id, e.feed_id AS feed_id, e.title AS title,
                           COALESCE(e.excerpt, '') AS excerpt,
                           COALESCE(e.published_at, e.received_at) AS date
                    FROM entry e
                    LEFT JOIN story_member m ON m.entry_id = e.id
                    WHERE m.entry_id IS NULL AND e.is_hidden = 0 AND e.duplicate_of IS NULL
                      AND COALESCE(e.published_at, e.received_at) >= ?
                    ORDER BY date ASC
                    """,
                arguments: [since]
            )
            .map { row in
                let title: String = row["title"]
                let excerpt: String = row["excerpt"]
                let date: Date = row["date"]

                return Candidate(
                    id: row["id"],
                    feedID: row["feed_id"],
                    date: date,
                    title: title,
                    // The title counts twice : a headline says what an article
                    // is about, and a standfirst says how.
                    terms: TextSignatures.terms(of: title + " " + title + " " + excerpt),
                    // The date it wears, which is the date the reader reads on
                    // the row : an article is in the period it says it is in,
                    // and not in the one it happened to be fetched in.
                    period: schedule?.period(of: date, in: calendar)
                )
            }
        }
    }

    /// The stories still open to new articles, held to one period apiece.
    ///
    /// **One read for the members, their dates and their rooms**, where it was
    /// a query for the rows and a second for the feeds behind them, per story.
    /// The dates are what this now turns on : a story's period is the one its
    /// newest article is in, and anything of its own that falls outside it is
    /// handed back.
    ///
    /// Its newest and not its oldest, so that a story the reader is following
    /// keeps its name and its headline where it is still running, and it is the
    /// older half that is let go and grouped again. The other way about would
    /// freeze the row in a period that has closed and start the current one
    /// from a headline nobody has written yet.
    ///
    /// - Returns: the clusters, and the articles their stories have lost.
    private func openClusters(
        since: Date, within schedule: EditionSchedule?, in calendar: Calendar
    ) async throws -> (clusters: [Cluster], released: [UUID]) {
        try await database.writer.read { db in
            let stories = try Story.filter(Story.Columns.lastAt >= since).fetchAll(db)
            var clusters: [Cluster] = []
            var released: [UUID] = []

            for story in stories {
                guard let signature = story.signature, !signature.isEmpty else { continue }

                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT m.entry_id AS entry_id, m.similarity AS similarity, e.feed_id AS feed_id,
                               COALESCE(e.published_at, e.received_at) AS date
                        FROM story_member m JOIN entry e ON e.id = m.entry_id
                        WHERE m.story_id = ?
                        """,
                    arguments: [story.id]
                )

                let period = schedule?.period(of: story.lastAt, in: calendar)
                var members: [(id: UUID, similarity: Double)] = []
                var feeds: Set<UUID> = []
                var firstAt = Date.distantFuture
                var lastAt = Date.distantPast

                for row in rows {
                    let date: Date = row["date"]
                    guard schedule?.period(of: date, in: calendar) == period else {
                        released.append(row["entry_id"])
                        continue
                    }
                    members.append((row["entry_id"], row["similarity"]))
                    feeds.insert(row["feed_id"])
                    firstAt = min(firstAt, date)
                    lastAt = max(lastAt, date)
                }

                guard !members.isEmpty else { continue }

                clusters.append(
                    Cluster(
                        id: story.id,
                        title: story.title,
                        signature: signature,
                        signatures: [signature],
                        members: members,
                        feeds: feeds,
                        firstAt: firstAt,
                        lastAt: lastAt,
                        period: period,
                        isNew: false
                    )
                )
            }

            return (clusters, released)
        }
    }

    /// Hands back the articles a boundary has taken out from under their story.
    ///
    /// In batches, since a schedule the reader has just changed can free the
    /// whole window at once and SQLite binds a few hundred values to a
    /// statement.
    private func release(_ entries: [UUID]) async throws {
        try await database.writer.write { db in
            for start in stride(from: 0, to: entries.count, by: Self.releasedAtOnce) {
                let batch = Array(entries[start..<min(start + Self.releasedAtOnce, entries.count)])
                try db.execute(
                    sql: "DELETE FROM story_member WHERE entry_id IN (\(databaseQuestionMarks(count: batch.count)))",
                    arguments: StatementArguments(batch)
                )
            }
        }
    }

    private func save(_ clusters: [Cluster], at now: Date) async throws {
        guard !clusters.isEmpty else { return }

        try await database.writer.write { db in
            for cluster in clusters {
                var story =
                    try Story.fetchOne(db, key: cluster.id)
                    ?? Story(id: cluster.id, title: cluster.title, firstAt: cluster.firstAt, lastAt: cluster.lastAt)

                story.signature = cluster.signature
                story.articleCount = cluster.members.count
                story.feedCount = cluster.feeds.count
                story.firstAt = cluster.firstAt
                story.lastAt = cluster.lastAt
                story.updatedAt = now

                // A story whose title came from an article rather than a model
                // follows its most central article as the group settles.
                if !story.isGenerated {
                    story.title = cluster.title
                }
                try story.upsert(db)

                for member in cluster.members {
                    try StoryMember(storyID: cluster.id, entryID: member.id, similarity: member.similarity)
                        .upsert(db)
                }
            }
        }
    }

    /// Drops the stories a purge left with fewer than two articles.
    private func removeEmptyStories() async throws {
        try await database.writer.write { db in try Self.removeEmptyStories(in: db) }
    }

    /// The same, inside a transaction somebody else opened.
    ///
    /// Removing a source empties stories exactly as a purge does, and what a
    /// story needs in order to still be a story is written here and nowhere
    /// else : two rooms covering one event. A second copy of that rule would be
    /// a front page that disagreed with itself depending on which path had last
    /// touched it.
    static func removeEmptyStories(in db: Database) throws {
        try db.execute(
            sql: """
                DELETE FROM story WHERE id IN (
                    SELECT s.id FROM story s
                    LEFT JOIN story_member m ON m.story_id = s.id
                    GROUP BY s.id HAVING COUNT(m.entry_id) < 2
                )
                """
        )
    }
}
