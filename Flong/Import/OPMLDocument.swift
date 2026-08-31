//
//  OPMLDocument.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// One `outline` element, with the children nested under it.
///
/// The attributes are kept as they were read, addresses included : nothing here
/// canonicalizes anything, so the document stays a faithful picture of the file
/// and the import decides what to do with it.
nonisolated struct OPMLOutline: Hashable, Sendable {
    var text: String?
    var title: String?
    var xmlURL: String?
    var htmlURL: String?
    var type: String?
    var children: [OPMLOutline] = []

    /// What the outline is called. OPML 2.0 requires `text`, and exporters fill
    /// `title` as often, so whichever is there wins.
    var name: String? {
        for candidate in [title, text] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return nil
    }

    /// An outline is a feed when it carries an address, whatever its `type` says.
    ///
    /// Plenty of exporters write `type="rss"` on an Atom feed, or leave the
    /// attribute out entirely, so it is worth nothing as a signal.
    var isFeed: Bool { xmlURL?.isEmpty == false }
}

/// A feed read from an OPML file.
nonisolated struct OPMLFeed: Hashable, Sendable {
    var address: String
    var title: String
    var siteAddress: String?
}

/// The contents of an OPML file.
nonisolated struct OPMLDocument: Hashable, Sendable {
    var title: String?
    var outlines: [OPMLOutline] = []

    /// Every feed of the document, depth first, in the order the file lists them.
    ///
    /// **The nesting is walked and not kept.** An exported file files its feeds
    /// into folders, and Flong no longer has any : a source belongs to the
    /// publisher that serves it, which is worked out from its own address and
    /// needs nobody's filing. What the tree is still good for is finding the
    /// feeds at the bottom of it, so every level is descended and only the
    /// addresses come back.
    var feeds: [OPMLFeed] {
        var feeds: [OPMLFeed] = []
        collect(outlines, into: &feeds)
        return feeds
    }

    private func collect(_ outlines: [OPMLOutline], into feeds: inout [OPMLFeed]) {
        for outline in outlines {
            if outline.isFeed, let address = outline.xmlURL {
                feeds.append(
                    OPMLFeed(
                        address: address,
                        title: outline.name ?? "",
                        siteAddress: outline.htmlURL
                    )
                )
            }

            guard !outline.children.isEmpty else { continue }
            collect(outline.children, into: &feeds)
        }
    }
}
