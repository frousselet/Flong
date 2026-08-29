//
//  OPMLImport.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// A feed of the file that could not be followed.
nonisolated struct SkippedFeed: Hashable, Sendable {
    let title: String
    let address: String
    let reason: FeedURLError
}

/// What an import did.
///
/// Nothing is reported as an error when a single line is unusable : a file of a
/// thousand feeds routinely holds two addresses nobody can make sense of, and
/// refusing the whole import over them would be useless. They are listed here
/// instead, and the reader decides whether to care.
nonisolated struct OPMLImportReport: Hashable, Sendable {
    var added = 0
    var alreadyFollowed = 0
    var skipped: [SkippedFeed] = []

    var total: Int { added + alreadyFollowed + skipped.count }
}

/// Reads an OPML file and follows what it holds.
nonisolated struct OPMLImport: Sendable {
    private let store: SubscriptionStore

    init(_ store: SubscriptionStore) {
        self.store = store
    }

    /// Follows every feed of an OPML file picked by the reader.
    ///
    /// The file is opened here rather than by the interface : this method is
    /// `nonisolated`, so reading the bytes and walking the XML happen off the
    /// main actor, where a file of a thousand feeds belongs.
    func callAsFunction(contentsOf url: URL) async throws -> OPMLImportReport {
        try await self(Self.read(url))
    }

    private static func read(_ url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        return try Data(contentsOf: url)
    }

    /// Follows every feed of an OPML file, in one transaction.
    ///
    /// The folder tree of the file is preserved. A feed already followed keeps
    /// the title and the folder it has, as `SubscriptionStore` documents : an
    /// import completes what is there and never overwrites it.
    func callAsFunction(_ data: Data) async throws -> OPMLImportReport {
        let document = try OPMLReader.read(data)

        var report = OPMLImportReport()
        var subscriptions: [Subscription] = []

        for feed in document.feeds {
            do {
                subscriptions.append(
                    try Subscription(
                        address: feed.address,
                        title: feed.title,
                        siteURL: feed.siteAddress.flatMap { try? FeedURL.canonical($0) },
                        folder: feed.folder
                    )
                )
            } catch {
                report.skipped.append(
                    SkippedFeed(title: feed.title, address: feed.address, reason: error)
                )
            }
        }

        for result in try await store.subscribe(to: subscriptions) {
            if result.isNew {
                report.added += 1
            } else {
                report.alreadyFollowed += 1
            }
        }

        return report
    }
}
