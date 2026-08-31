//
//  Subscription.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// A feed someone asks Flong to follow.
///
/// This is what an OPML file, a pasted address or the share extension produces,
/// before the store knows whether it is already following it. Its URL is
/// canonical by construction, so nothing further down has to remember to make
/// it so.
nonisolated struct Subscription: Hashable, Sendable {
    /// The canonical feed URL, which is what identifies the feed.
    let url: URL
    /// The title to show. Never empty : it falls back to the host.
    var title: String
    var siteURL: URL?
    var iconURL: URL?

    init(
        url: URL,
        title: String = "",
        siteURL: URL? = nil,
        iconURL: URL? = nil
    ) throws(FeedURLError) {
        try self.init(address: url.absoluteString, title: title, siteURL: siteURL, iconURL: iconURL)
    }

    init(
        address: String,
        title: String = "",
        siteURL: URL? = nil,
        iconURL: URL? = nil
    ) throws(FeedURLError) {
        let url = try FeedURL.canonical(address)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        self.url = url
        self.title = title.isEmpty ? Subscription.fallbackTitle(for: url) : title
        self.siteURL = siteURL
        self.iconURL = iconURL
    }

    /// What a feed is called when its source names it nothing.
    ///
    /// The host is the least surprising answer, and the parser replaces it as
    /// soon as the feed itself states a title.
    static func fallbackTitle(for url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
