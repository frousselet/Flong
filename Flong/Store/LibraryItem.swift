//
//  LibraryItem.swift
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

/// An article the reader chose to keep.
///
/// Everything an article needs to be read again is copied here at the moment of
/// promotion : its text, its title, its author, and the name and address of the
/// feed it came from. Nothing points at the stream row for its content, because
/// that row is a cache and will be purged, and the feed itself may be gone in a
/// year. A library item that needed either of them would be a library item that
/// stops working.
nonisolated struct LibraryItem: Identifiable, Hashable, StoredRecord {
    static let databaseTableName = "library_item"

    enum CodingKeys: String, CodingKey {
        case id
        case entryID = "entry_id"
        case feedURL = "feed_url"
        case feedTitle = "feed_title"
        case guid
        case url
        case title
        case author
        case language
        case publishedAt = "published_at"
        case promotedAt = "promoted_at"
        case contentHTML = "content_html"
        case plainText = "plain_text"
        case annotation
        case vector
        case vectorModel = "vector_model"
        case vectorRevision = "vector_revision"
    }

    var id: UUID
    /// The stream article this was kept from, until that article is purged.
    var entryID: UUID?

    var feedURL: URL?
    var feedTitle: String?
    var guid: String
    var url: URL?
    var title: String
    var author: String?
    var language: String?
    var publishedAt: Date?
    var promotedAt: Date

    /// The article as it read on the day it was kept.
    var contentHTML: String?
    var plainText: String?
    /// What the reader wrote about it.
    var annotation: String?

    /// The vector and the model that produced it, both arriving with M4.
    var vector: Data?
    var vectorModel: String?
    var vectorRevision: String?

    init(
        id: UUID = .v7(),
        entryID: UUID? = nil,
        feedURL: URL? = nil,
        feedTitle: String? = nil,
        guid: String,
        url: URL? = nil,
        title: String,
        author: String? = nil,
        language: String? = nil,
        publishedAt: Date? = nil,
        promotedAt: Date = Date(),
        contentHTML: String? = nil,
        plainText: String? = nil,
        annotation: String? = nil
    ) {
        self.id = id
        self.entryID = entryID
        self.feedURL = feedURL
        self.feedTitle = feedTitle
        self.guid = guid
        self.url = url
        self.title = title
        self.author = author
        self.language = language
        self.publishedAt = publishedAt
        self.promotedAt = promotedAt
        self.contentHTML = contentHTML
        self.plainText = plainText
        self.annotation = annotation
    }

    /// The date a list sorts on : when the article was published, or failing
    /// that when it was kept.
    var date: Date { publishedAt ?? promotedAt }
}

nonisolated extension LibraryItem {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let entryID = Column(CodingKeys.entryID)
        static let guid = Column(CodingKeys.guid)
        static let feedURL = Column(CodingKeys.feedURL)
        static let annotation = Column(CodingKeys.annotation)
    }
}
