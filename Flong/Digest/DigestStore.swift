//
//  DigestStore.swift
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

/// How far back the digest looks.
nonisolated enum DigestPeriod: String, Hashable, Sendable, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: Self { self }

    var duration: TimeInterval {
        switch self {
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        case .month: 30 * 24 * 60 * 60
        }
    }
}

/// A story, as the digest shows it.
nonisolated struct DigestStory: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let summary: String?
    /// Whether a model wrote the title or the summary, which the card says.
    let isGenerated: Bool

    let articleCount: Int
    /// The rooms talking about it, a few of them named.
    let feedTitles: [String]
    let feedCount: Int

    let firstAt: Date
    let lastAt: Date
    /// Arrivals over the story's life, for the sparkline.
    let arrivals: [Int]
    /// Several rooms, in the last few hours : something is happening.
    let isLive: Bool
    /// The picture of the most recent article that has one.
    let imageURL: URL?
}

/// What the main screen shows.
nonisolated struct Digest: Hashable, Sendable {
    var live: [DigestStory] = []
    var stories: [DigestStory] = []
    /// Articles that made no story, which the tail shows as themselves.
    var looseCount = 0

    var isEmpty: Bool { live.isEmpty && stories.isEmpty && looseCount == 0 }
}

/// One article of a story, as the digest query returns it.
private struct StoryArticle {
    let storyID: UUID
    let feedTitle: String
    let date: Date
    let imageURL: URL?
}

/// Reads the digest out of the store.
nonisolated struct DigestStore: Sendable {
    /// What counts as happening now : several rooms, within these hours.
    static let liveWindow: TimeInterval = 6 * 60 * 60
    static let liveArticles = 3
    static let liveFeeds = 2

    /// How many rooms a card names before it counts the rest.
    static let namedFeeds = 3
    /// How many buckets the sparkline has.
    static let sparklineBuckets = 12

    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    func digest(_ period: DigestPeriod, now: Date = Date(), limit: Int = 60) async throws -> Digest {
        let since = now.addingTimeInterval(-period.duration)

        let (stories, members, loose) = try await database.writer.read { db in
            let stories =
                try Story
                .filter(Story.Columns.lastAt >= since)
                .order(Story.Columns.lastAt.desc)
                .limit(limit)
                .fetchAll(db)

            let members = try Row.fetchAll(
                db,
                sql: """
                    SELECT m.story_id AS story_id, f.title AS feed_title, e.image_url AS image_url,
                           COALESCE(e.published_at, e.received_at) AS date
                    FROM story_member m
                    JOIN entry e ON e.id = m.entry_id
                    JOIN feed f ON f.id = e.feed_id
                    WHERE COALESCE(e.published_at, e.received_at) >= ?
                    """,
                arguments: [since]
            )
            .map { row in
                StoryArticle(
                    storyID: row["story_id"],
                    feedTitle: row["feed_title"],
                    date: row["date"],
                    imageURL: (row["image_url"] as String?).flatMap(URL.init(string:))
                )
            }

            let loose =
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM entry e
                        LEFT JOIN story_member m ON m.entry_id = e.id
                        WHERE m.entry_id IS NULL AND e.is_hidden = 0
                          AND COALESCE(e.published_at, e.received_at) >= ?
                        """,
                    arguments: [since]
                ) ?? 0

            return (stories, members, loose)
        }

        let grouped = Dictionary(grouping: members, by: \.storyID)
        let live = now.addingTimeInterval(-Self.liveWindow)

        let built = stories.compactMap { story -> DigestStory? in
            let members = grouped[story.id] ?? []
            guard members.count > 1 else { return nil }
            return Self.story(story, members: members, liveSince: live)
        }

        var digest = Digest(looseCount: loose)
        digest.live = built.filter(\.isLive).sorted { $0.lastAt > $1.lastAt }
        digest.stories = built.filter { !$0.isLive }
            .sorted { ($0.articleCount, $0.lastAt) > ($1.articleCount, $1.lastAt) }

        return digest
    }

    private static func story(
        _ story: Story,
        members: [StoryArticle],
        liveSince: Date
    ) -> DigestStory {
        let dates = members.map(\.date).sorted()
        let recent = members.filter { $0.date >= liveSince }

        // Several rooms in a few hours is an event. Ten articles from one room
        // is a single newsroom having a busy afternoon.
        let isLive = recent.count >= liveArticles && Set(recent.map(\.feedTitle)).count >= liveFeeds

        var titles: [String] = []
        for member in members.sorted(by: { $0.date < $1.date }) where !titles.contains(member.feedTitle) {
            titles.append(member.feedTitle)
        }

        return DigestStory(
            id: story.id,
            title: story.title,
            summary: story.summary,
            isGenerated: story.isGenerated,
            articleCount: members.count,
            feedTitles: Array(titles.prefix(namedFeeds)),
            feedCount: titles.count,
            firstAt: dates.first ?? story.firstAt,
            lastAt: dates.last ?? story.lastAt,
            arrivals: sparkline(dates),
            isLive: isLive,
            // The latest article to carry a picture, since a story is shown for
            // where it has got to rather than for where it started.
            imageURL: members.sorted { $0.date > $1.date }.lazy.compactMap(\.imageURL).first
        )
    }

    /// The shape of a story's arrival, in a handful of buckets.
    ///
    /// It is what tells a burst from a trickle at a glance, which is the one
    /// thing a number cannot say.
    static func sparkline(_ dates: [Date], buckets: Int = DigestStore.sparklineBuckets) -> [Int] {
        guard let first = dates.first, let last = dates.last, last > first else {
            return Array(repeating: dates.isEmpty ? 0 : 1, count: 1)
        }

        let span = last.timeIntervalSince(first)
        var counts = Array(repeating: 0, count: buckets)

        for date in dates {
            let position = date.timeIntervalSince(first) / span
            counts[min(buckets - 1, Int(position * Double(buckets)))] += 1
        }
        return counts
    }
}
