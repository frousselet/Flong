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
/// What the front page is showing.
///
/// It replaces the day, week and month selector. A period is a question about
/// the calendar, and nobody watching a subject asks it : they ask what is
/// happening, and then what is happening about one thing in particular.
nonisolated enum DigestTopic: Hashable, Sendable, Identifiable {
    /// Everything, which is what the page opens on.
    case frontPage
    /// One subject, as the model named it.
    case named(String)

    var id: Self { self }

    var name: String? {
        guard case .named(let name) = self else { return nil }
        return name
    }

    func holds(_ topics: [String]) -> Bool {
        switch self {
        case .frontPage: true
        case .named(let name): topics.contains(name)
        }
    }
}

/// One of the rooms covering a story, as the page shows it.
///
/// A mark rather than a name : four names are a line of text nobody reads,
/// four marks are a glance.
nonisolated struct FeedMark: Hashable, Sendable, Identifiable {
    let title: String
    let iconURL: URL?
    let siteURL: URL?

    var id: String { title }
}

/// A story, as the digest shows it.
nonisolated struct DigestStory: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let summary: String?
    /// Whether a model wrote the title or the summary, which the card says.
    let isGenerated: Bool

    let articleCount: Int
    /// The rooms talking about it, a few of them shown.
    let feedMarks: [FeedMark]
    let feedCount: Int

    let firstAt: Date
    let lastAt: Date
    /// Arrivals over the story's life, for the sparkline.
    let arrivals: [Int]
    /// Several rooms, in the last few hours : something is happening.
    let isLive: Bool
    /// The picture of the most recent article that has one.
    let imageURL: URL?
    /// The subjects the model put it under, which may be none and may be
    /// several : a story is rarely about one thing.
    let topics: [String]

    /// What the reader has said about this story, taken from its subjects.
    ///
    /// Asking for more of anything wins : a reader who wants more of one of
    /// its subjects meant this story, whatever they think of the others. It is
    /// only when nothing about it was asked for that asking for less applies.
    func score(_ scores: [String: Int]) -> Int {
        let said = topics.compactMap { scores[$0] }
        return said.max().map { $0 > 0 ? $0 : (said.min() ?? 0) } ?? 0
    }
}

/// What the main screen shows.
nonisolated struct Digest: Hashable, Sendable {
    var live: [DigestStory] = []
    var stories: [DigestStory] = []
    /// Articles that made no story, which the tail shows as themselves.
    var looseCount = 0

    /// The subjects on the page, whichever one is being shown : narrowing to
    /// one must not take the others off the page, or the only way back would
    /// be a button that is no longer there.
    var topics: [String] = []

    /// What the reader has said about them, for the ones they have spoken
    /// about at all.
    var scores: [String: Int] = [:]

    var isEmpty: Bool { live.isEmpty && stories.isEmpty && looseCount == 0 }
}

/// One article of a story, as the digest query returns it.
private struct StoryArticle {
    let storyID: UUID
    let feedTitle: String
    let feedIconURL: URL?
    let feedSiteURL: URL?
    let date: Date
    let imageURL: URL?
}

/// Reads the digest out of the store.
nonisolated struct DigestStore: Sendable {
    /// What counts as happening now : several rooms, within these hours.
    static let liveWindow: TimeInterval = 6 * 60 * 60
    static let liveArticles = 3
    static let liveFeeds = 2

    /// How far back the front page looks.
    ///
    /// Not a day : a reader opening Flong on Monday morning would find a page
    /// emptied by the weekend. Not a month either, since a front page is about
    /// what is current, and everything older is still reachable through unread,
    /// the library and search. Three days is a story still worth a headline.
    static let window: TimeInterval = 3 * 24 * 60 * 60

    /// How many rooms a row shows the mark of before it counts the rest.
    static let namedFeeds = 4
    /// How many buckets the sparkline has.
    static let sparklineBuckets = 12

    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    func digest(_ topic: DigestTopic = .frontPage, now: Date = Date(), limit: Int = 60) async throws -> Digest {
        let since = now.addingTimeInterval(-Self.window)
        let scores = try await TopicPreferences(database).scores()

        let (stories, topics, members, loose) = try await database.writer.read { db in
            let stories =
                try Story
                .filter(Story.Columns.lastAt >= since)
                .order(Story.Columns.lastAt.desc)
                .limit(limit)
                .fetchAll(db)

            // One row per subject a story is under, folded back into a list
            // per story.
            let topics = try StoryTopic.fetchAll(db).reduce(into: [UUID: [String]]()) { topics, row in
                topics[row.storyID, default: []].append(row.name)
            }

            let members = try Row.fetchAll(
                db,
                sql: """
                    SELECT m.story_id AS story_id, f.title AS feed_title,
                           f.icon_url AS icon_url, COALESCE(f.site_url, f.url) AS site_url,
                           e.image_url AS image_url,
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
                    feedIconURL: (row["icon_url"] as String?).flatMap(URL.init(string:)),
                    feedSiteURL: (row["site_url"] as String?).flatMap(URL.init(string:)),
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

            return (stories, topics, members, loose)
        }

        let grouped = Dictionary(grouping: members, by: \.storyID)
        let live = now.addingTimeInterval(-Self.liveWindow)

        let all = stories.compactMap { story -> DigestStory? in
            let members = grouped[story.id] ?? []
            guard members.count > 1 else { return nil }
            return Self.story(story, members: members, topics: topics[story.id] ?? [], liveSince: live)
        }

        // The pills are read from the whole page, then the page is narrowed :
        // the other subjects have to stay on screen, or the way back would be a
        // button that is no longer there.
        var digest = Digest(topics: Self.topics(of: all, scores: scores), scores: scores)
        let built = all.filter { topic.holds($0.topics) }

        // What is happening now is ordered by when, and by nothing else : a
        // reader who asked for less of a subject did not ask to hear about it
        // late.
        digest.live = built.filter(\.isLive).sorted { $0.lastAt > $1.lastAt }

        // The rest is ordered by what the reader asked for, then by weight.
        // The score comes first rather than being mixed into the weight : a
        // reader who says more of this expects more of this, not a story two
        // articles heavier than the one they asked for.
        digest.stories = built.filter { !$0.isLive }
            .sorted {
                let left = ($0.score(scores), $0.articleCount, $0.lastAt)
                let right = ($1.score(scores), $1.articleCount, $1.lastAt)
                return left > right
            }

        // The tail is what fell under no story at all, so it belongs to no
        // subject either, and it is shown on the front page only.
        digest.looseCount = topic == .frontPage ? loose : 0

        return digest
    }

    private static func story(
        _ story: Story,
        members: [StoryArticle],
        topics: [String],
        liveSince: Date
    ) -> DigestStory {
        let dates = members.map(\.date).sorted()
        let recent = members.filter { $0.date >= liveSince }

        // Several rooms in a few hours is an event. Ten articles from one room
        // is a single newsroom having a busy afternoon.
        let isLive = recent.count >= liveArticles && Set(recent.map(\.feedTitle)).count >= liveFeeds

        // In the order the rooms picked the story up, which is the order a
        // reader would tell it in.
        var marks: [FeedMark] = []
        for member in members.sorted(by: { $0.date < $1.date })
        where !marks.contains(where: { $0.title == member.feedTitle }) {
            marks.append(
                FeedMark(title: member.feedTitle, iconURL: member.feedIconURL, siteURL: member.feedSiteURL)
            )
        }

        return DigestStory(
            id: story.id,
            title: story.title,
            summary: story.summary,
            isGenerated: story.isGenerated,
            articleCount: members.count,
            feedMarks: Array(marks.prefix(namedFeeds)),
            feedCount: marks.count,
            firstAt: dates.first ?? story.firstAt,
            lastAt: dates.last ?? story.lastAt,
            arrivals: sparkline(dates),
            isLive: isLive,
            // The latest article to carry a picture, since a story is shown for
            // where it has got to rather than for where it started.
            imageURL: members.sorted { $0.date > $1.date }.lazy.compactMap(\.imageURL).first,
            topics: topics
        )
    }

    /// The subjects on a page : what the reader asked for first, then the one
    /// covering the most stories.
    ///
    /// Ties are broken by what moved last, so a page whose subjects are evenly
    /// matched still puts the live one first.
    static func topics(of stories: [DigestStory], scores: [String: Int] = [:]) -> [String] {
        var counts: [String: (stories: Int, lastAt: Date)] = [:]
        for story in stories {
            for topic in story.topics {
                let seen = counts[topic] ?? (stories: 0, lastAt: .distantPast)
                counts[topic] = (stories: seen.stories + 1, lastAt: max(seen.lastAt, story.lastAt))
            }
        }

        return
            counts
            .sorted {
                let left = (scores[$0.key] ?? 0, $0.value.stories, $0.value.lastAt)
                let right = (scores[$1.key] ?? 0, $1.value.stories, $1.value.lastAt)
                return left > right
            }
            .map(\.key)
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
