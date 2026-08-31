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
    /// The newsroom it belongs to, which is its host rather than its feed : a
    /// paper with a feed per desk is one room, however many feeds are followed.
    let room: String
    let iconURL: URL?
    let siteURL: URL?

    var id: String { room }
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
    /// the collections and search. Three days is a story still worth a headline.
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
        let preferences = TopicPreferences(database)
        let scores = try await preferences.scores()
        let own = try await preferences.ownNames()

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
                    WHERE e.duplicate_of IS NULL AND COALESCE(e.published_at, e.received_at) >= ?
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
                        WHERE m.entry_id IS NULL AND e.is_hidden = 0 AND e.duplicate_of IS NULL
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
        var digest = Digest(
            topics: Self.topics(of: all, scores: scores, own: own),
            scores: scores
        )
        let built = all.filter { topic.holds($0.topics) }

        // What is happening now is ordered by when, and by nothing else : a
        // reader who asked for less of a subject did not ask to hear about it
        // late.
        digest.live = built.filter(\.isLive).sorted { $0.lastAt > $1.lastAt }

        // The rest is ordered by what the reader asked for, then by when, then
        // by weight.
        //
        // The score comes first rather than being mixed into the weight : a
        // reader who says more of this expects more of this, not a story two
        // articles heavier than the one they asked for.
        //
        // **Then when, and not how heavy.** Weight came second, and a reader
        // who has said nothing about anything, which is every reader on their
        // first days, had a page ordered by article count alone. A story that
        // ran all week outweighs anything that opened overnight and outweighs
        // it more every day, so the top of the page was the same top of the
        // page every morning however much had arrived : a front page that says
        // nothing has happened is a front page nobody believes. A newspaper
        // orders the day's news by the day.
        digest.stories = built.filter { !$0.isLive }
            .sorted {
                let left = ($0.score(scores), $0.lastAt, $0.articleCount)
                let right = ($1.score(scores), $1.lastAt, $1.articleCount)
                return left > right
            }

        // The tail is what fell under no story at all, so it belongs to no
        // subject either, and it is shown on the front page only.
        digest.looseCount = topic == .frontPage ? loose : 0

        return digest
    }

    /// How many stories the page is looking at.
    ///
    /// What the model's own work is measured against before there is anything
    /// better to measure it with. The stories waiting for a headline cannot be
    /// counted until the feeds have been fetched and what they brought has been
    /// grouped, and taking that count at the start of a pass answers nought :
    /// the stage is then worth nothing, and the bar reaches the end of its rail
    /// while the pass is a third done. The stories already on the page are the
    /// right order of magnitude for the ones that are about to be.
    func storyCount(now: Date = Date()) async throws -> Int {
        let since = now.addingTimeInterval(-Self.window)

        return try await database.writer.read { db in
            try Story.filter(Story.Columns.lastAt >= since).fetchCount(db)
        }
    }

    /// A story that has just been opened, as a notification needs it.
    nonisolated struct Opened: Hashable, Sendable, Identifiable {
        let id: UUID
        /// What the story is called : written by the model when there is one,
        /// and otherwise the headline of the article nearest the middle of the
        /// group.
        let title: String
        /// The one line saying what happened, when the model wrote one.
        let summary: String?
        /// The newsrooms covering it, in the order they picked it up.
        let rooms: [String]
    }

    /// The stories opened since a moment, oldest first.
    ///
    /// **Asked of the primary key.** A story identifier is a UUIDv7, so it
    /// carries the moment the story was opened and sorts by it : the question
    /// is a range on the key, not a scan with a timestamp unpacked per row.
    /// Nothing else records when a story was opened, `first_at` being the date
    /// of its earliest article, which may be days older than the story.
    func opened(since moment: Date, limit: Int = 20, now: Date = Date()) async throws -> [Opened] {
        let since = now.addingTimeInterval(-Self.window)

        return try await database.writer.read { db in
            let stories =
                try Story
                .filter(Column("id") > UUID.v7Floor(at: moment))
                // Only what the reader will actually find on the page.
                //
                // **The two used to ask different questions.** This asked the
                // primary key and nothing else, while ``digest(_:now:limit:)``
                // also holds a story to the window and to having more than one
                // article left inside it. A pass that grouped a quiet feed's
                // backlog into stories dated last week announced every one of
                // them and put none of them on the page, and the reader was
                // told about news they then could not find : a notification
                // about a page that had, as far as they could see, not changed
                // at all.
                .filter(Story.Columns.lastAt >= since)
                .order(Column("id"))
                .limit(limit)
                .fetchAll(db)
            guard !stories.isEmpty else { return [] }

            let ids = stories.map(\.id)
            let members = try Row.fetchAll(
                db,
                sql: """
                    SELECT m.story_id AS story_id, f.title AS feed_title,
                           COALESCE(f.site_url, f.url) AS site_url,
                           COALESCE(e.published_at, e.received_at) AS date
                    FROM story_member m
                    JOIN entry e ON e.id = m.entry_id
                    JOIN feed f ON f.id = e.feed_id
                    WHERE m.story_id IN (\(databaseQuestionMarks(count: ids.count)))
                      AND e.duplicate_of IS NULL
                      AND COALESCE(e.published_at, e.received_at) >= ?
                    ORDER BY date
                    """,
                arguments: StatementArguments(ids) + [since]
            )

            var rooms: [UUID: [String]] = [:]
            var counts: [UUID: Int] = [:]
            for row in members {
                let site = (row["site_url"] as String?).flatMap(URL.init(string:))
                let room = FeedURL.room(of: site) ?? (row["feed_title"] as String)
                let id = row["story_id"] as UUID
                counts[id, default: 0] += 1
                guard !(rooms[id] ?? []).contains(room) else { continue }
                rooms[id, default: []].append(room)
            }

            // The page shows nothing a single article stands behind, so
            // neither does a notification about the page.
            return
                stories
                .filter { (counts[$0.id] ?? 0) > 1 }
                .map {
                    Opened(id: $0.id, title: $0.title, summary: $0.summary, rooms: rooms[$0.id] ?? [])
                }
        }
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
        // is a single newsroom having a busy afternoon, and a paper running a
        // story in three of its sections is still one paper.
        let isLive = recent.count >= liveArticles && Set(recent.map(Self.room)).count >= liveFeeds

        // In the order the rooms picked the story up, which is the order a
        // reader would tell it in. One mark per room, not per feed.
        var marks: [FeedMark] = []
        for member in members.sorted(by: { $0.date < $1.date }) {
            let room = Self.room(of: member)
            guard !marks.contains(where: { $0.room == room }) else { continue }
            marks.append(
                FeedMark(
                    title: member.feedTitle,
                    room: room,
                    iconURL: member.feedIconURL,
                    siteURL: member.feedSiteURL
                )
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

    /// The newsroom an article came from, or its feed when it has no address
    /// worth reading a host out of.
    private static func room(of member: StoryArticle) -> String {
        FeedURL.room(of: member.feedSiteURL) ?? member.feedTitle
    }

    /// The subjects on a page : what the reader asked for first, then the one
    /// covering the most stories, and the reader's own subjects whether they
    /// cover anything yet or not.
    ///
    /// Ties are broken by what moved last, so a page whose subjects are evenly
    /// matched still puts the live one first.
    static func topics(
        of stories: [DigestStory],
        scores: [String: Int] = [:],
        own: [String] = []
    ) -> [String] {
        var counts: [String: (stories: Int, lastAt: Date)] = [:]
        for story in stories {
            for topic in story.topics {
                let seen = counts[topic] ?? (stories: 0, lastAt: .distantPast)
                counts[topic] = (stories: seen.stories + 1, lastAt: max(seen.lastAt, story.lastAt))
            }
        }

        // A subject the reader wrote is on the page whether anything has been
        // filed under it yet or not. One the model found is only there when it
        // holds something : it was never asked for.
        for name in own where counts[name] == nil {
            counts[name] = (stories: 0, lastAt: .distantPast)
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
