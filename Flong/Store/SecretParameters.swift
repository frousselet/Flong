//
//  SecretParameters.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The parameters of a feed's addresses that the reader said are theirs.
///
/// **Flong does not guess which ones those are, and this type is why it does
/// not have to.** A platform that hands out a per-subscriber feed puts the
/// subscriber in the query string, and so does a site that lets a reader pick a
/// section : `?token=` and `?format=rss` look exactly alike from here.
/// `docs/technical/feed-identity.md` already settled the consequence for
/// identity, keeping the query string because it *selects the feed on plenty of
/// sites* ; a heuristic that stripped it to be safe would collapse two
/// subscriptions into one and hand somebody a link to the wrong page.
///
/// So the reader says, per feed, and nothing else is ever taken off.
///
/// **The names live in the keychain rather than in the database.** They travel
/// to the reader's other devices through iCloud Keychain, which is where
/// ``KeychainCredentials`` already puts a password and for the same reasons, so
/// a second device knows what to take off an address without being told again.
/// They are also then absent from a default export, which is where a list of
/// exactly which parameters carry a subscription would be least welcome.
///
/// **Nothing is taken off at ingestion.** An article's address is written down
/// as the feed published it : the reader has to be able to open the piece, and
/// the parameters that are not secret are frequently what makes the address
/// work at all. The removal happens where an address leaves, which is a shared
/// collection or an export, and it is done by ``PublicURL``.
nonisolated struct SecretParameters: Hashable, Sendable, Codable {
    /// The names, folded, so that `Token` and `token` are one designation.
    ///
    /// A query string is case sensitive by the letter of the specification and
    /// is treated every possible way in practice. Folding risks taking off one
    /// parameter too many ; not folding risks leaving a subscription on a link
    /// handed to somebody else. Only one of those two is worth risking.
    private(set) var names: Set<String>

    init(_ names: some Sequence<String> = [String]()) {
        self.names = Set(names.compactMap(Self.folded))
    }

    var isEmpty: Bool { names.isEmpty }

    /// The form a name is compared in, or `nil` when it is not a name.
    static func folded(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    func contains(_ name: String) -> Bool {
        guard let folded = Self.folded(name) else { return false }
        return names.contains(folded)
    }

    mutating func insert(_ name: String) {
        guard let folded = Self.folded(name) else { return }
        names.insert(folded)
    }

    mutating func remove(_ name: String) {
        guard let folded = Self.folded(name) else { return }
        names.remove(folded)
    }

    /// The names an address carries, in the order it carries them.
    ///
    /// What the interface asks the reader about : a list of parameter names
    /// against a real address is a question somebody can answer, where the same
    /// question in the abstract is not.
    static func names(of url: URL) -> [String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var seen = Set<String>()
        return (components?.queryItems ?? []).compactMap { item in
            guard let folded = folded(item.name), seen.insert(folded).inserted else { return nil }
            return item.name
        }
    }
}

/// An address with nothing left on it that says who the reader is.
///
/// Used wherever an address leaves this device for somebody else : a shared
/// collection, an export. Never on the way in, and never on a feed's own
/// address, which is its identity and is masked rather than trimmed.
nonisolated enum PublicURL {
    /// The address, without the parameters the reader designated and without
    /// the ones that only ever said who sent them.
    ///
    /// **The tracking parameters go whether anything was designated or not.**
    /// ``ArticleKey/tracking`` already exists as the list of parameters that
    /// say who sent the reader rather than what they are reading, and none of
    /// them belongs in a link handed to another person.
    ///
    /// **Anything in front of the host goes too.** A `user:password@host` is a
    /// credential written into an address, and it is the one place a secret can
    /// sit in a URL without being a query parameter at all.
    static func of(_ url: URL, without secret: SecretParameters? = nil) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }

        components.user = nil
        components.password = nil

        if let items = components.queryItems, !items.isEmpty {
            let taken = ArticleKey.tracking.union(secret?.names ?? [])
            let kept = items.filter { item in
                guard let folded = SecretParameters.folded(item.name) else { return true }
                return !taken.contains(folded)
            }
            // An empty query is no query, which is what a canonical address
            // says too : `docs/technical/feed-identity.md`.
            components.queryItems = kept.isEmpty ? nil : kept
        }

        return components.url ?? url
    }
}
