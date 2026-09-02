//
//  PooledFeed.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// One source, as it crosses between two readers who have never met.
///
/// **An address, a name, and nothing else.** There is nowhere in here to put a
/// reader, a date, a count, an article or a word of anything they said, and
/// that is the point : what the common pool of section 8 answers is *which
/// addresses are worth following*, and every further field would be something
/// about a person that the question did not need. ``SharedEntry`` makes the
/// same argument for a collection handed to a named participant ; this goes to
/// everybody, so it says less.
///
/// **Every address here has been through ``PublicURL``, and was published only
/// if that changed nothing.** A parameter the reader designated as theirs is
/// not stripped and offered anyway : what is left of such an address is a
/// different address, frequently not a feed at all, and handing somebody a
/// half-address is worse than handing them nothing. The whole source is held
/// back instead. ``PooledFeed/offered(_:secret:hasCredential:)`` is where that
/// is decided, in one place, so no caller has to remember it.
nonisolated struct PooledFeed: Hashable, Sendable, Codable {
    /// The canonical feed address, which is what identifies the source and is
    /// the whole of what a reader is being offered.
    var url: String
    /// What the source calls itself, for a list somebody has to read.
    var title: String
    /// The site behind it, when the feed names one that is public too.
    var siteURL: String?

    enum CodingKeys: String, CodingKey {
        case url = "u"
        case title = "t"
        case siteURL = "s"
    }

    /// The longest a name may be, going out and coming in.
    ///
    /// A feed's title is a headline's worth of text and no more. The cap is
    /// against the record budget on the way out and against a row of a list
    /// being made to hold a paragraph on the way in.
    static let titleLimit = 120

    /// How many sources one reader offers.
    ///
    /// Section 21 targets a thousand followed feeds, so a reader at the top of
    /// the range still offers all of theirs. Past that the list is cut rather
    /// than the record growing : a pool where one person can publish a hundred
    /// thousand addresses is a pool one person can fill.
    static let listLimit = 1_000

    // MARK: - Going out

    /// The source as it may be offered, or `nil` where it may not be.
    ///
    /// **Six reasons to hold one back, and they are all here.** Scattering them
    /// over the publisher and the interface is how one of them eventually gets
    /// forgotten on a path somebody adds later, and the one that gets forgotten
    /// is a reader's private address in a list the whole world reads.
    ///
    /// - The reader took this source out of what they offer.
    /// - Its address is itself the subscription, so the store holds the masked
    ///   form of section 9 and there is nothing here anybody could follow.
    /// - It has a credential, so it is not a source anybody else can read.
    /// - Its address carries something the reader designated as theirs, or
    ///   something that only ever said who sent them.
    /// - Its host is not one another reader could reach : a machine on a
    ///   network, an address literal, a name reserved for not resolving.
    /// - It has never once been fetched successfully, so recommending it would
    ///   be recommending a broken address.
    static func offered(_ feed: Feed, secret: SecretParameters?, hasCredential: Bool) -> PooledFeed? {
        guard feed.isShared, !hasCredential, !MaskedURL.isMasked(feed.url) else { return nil }
        guard feed.lastSuccessAt != nil else { return nil }
        guard PublicURL.of(feed.url, without: secret) == feed.url else { return nil }
        guard isPublic(feed.url) else { return nil }

        let title = name(feed.title) ?? Subscription.fallbackTitle(for: feed.url)
        let site = feed.siteURL.flatMap { site in
            let trimmed = PublicURL.of(site, without: secret)
            return trimmed == site && isPublic(site) ? site.absoluteString : nil
        }

        return PooledFeed(url: feed.url.absoluteString, title: title, siteURL: site)
    }

    // MARK: - Coming in

    /// The source as it may be shown, or `nil` where nothing usable is left.
    ///
    /// **Nothing here is trusted for having been written by a copy of Flong.**
    /// The public database takes a record from anybody with an iCloud account,
    /// so every address is put back through ``FeedURL/canonical(_:)`` rather
    /// than believed : that is what refuses a scheme nobody should be asked to
    /// open, an address with a password written into it, and the malformed
    /// remainder. The name is cut to a title's length and stripped of the
    /// characters that would let a row of a list pretend to be two.
    var received: PooledFeed? {
        guard let url = try? FeedURL.canonical(url), Self.isPublic(url), !MaskedURL.isMasked(url) else {
            return nil
        }

        let canonicalSite = siteURL.flatMap { try? FeedURL.canonical($0) }
        let site = canonicalSite.flatMap { Self.isPublic($0) ? $0.absoluteString : nil }

        return PooledFeed(
            url: url.absoluteString,
            title: Self.name(title) ?? Subscription.fallbackTitle(for: url),
            siteURL: site
        )
    }

    // MARK: - What both sides agree on

    /// A name with nothing in it that belongs to a renderer, cut to length.
    static func name(_ raw: String) -> String? {
        let kept = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let trimmed = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > titleLimit ? String(trimmed.prefix(titleLimit)) : trimmed
    }

    /// Whether an address is one another reader could actually reach.
    ///
    /// **A host on somebody's own network is not a recommendation, it is a
    /// leak.** `localhost:1200`, `nas.local` and `192.168.1.4` say something
    /// about the reader's house and nothing about journalism, and a list of
    /// them would be a list of what people run at home.
    ///
    /// An address literal goes with them, and so do the names reserved for not
    /// resolving, and so does a bare hostname with no dot in it, which is a
    /// machine rather than a domain.
    static let reservedNames: Set<String> = [
        "local", "localhost", "internal", "intranet", "home", "lan",
        "test", "invalid", "example", "onion",
    ]

    static func isPublic(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return false }
        guard !host.contains(":"), host.contains(".") else { return false }
        guard !IPv4Address.looksLikeOne(host) else { return false }
        guard let last = host.split(separator: ".").last, !reservedNames.contains(String(last)) else { return false }
        return !host.hasSuffix(".home.arpa")
    }
}

/// Whether a host is four numbers rather than a name.
///
/// `URL` hands back an address literal as a host like any other, and there is
/// no framework question that says which it was. Four dot-separated groups of
/// digits is the whole of the test, which is enough : a real domain's last
/// label is never all digits, so nothing legitimate is caught by it.
nonisolated enum IPv4Address {
    static func looksLikeOne(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber) && (Int(part) ?? 256) <= 255
        }
    }
}
