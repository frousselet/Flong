//
//  Story.swift
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

/// Several articles about the same thing.
///
/// The unit of the digest is the story, not the article. That is the whole
/// difference between a reader and a tool for watching a subject : a reader
/// shows what arrived, in the order it arrived ; this shows what is happening,
/// and how many rooms are talking about it.
nonisolated struct Story: Identifiable, Hashable, StoredRecord {
    static let databaseTableName = "story"

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case isGenerated = "is_generated"
        case briefLocked = "brief_locked"
        case briefLocale = "brief_locale"
        case topicsAskedAt = "topics_asked_at"
        case signature
        case articleCount = "article_count"
        case feedCount = "feed_count"
        case firstAt = "first_at"
        case lastAt = "last_at"
        case updatedAt = "updated_at"
    }

    var id: UUID
    /// What the story is called : written by the model, or taken from the
    /// article closest to the middle of the group.
    var title: String
    /// One line saying what happened.
    var summary: String?
    /// Whether a model wrote either of them, which the interface says out loud.
    var isGenerated: Bool
    /// Whether the reader has settled the matter themselves.
    var briefLocked: Bool

    /// The language the brief was written in, when a model wrote it.
    var briefLocale: String?

    /// When the model was last asked what this story is about.
    ///
    /// Asked once, whatever came of it. A story the model cannot file would
    /// otherwise be asked about at every opening, and, since the unfiled are
    /// taken newest first, it would sit at the head of the queue for ever and
    /// stop everything behind it from being asked at all.
    var topicsAskedAt: Date?

    /// The vocabulary its articles share, which is what a new article is
    /// compared against.
    var signature: TextSignature?

    var articleCount: Int
    var feedCount: Int
    var firstAt: Date
    var lastAt: Date
    var updatedAt: Date

    init(
        id: UUID = .v7(),
        title: String,
        summary: String? = nil,
        isGenerated: Bool = false,
        briefLocked: Bool = false,
        briefLocale: String? = nil,
        topicsAskedAt: Date? = nil,
        signature: TextSignature? = nil,
        articleCount: Int = 0,
        feedCount: Int = 0,
        firstAt: Date,
        lastAt: Date,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.isGenerated = isGenerated
        self.briefLocked = briefLocked
        self.briefLocale = briefLocale
        self.topicsAskedAt = topicsAskedAt
        self.signature = signature
        self.articleCount = articleCount
        self.feedCount = feedCount
        self.firstAt = firstAt
        self.lastAt = lastAt
        self.updatedAt = updatedAt
    }
}

nonisolated extension Story {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let lastAt = Column(CodingKeys.lastAt)
        static let articleCount = Column(CodingKeys.articleCount)
    }
}

/// One subject a story falls under.
///
/// Several rows per story : a story is rarely about one thing, and a reader
/// who asked for more of any of them meant this story.
nonisolated struct StoryTopic: Hashable, StoredRecord {
    static let databaseTableName = "story_topic"

    enum CodingKeys: String, CodingKey {
        case storyID = "story_id"
        case name
    }

    var storyID: UUID
    var name: String
}

/// One article's membership of a story.
nonisolated struct StoryMember: Hashable, StoredRecord {
    static let databaseTableName = "story_member"

    enum CodingKeys: String, CodingKey {
        case storyID = "story_id"
        case entryID = "entry_id"
        case similarity
    }

    var storyID: UUID
    var entryID: UUID
    /// How close the article was to the story when it joined, kept so the most
    /// central one can be found again without recomputing anything.
    var similarity: Double
}
