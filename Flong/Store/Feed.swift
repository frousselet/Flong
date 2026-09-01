//
//  Feed.swift
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

/// A source of articles, identified by its canonical URL.
nonisolated struct Feed: Identifiable, Hashable, StoredRecord {
    static let databaseTableName = "feed"

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case previousURL = "previous_url"
        case siteURL = "site_url"
        case iconURL = "icon_url"
        case title
        case language
        case etag
        case lastModified = "last_modified"
        case fetchCount = "fetch_count"
        case notModifiedCount = "not_modified_count"
        case failureCount = "failure_count"
        case lastFailureReason = "last_failure_reason"
        case lastFetchAt = "last_fetch_at"
        case lastSuccessAt = "last_success_at"
        case quarantinedAt = "quarantined_at"
        case observedInterval = "observed_interval"
        case refreshInterval = "refresh_interval"
        case readerModeEnabled = "reader_mode_enabled"
        case loadsImages = "loads_images"
        case isFavourite = "is_favourite"
        case createdAt = "created_at"
    }

    var id: UUID
    var url: URL

    /// Where this source was served before the reader moved it, when they have.
    ///
    /// **It is kept so that the move can travel.** Every record about a source
    /// is named after its address, so a source that moves is a new record and a
    /// deletion of the old one, and a device reading those two as a removal
    /// followed by a subscription would take the articles of the old row with
    /// it. The record carries this, and a device that has the source at this
    /// address moves it rather than building a second one.
    ///
    /// Never cleared, since the device that needs it is the one that has been
    /// switched off, and never a secret : the address stored for a private feed
    /// is already the masked one.
    var previousURL: URL?
    var siteURL: URL?
    var iconURL: URL?
    var title: String
    var language: String?

    /// Conditional request state, replayed on the next fetch.
    var etag: String?
    var lastModified: String?

    var fetchCount: Int
    var notModifiedCount: Int
    var failureCount: Int
    var lastFailureReason: String?
    var lastFetchAt: Date?
    var lastSuccessAt: Date?
    var quarantinedAt: Date?

    /// The median publication gap observed on this feed, in seconds.
    var observedInterval: TimeInterval?
    /// A manual refresh interval, in seconds, which wins over the observed one.
    var refreshInterval: TimeInterval?

    var readerModeEnabled: Bool
    var loadsImages: Bool

    /// Whether the reader singled this source out.
    ///
    /// It says nothing about the articles underneath : a source in the
    /// favourites is a publisher the reader wants near the top of their own
    /// list, and starring an article stays a judgement about that article. The
    /// two are deliberately unconnected, and ``ArticleCollection`` keeps a
    /// square for each so neither is mistaken for the other.
    var isFavourite: Bool
    var createdAt: Date

    init(
        id: UUID = .v7(),
        url: URL,
        previousURL: URL? = nil,
        siteURL: URL? = nil,
        iconURL: URL? = nil,
        title: String,
        language: String? = nil,
        etag: String? = nil,
        lastModified: String? = nil,
        fetchCount: Int = 0,
        notModifiedCount: Int = 0,
        failureCount: Int = 0,
        lastFailureReason: String? = nil,
        lastFetchAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        quarantinedAt: Date? = nil,
        observedInterval: TimeInterval? = nil,
        refreshInterval: TimeInterval? = nil,
        readerModeEnabled: Bool = false,
        loadsImages: Bool = true,
        isFavourite: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.previousURL = previousURL
        self.siteURL = siteURL
        self.iconURL = iconURL
        self.title = title
        self.language = language
        self.etag = etag
        self.lastModified = lastModified
        self.fetchCount = fetchCount
        self.notModifiedCount = notModifiedCount
        self.failureCount = failureCount
        self.lastFailureReason = lastFailureReason
        self.lastFetchAt = lastFetchAt
        self.lastSuccessAt = lastSuccessAt
        self.quarantinedAt = quarantinedAt
        self.observedInterval = observedInterval
        self.refreshInterval = refreshInterval
        self.readerModeEnabled = readerModeEnabled
        self.loadsImages = loadsImages
        self.isFavourite = isFavourite
        self.createdAt = createdAt
    }

    /// The publisher this source belongs to, which is what the sources list
    /// groups by.
    ///
    /// The host of the site, or of the feed when the site is unknown : the
    /// same value ``FeedURL/room(of:)`` computes for the digest, and for the
    /// same reason. A paper that publishes a feed per desk is one publisher,
    /// not six, whether the question is asked by a front page counting who is
    /// covering a story or by a list deciding which rows belong together.
    var domain: String {
        FeedURL.publisher(site: siteURL, feed: url) ?? url.absoluteString
    }

    /// The share of fetches the server answered with a 304, the health indicator
    /// of section 8 of the specification. `nil` until the feed has been fetched.
    var notModifiedRate: Double? {
        guard fetchCount > 0 else { return nil }
        return Double(notModifiedCount) / Double(fetchCount)
    }
}

nonisolated extension Feed {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let url = Column(CodingKeys.url)
        static let title = Column(CodingKeys.title)
        static let isFavourite = Column(CodingKeys.isFavourite)
    }
}

nonisolated extension DerivableRequest<Feed> {
    /// Feeds in the order a list shows them, sorted the way the reader's locale sorts.
    func orderedByTitle() -> Self {
        order(Feed.Columns.title.collating(.localizedStandardCompare))
    }
}
