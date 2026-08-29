//
//  FeedFinder.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Why an address did not turn into a feed.
nonisolated enum FeedFinderError: Error, Hashable, Sendable {
    case invalidAddress(FeedURLError)
    case unreachable
    case noFeedFound
}

/// What was found at an address.
nonisolated struct FoundFeed: Hashable, Sendable {
    let url: URL
    let title: String?
    let siteURL: URL?
    let iconURL: URL?
}

/// Turns whatever a reader pasted into a feed.
///
/// Readers paste the address of a site far more often than the address of its
/// feed, which is the case section 8 of the specification asks to handle. The
/// page is read first, the usual locations only afterwards : guessing is a
/// fallback, never the opening move.
nonisolated struct FeedFinder: Sendable {
    private let fetcher: FeedFetcher

    init(fetcher: FeedFetcher = FeedFetcher()) {
        self.fetcher = fetcher
    }

    func find(at address: String) async throws -> FoundFeed {
        let url: URL
        do {
            url = try FeedURL.canonical(address)
        } catch {
            throw FeedFinderError.invalidAddress(error)
        }

        guard case .updated(let document) = await fetcher.fetch(FetchRequest(url: url)) else {
            throw FeedFinderError.unreachable
        }

        if let parsed = try? FeedParser.parse(document.data, url: document.url, contentType: document.contentType) {
            return found(parsed, at: document.url)
        }

        // Not a feed, so the page is asked where its feed is, and failing that
        // the usual locations are tried in order.
        let html = String(decoding: document.data, as: UTF8.self)
        let declared = FeedDiscovery.links(in: html, relativeTo: document.url)

        for candidate in declared + FeedDiscovery.candidates(under: document.url) where candidate != document.url {
            guard case .updated(let candidateDocument) = await fetcher.fetch(FetchRequest(url: candidate)) else {
                continue
            }
            guard
                let parsed = try? FeedParser.parse(
                    candidateDocument.data,
                    url: candidateDocument.url,
                    contentType: candidateDocument.contentType
                )
            else { continue }

            return found(parsed, at: candidateDocument.url)
        }

        throw FeedFinderError.noFeedFound
    }

    private func found(_ parsed: ParsedFeed, at url: URL) -> FoundFeed {
        FoundFeed(url: url, title: parsed.title, siteURL: parsed.siteURL, iconURL: parsed.iconURL)
    }
}
