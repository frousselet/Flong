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
/// Stories **grow**. An article that arrives an hour later joins the story that
/// is already there rather than starting a new one, which is what lets the
/// interface say that something has been running for two hours and is still
/// going. That is why they are stored rather than recomputed on each render.
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

    /// How far back a story stays open. Beyond it, an article about the same
    /// subject starts a new story, which is right : it is a new development and
    /// not the same one.
    static let linkWindow: TimeInterval = 3 * 24 * 60 * 60

    /// What the digest looks back over at most.
    static let defaultWindow: TimeInterval = 30 * 24 * 60 * 60

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

    @discardableResult
    func build(window: TimeInterval = StoryBuilder.defaultWindow, now: Date = Date()) async throws -> Summary {
        let since = now.addingTimeInterval(-window)

        var candidates = try await unassignedCandidates(since: since)
        guard !candidates.isEmpty else { return Summary() }

        var clusters = try await openClusters(since: now.addingTimeInterval(-Self.linkWindow))

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

    /// The cluster sharing the most with an article, when that is enough.
    private static func nearest(_ candidate: Candidate, in clusters: [Cluster]) -> Int? {
        var best: (index: Int, similarity: Double)?

        for (index, cluster) in clusters.enumerated() {
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
            isNew: true
        )
    }

    // MARK: - The store

    private func unassignedCandidates(since: Date) async throws -> [Candidate] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.id AS id, e.feed_id AS feed_id, e.title AS title,
                           COALESCE(e.excerpt, '') AS excerpt,
                           COALESCE(e.published_at, e.received_at) AS date
                    FROM entry e
                    LEFT JOIN story_member m ON m.entry_id = e.id
                    WHERE m.entry_id IS NULL AND e.is_hidden = 0
                      AND COALESCE(e.published_at, e.received_at) >= ?
                    ORDER BY date ASC
                    """,
                arguments: [since]
            )
            .map { row in
                let title: String = row["title"]
                let excerpt: String = row["excerpt"]

                return Candidate(
                    id: row["id"],
                    feedID: row["feed_id"],
                    date: row["date"],
                    title: title,
                    // The title counts twice : a headline says what an article
                    // is about, and a standfirst says how.
                    terms: TextSignatures.terms(of: title + " " + title + " " + excerpt)
                )
            }
        }
    }

    /// The stories still open to new articles.
    private func openClusters(since: Date) async throws -> [Cluster] {
        try await database.writer.read { db in
            let stories = try Story.filter(Story.Columns.lastAt >= since).fetchAll(db)

            return try stories.compactMap { story -> Cluster? in
                guard let signature = story.signature, !signature.isEmpty else { return nil }

                let members = try StoryMember.filter(Column("story_id") == story.id).fetchAll(db)
                let feeds = try UUID.fetchSet(
                    db,
                    sql: "SELECT feed_id FROM entry WHERE id IN (SELECT entry_id FROM story_member WHERE story_id = ?)",
                    arguments: [story.id]
                )

                return Cluster(
                    id: story.id,
                    title: story.title,
                    signature: signature,
                    signatures: [signature],
                    members: members.map { ($0.entryID, $0.similarity) },
                    feeds: feeds,
                    firstAt: story.firstAt,
                    lastAt: story.lastAt,
                    isNew: false
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
        try await database.writer.write { db in
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
}
