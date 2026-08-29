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

/// An article of the stream.
///
/// The stream is a cache : an entry is purged by age and by volume, and what the
/// user keeps lives in the library instead.
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
        imageURL: URL? = nil
    ) {
        self.id = id
        self.feedID = feedID
        self.guid = guid
        self.url = url
        self.title = title
        self.excerpt = excerpt
        self.author = author
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
    }

    /// The date the article is sorted on : when it was published, or when it
    /// reached this device for a feed that dates nothing.
    var sortDate: Date { publishedAt ?? receivedAt }
}

nonisolated extension Entry {
    static let feed = belongsTo(Feed.self)
    static let body = hasOne(EntryBody.self)
}
