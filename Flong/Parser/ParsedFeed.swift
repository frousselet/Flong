//
//  ParsedFeed.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The formats Flong reads.
nonisolated enum FeedFormat: String, Hashable, Sendable {
    case rss
    case atom
    case jsonFeed
    case hFeed
}

/// One article, as its feed states it.
///
/// Bodies are the markup the publisher served, untouched : sanitizing happens on
/// the way into the store, where the article address is known and can resolve
/// the relative links.
nonisolated struct ParsedItem: Hashable, Sendable {
    var guid: String?
    var url: URL?
    var title: String?
    var summaryHTML: String?
    var contentHTML: String?
    var author: String?
    var publishedAt: Date?
    var updatedAt: Date?
    var language: String?
    var enclosures: [Enclosure] = []

    /// What identifies the article for good.
    ///
    /// A GUID when the feed states one, and otherwise the link paired with the
    /// publication date, as section 4 of the specification requires. A feed that
    /// offers neither has nothing stable to offer, and its articles cannot be
    /// followed across refreshes.
    var identity: String? {
        if let guid, !guid.isEmpty { return guid }
        guard let url else { return nil }
        guard let publishedAt else { return url.absoluteString }
        return "\(url.absoluteString)#\(Int(publishedAt.timeIntervalSince1970))"
    }
}

/// A feed, as it was published.
nonisolated struct ParsedFeed: Hashable, Sendable {
    var format: FeedFormat
    var title: String?
    var siteURL: URL?
    var iconURL: URL?
    var language: String?
    var updatedAt: Date?
    var items: [ParsedItem] = []
}

/// Why a document could not be read as a feed.
nonisolated enum FeedParserError: Error, Hashable, Sendable {
    /// The bytes are neither XML nor JSON, even after the repair pass.
    case unreadable
    /// Readable, and not a feed : an HTML page, an error message, an image.
    case notAFeed
}
