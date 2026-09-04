//
//  Entry.swift
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

/// A media file served alongside an article.
nonisolated struct Enclosure: Hashable, Codable, Sendable {
    var url: URL
    var type: String?
    var length: Int?
}

/// An article.
///
/// There is one of these per article and no second copy anywhere : what the
/// reader says about one - starred, written on, filed - is written on the row
/// itself, and that is what keeps it from ever being purged.
nonisolated struct Entry: Identifiable, Hashable, StoredRecord {
    static let databaseTableName = "entry"

    enum CodingKeys: String, CodingKey {
        case id
        case feedID = "feed_id"
        case guid
        case url
        case title
        case excerpt
        case author
        case language
        case publishedAt = "published_at"
        case updatedAt = "updated_at"
        case receivedAt = "received_at"
        case isRead = "is_read"
        case readAt = "read_at"
        case isStarred = "is_starred"
        case isHidden = "is_hidden"
        case enclosures
        case hasMedia = "has_media"
        case imageURL = "image_url"
        case canonicalKey = "canonical_key"
        case annotation
        case vector
        case vectorModel = "vector_model"
        case vectorRevision = "vector_revision"
        case duplicateOf = "duplicate_of"
        case newsmakersAt = "newsmakers_at"
        case announcedAt = "announced_at"
    }

    var id: UUID
    var feedID: UUID

    /// The identity the feed gives the article : its GUID, or the link and the
    /// publication date when it serves none. Unique within a feed.
    var guid: String

    var url: URL?
    var title: String
    var excerpt: String?
    var author: String?
    var language: String?
    var publishedAt: Date?
    var updatedAt: Date?
    var receivedAt: Date

    var isRead: Bool
    var readAt: Date?
    var isStarred: Bool
    var isHidden: Bool

    var enclosures: [Enclosure]?
    var hasMedia: Bool

    /// The picture that stands for the article, wherever `CoverImage` found it.
    /// Only its address is kept : the file itself is the publisher's, and is
    /// asked for when a screen actually shows it.
    var imageURL: URL?

    /// What makes this the same article as another : see ``ArticleKey``.
    var canonicalKey: String?

    /// What the reader wrote on it, which is one of the two things that puts an
    /// article in a collection every reader has.
    var annotation: String?

    /// What it means, for the search that goes by meaning rather than by words.
    ///
    /// A vector only compares to vectors of the same model and revision, so
    /// both travel with it and a mismatch means computing it again.
    var vector: Data?
    var vectorModel: String?
    var vectorRevision: String?

    /// The copy that arrived first, when this one is the same article reaching
    /// the reader through a second feed of the same newsroom. A duplicate is
    /// kept and shown nowhere.
    var duplicateOf: UUID?

    /// When the people this article names were read out of it, or `nil` where
    /// they have not been.
    ///
    /// **The date is the answer, and no rows is not.** Reading who an article
    /// is about is a model over the whole of its text, so it happens in a
    /// resumable job rather than in the write that stores the article, and the
    /// job has to be able to tell an article it has never read from one it read
    /// and found nobody in. See ``Newsmaker`` and ``NewsmakerStore``.
    ///
    /// It is set back to `nil` when a publisher rewrites the piece, which is
    /// what makes the people follow the prose.
    var newsmakersAt: Date?

    /// When the reader was told about this article, or `nil` where they have
    /// not been and may still be.
    ///
    /// **Per article, because a notice is per article.** It was a watermark on
    /// the device, which is the right shape for one sentence about everything
    /// that arrived and the wrong one for one sentence apiece : the read behind
    /// it is bounded at two hundred against absurdity, and a mark moved past
    /// what the bound left behind loses the rest for good.
    ///
    /// It is stamped whether a notice was posted or not. A reader looking at
    /// the page an article lands on has seen it, and being told tomorrow about
    /// what they read today is worse than not being told ; what this records is
    /// that the article reached them and not that a notification went out.
    ///
    /// And it is stamped on the way in for everything that is a backlog rather
    /// than news : an import, and the first fetch of a feed nobody has fetched
    /// before. Both of those are a reader receiving a history, and a history is
    /// not something to be interrupted about a thousand times.
    var announcedAt: Date?

    init(
        id: UUID = .v7(),
        feedID: UUID,
        guid: String,
        url: URL? = nil,
        title: String,
        excerpt: String? = nil,
        author: String? = nil,
        language: String? = nil,
        publishedAt: Date? = nil,
        updatedAt: Date? = nil,
        receivedAt: Date = Date(),
        isRead: Bool = false,
        readAt: Date? = nil,
        isStarred: Bool = false,
        isHidden: Bool = false,
        enclosures: [Enclosure]? = nil,
        imageURL: URL? = nil,
        canonicalKey: String? = nil,
        duplicateOf: UUID? = nil
    ) {
        self.id = id
        self.feedID = feedID
        self.guid = guid
        self.url = url
        self.title = title
        self.excerpt = excerpt
        // Normalized once, here, so every later question about a byline is
        // an exact comparison the index can answer : see ``Author``.
        self.author = Author.name(from: author)
        self.language = language
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
        self.receivedAt = receivedAt
        self.isRead = isRead
        self.readAt = readAt
        self.isStarred = isStarred
        self.isHidden = isHidden
        self.enclosures = enclosures
        self.hasMedia = !(enclosures ?? []).isEmpty
        self.imageURL = imageURL
        self.canonicalKey = canonicalKey
        self.duplicateOf = duplicateOf
    }

    /// The date the article is sorted on : when it was published, or when it
    /// reached this device for a feed that dates nothing.
    var sortDate: Date { publishedAt ?? receivedAt }
}

nonisolated extension Entry {
    static let feed = belongsTo(Feed.self)
    static let body = hasOne(EntryBody.self)
}
