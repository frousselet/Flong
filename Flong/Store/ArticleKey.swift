//
//  ArticleKey.swift
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

/// What makes two articles the same article.
///
/// A paper that publishes a feed per desk puts the same piece in several of
/// them, and a reader following two desks was reading it twice : the same
/// headline, three minutes apart, filed under one story that then claimed three
/// articles when it had two.
///
/// **It is only ever the same newsroom's article.** Two papers covering one
/// event write two articles, and collapsing those would destroy the one thing
/// the digest is for : several rooms saying the same thing is the story. So the
/// key is scoped to the room, by the address the article lives at or, failing
/// that, by the room's own name.
nonisolated enum ArticleKey {
    /// Parameters that say who sent the reader, not what they are reading.
    ///
    /// A section feed and a newsletter feed hand out the same article with
    /// different campaign tags on it, and an address is not two addresses
    /// because a marketing department says so.
    static let tracking: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "fbclid", "gclid", "mc_cid", "mc_eid", "igshid",
        "at_medium", "at_campaign", "at_custom1", "at_custom2", "at_custom3", "at_custom4",
        "xtor", "ref_src", "ref_url", "spm",
    ]

    /// The key of an article, or `nil` when there is nothing stable to key it by.
    /// The first copy of an article, wherever it came from.
    ///
    /// Whatever feed, this one included. A feed that gives its articles a fresh
    /// identifier on every build hands the same piece over again and again, and
    /// the identifier is exactly what stops the ordinary path from noticing.
    /// The key notices.
    ///
    /// Never a duplicate itself, so a third copy points at the original rather
    /// than at the second.
    ///
    /// **Here rather than beside one of its two callers.** An article reaches
    /// the store two ways, from a publisher and from another of the reader's
    /// own devices, and a second copy of this rule would be a second chance for
    /// the two to disagree about what a duplicate is.
    static func original(of key: String, in db: Database) throws -> UUID? {
        try Entry
            .filter(Column("canonical_key") == key && Column("duplicate_of") == nil)
            .order(Column("received_at"))
            .fetchOne(db)?
            .id
    }

    static func of(url: URL?, title: String, publishedAt: Date?, room: String?) -> String? {
        if let address = address(url) { return address }
        return spelling(title, publishedAt: publishedAt, room: room)
    }

    /// The address, reduced to what identifies the page.
    ///
    /// The host without its `www`, the path without a trailing slash, and what
    /// is left of the query once the tracking is gone, in a fixed order. The
    /// fragment goes : `#comments` is a place on a page, not another page.
    static func address(_ url: URL?) -> String? {
        guard let url, let host = FeedURL.room(of: url) else { return nil }

        var path = url.path()
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let kept =
            (components?.queryItems ?? [])
            .filter { !tracking.contains($0.name.lowercased()) }
            .map { "\($0.name)=\($0.value ?? "")" }
            .sorted()

        let query = kept.isEmpty ? "" : "?" + kept.joined(separator: "&")
        return host + path.lowercased() + query
    }

    /// What an article is called, for a feed that gives no address at all.
    ///
    /// Scoped to the room and to the day : two papers writing the same headline
    /// on the same morning are two articles, and that they wrote the same
    /// headline is the story rather than a mistake.
    static func spelling(_ title: String, publishedAt: Date?, room: String?) -> String? {
        guard let room else { return nil }

        let folded =
            title
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !folded.isEmpty else { return nil }

        let day = publishedAt.map { Self.day.string(from: $0) } ?? "-"
        return "\(room)|\(day)|\(folded)"
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
