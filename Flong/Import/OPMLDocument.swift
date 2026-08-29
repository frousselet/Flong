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
    var category: String?
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

/// A feed read from an OPML file, with the folder its nesting puts it in.
nonisolated struct OPMLFeed: Hashable, Sendable {
    var address: String
    var title: String
    var siteAddress: String?
    var folder: String?
}

/// The contents of an OPML file.
nonisolated struct OPMLDocument: Hashable, Sendable {
    var title: String?
    var outlines: [OPMLOutline] = []

    /// Every feed of the document, depth first, in the order the file lists them.
    ///
    /// The folder comes from the outlines a feed is nested under. When nothing
    /// nests it, a `category` attribute is used instead : OPML 2.0 states it as
    /// a comma separated list of slash delimited paths, and it is how several
    /// services export a flat file.
    var feeds: [OPMLFeed] {
        var feeds: [OPMLFeed] = []
        collect(outlines, folder: [], into: &feeds)
        return feeds
    }

    private func collect(_ outlines: [OPMLOutline], folder: [String], into feeds: inout [OPMLFeed]) {
        for outline in outlines {
            if outline.isFeed, let address = outline.xmlURL {
                feeds.append(
                    OPMLFeed(
                        address: address,
                        title: outline.name ?? "",
                        siteAddress: outline.htmlURL,
                        folder: folder.isEmpty
                            ? OPMLDocument.folder(fromCategory: outline.category)
                            : folder.joined(separator: String(FolderPath.separator))
                    )
                )
            }

            guard !outline.children.isEmpty else { continue }
            let nested = outline.name.map { folder + [$0] } ?? folder
            collect(outline.children, folder: nested, into: &feeds)
        }
    }

    private static func folder(fromCategory category: String?) -> String? {
        guard let first = category?.split(separator: ",").first else { return nil }
        return FolderPath.normalized(String(first))
    }
}
