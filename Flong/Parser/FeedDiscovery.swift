//
//  FeedDiscovery.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Finds the feed a page belongs to.
///
/// A reader pastes the address of a site, not of its feed, which is the common
/// case section 8 of the specification asks to handle. The page states it in its
/// head ; when it does not, the usual locations are worth a try.
nonisolated enum FeedDiscovery {
    private static let feedTypes = [
        "application/rss+xml", "application/atom+xml", "application/feed+json",
        "application/json", "text/xml", "application/xml", "application/rdf+xml",
    ]

    /// The feeds a page declares, in the order it declares them.
    static func links(in html: String, relativeTo base: URL) -> [URL] {
        let document = HTMLDocument(html)
        var found: [URL] = []

        for link in document.elements(named: "link") {
            let relations = (link.attribute("rel") ?? "").lowercased().split(whereSeparator: \.isWhitespace)
            guard relations.contains("alternate") || relations.contains("feed") else { continue }

            let type = (link.attribute("type") ?? "").lowercased()
            guard relations.contains("feed") || feedTypes.contains(type) else { continue }

            guard let href = link.attribute("href"),
                let url = URL(string: href, relativeTo: base)?.absoluteURL,
                url.scheme?.hasPrefix("http") == true,
                !found.contains(url)
            else { continue }

            found.append(url)
        }

        return found
    }

    /// Where a feed sits when the page says nothing.
    ///
    /// Tried in order, and only after the page has been read : guessing is a
    /// fallback, never the first request.
    static let commonPaths = ["/feed", "/feed/", "/rss", "/rss.xml", "/atom.xml", "/feed.xml", "/index.xml"]

    static func candidates(under url: URL) -> [URL] {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        components.query = nil
        components.fragment = nil

        return commonPaths.compactMap { path in
            var candidate = components
            candidate.path = path
            return candidate.url
        }
    }
}
