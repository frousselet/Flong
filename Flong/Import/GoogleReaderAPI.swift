//
//  GoogleReaderAPI.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// What a Google Reader compatible service calls the things it holds.
///
/// FreshRSS serves this API, and so do Miniflux, Inoreader, The Old Reader and
/// BazQux, which is why the whole surface is named after the dead service they
/// all copied rather than after any one of them.
///
/// `docs/technical/freshrss-api.md` is the reference for every shape below. It
/// was read off the FreshRSS implementation itself, since Google never
/// published a specification and there is none to appeal to.
nonisolated enum GoogleReader {
    /// The path everything hangs off, under the address of the instance.
    static let endpoint = "api/greader.php"

    /// Everything the service holds, which is what a history import walks.
    static let readingList = "user/-/state/com.google/reading-list"
    /// The state an article wears once it has been read.
    static let read = "user/-/state/com.google/read"
    /// The state an article wears once the reader has kept it.
    static let starred = "user/-/state/com.google/starred"

    /// The stream one subscription is served under.
    ///
    /// The numeric form, which is the only one `stream/contents` routes and the
    /// only one `mark-all-as-read` accepts. The feed's own address travels
    /// separately, in the `url` field of `subscription/list`.
    static func stream(ofSubscription id: String) -> String { id }

    /// Where the API lives, from whatever the reader typed.
    ///
    /// A reader pastes what their browser is showing, and that is almost never
    /// the API's own address : FreshRSS puts its interface at `…/p/i/` and its
    /// API at `…/p/api/greader.php`, so the two differ by the last component of
    /// a path nobody looks at. Every spelling below reaches the same place.
    ///
    /// ```
    /// rss.example.com                        → https://rss.example.com/api/greader.php
    /// https://rss.example.com/i/             → https://rss.example.com/api/greader.php
    /// https://rss.example.com/api/greader.php → unchanged
    /// https://example.com/FreshRSS/p/        → https://example.com/FreshRSS/p/api/greader.php
    /// ```
    ///
    /// **The scheme is added and never assumed away.** An address typed without
    /// one is asked for over TLS, which is what every instance worth signing in
    /// to serves, and an address typed with `http` is left as it was typed :
    /// somebody running FreshRSS on their own network knows what they wrote.
    static func base(of address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let spelled = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard var components = URLComponents(string: spelled), let host = components.host, !host.isEmpty else {
            return nil
        }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }

        var path = components.path.split(separator: "/").map(String.init)
        // The interface's own address, reduced to the installation it belongs
        // to : a script name first, then the API directory, then the `i` the
        // web interface is served under. Nothing else is dropped, because
        // nothing else is guessable : `/FreshRSS/p/` is where somebody chose to
        // install it and is part of every address the instance answers.
        if path.last?.hasSuffix(".php") == true { path.removeLast() }
        if path.last == "api" { path.removeLast() }
        if path.last == "i" { path.removeLast() }

        components.path = "/" + (path + [endpoint]).joined(separator: "/")
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }
}

/// Why the service would not answer.
///
/// **A refusal and an outage are different things**, and the reader can only act
/// on one of them : a name and a password they can correct, a server that is
/// down they can only come back to. Everything the API can go wrong by is
/// sorted into one of the two before it reaches a screen.
nonisolated enum ServiceError: Error, Hashable, Sendable {
    /// What was typed is not an address there is any point asking.
    case badAddress
    /// The name or the API password is wrong. 400 and 401 both mean this : the
    /// server distinguishes an unknown account from a bad password, and telling
    /// the two apart on screen is telling somebody which half they got right.
    case rejected
    /// The network did not carry the request.
    case unreachable
    /// The server answered something, and it was not a yes.
    case refused(Int)
    /// The answer is not what the API says it is.
    case unreadable
}

// MARK: - What the service answers

/// The reply to `subscription/list`.
nonisolated struct GoogleReaderSubscriptionList: Decodable, Hashable, Sendable {
    var subscriptions: [GoogleReaderSubscription] = []
}

/// One subscription of the account.
nonisolated struct GoogleReaderSubscription: Decodable, Hashable, Sendable, Identifiable {
    /// The stream it is served under, `feed/<numeric id>`.
    var id: String
    var title: String?
    /// The feed document, which is the address Flong follows it at.
    var url: String?
    /// The site it belongs to.
    var htmlUrl: String?
    var iconUrl: String?
}

/// One page of `stream/contents`.
nonisolated struct GoogleReaderPage: Decodable, Hashable, Sendable {
    var items: [GoogleReaderItem] = []
    /// Where the next page starts, and **absent at the end of the stream** :
    /// the server sends it only when the page it just sent was filled.
    var continuation: String?
}

/// A number a server may have written as a string.
///
/// FreshRSS writes `published` as a number and `timestampUsec` as a string, and
/// the other services serving this API do not always agree with it. A decoder
/// that insisted on one shape would throw away a page of two hundred articles
/// over a field two of them spelled differently.
nonisolated struct LooseNumber: Decodable, Hashable, Sendable {
    var value: Double?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text)
        } else {
            value = nil
        }
    }

    var date: Date? {
        guard let value, value.isFinite else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    /// The same number as a size, where it is one a file could have.
    var bytes: Int? {
        guard let value, value.isFinite, value >= 0, value < Double(Int.max) else { return nil }
        return Int(value)
    }
}

/// One article, as the service serializes it.
nonisolated struct GoogleReaderItem: Decodable, Hashable, Sendable {
    nonisolated struct Content: Decodable, Hashable, Sendable {
        var content: String?
    }

    nonisolated struct Link: Decodable, Hashable, Sendable {
        var href: String?
    }

    nonisolated struct Origin: Decodable, Hashable, Sendable {
        /// `feed/<numeric id>`, matching `subscription/list`.
        var streamId: String?
        var title: String?
        var htmlUrl: String?
    }

    nonisolated struct Attachment: Decodable, Hashable, Sendable {
        var href: String?
        var type: String?
        var length: LooseNumber?
    }

    /// The long form, `tag:google.com,2005:reader/item/<16 hex digits>`.
    var id: String
    var title: String?
    var author: String?
    var published: LooseNumber?
    var updated: LooseNumber?
    /// The body, where the server does not serialize in compatibility mode.
    var content: Content?
    /// The body, where it does, which is what FreshRSS always does.
    var summary: Content?
    var canonical: [Link]?
    var alternate: [Link]?
    var origin: Origin?
    /// The states and the labels, which is the only place read and starred are
    /// said. There is no boolean anywhere in this API.
    var categories: [String]?
    var enclosure: [Attachment]?

    /// Where the article lives.
    var link: URL? {
        for candidate in (canonical ?? []) + (alternate ?? []) {
            guard let href = candidate.href, let url = URL(string: href), HTTPURL.isFetchable(url) else { continue }
            return url
        }
        return nil
    }

    /// The body, reading `content` first so a server that is not in
    /// compatibility mode is not made to look empty.
    var bodyHTML: String? {
        for candidate in [content?.content, summary?.content] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return nil
    }

    var isRead: Bool { categories?.contains(GoogleReader.read) ?? false }
    var isStarred: Bool { categories?.contains(GoogleReader.starred) ?? false }

    var publishedAt: Date? { published?.date }

    /// An update, only where the server states one later than the publication.
    ///
    /// FreshRSS comments `updated` out and never sends it, so this is for the
    /// other services serving the same API. The minute of tolerance is the one
    /// `docs/technical/ingestion.md` sets : a publisher who stamps both at the
    /// same second has published rather than updated.
    var updatedAt: Date? {
        guard let stated = updated?.date else { return nil }
        guard let published = publishedAt else { return stated }
        return stated.timeIntervalSince(published) > 60 ? stated : nil
    }

    var attachments: [Enclosure] {
        (enclosure ?? []).compactMap { attachment in
            guard let href = attachment.href, let url = URL(string: href), HTTPURL.isFetchable(url) else { return nil }
            return Enclosure(url: url, type: attachment.type, length: attachment.length?.bytes)
        }
    }
}
