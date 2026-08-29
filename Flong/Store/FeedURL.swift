//
//  FeedURL.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Why an address cannot become a feed URL.
nonisolated enum FeedURLError: Error, Hashable, Sendable {
    case empty
    case malformed
    case unsupportedScheme(String)
    case embeddedCredentials
}

/// The canonical form of a feed address.
///
/// A feed is identified by its URL, and that column is unique, so two spellings
/// of one address have to collapse into a single row before they reach the
/// store. Everything that creates a subscription goes through here : the OPML
/// import, the share extension, a pasted address.
///
/// Canonicalization stays conservative. Case and default ports carry no meaning
/// and are normalized ; a query string, a trailing slash and the scheme do carry
/// meaning and are left alone, because `http` and `https`, or `/feed` and
/// `/feed/`, are genuinely different resources on plenty of servers.
nonisolated enum FeedURL {
    /// Canonicalizes an address typed, pasted or read from a file.
    static func canonical(_ text: String) throws(FeedURLError) -> URL {
        var address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { throw .empty }

        address = removingFeedScheme(address)
        if !hasScheme(address) {
            address = "https://" + address
        }

        guard var components = URLComponents(string: address) else { throw .malformed }

        guard let scheme = components.scheme?.lowercased() else { throw .malformed }
        guard scheme == "http" || scheme == "https" else { throw .unsupportedScheme(scheme) }

        // A password in the URL would land in the database in clear. Section 9
        // of the specification keeps every secret in the keychain, so these
        // addresses are refused until private feeds are implemented.
        guard components.user == nil, components.password == nil else { throw .embeddedCredentials }

        guard let host = components.host?.lowercased(), !host.isEmpty else { throw .malformed }

        components.scheme = scheme
        components.host = host.hasSuffix(".") ? String(host.dropLast()) : host
        components.fragment = nil

        if components.port == defaultPort(for: scheme) {
            components.port = nil
        }
        if components.path.isEmpty {
            components.path = "/"
        }
        if components.query?.isEmpty == true {
            components.query = nil
        }

        guard let url = components.url else { throw .malformed }
        return url
    }

    /// The newsroom an address belongs to.
    ///
    /// A paper that publishes a section feed per desk is one newsroom, not
    /// six : `lemonde.fr/politique/rss` and `lemonde.fr/societe/rss` are the
    /// same room, and a story both of them ran is one room covering it, which
    /// is what the digest counts and what decides whether anything is
    /// happening at all.
    ///
    /// The host, lowercased, without its `www`. Not the registrable domain,
    /// which would need the public suffix list and would fold a paper and its
    /// unrelated blog into one : `blog.example.com` is its own room, and that
    /// is usually right.
    static func room(of url: URL?) -> String? {
        guard let host = url?.host()?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Canonicalizes an address that is already a `URL`.
    static func canonical(_ url: URL) throws(FeedURLError) -> URL {
        try canonical(url.absoluteString)
    }

    /// Drops the `feed:` scheme a browser or an OPML file sometimes carries.
    ///
    /// Both `feed:https://example.com/rss` and `feed://example.com/rss` appear in
    /// the wild, and neither is a scheme a server answers on.
    private static func removingFeedScheme(_ address: String) -> String {
        guard let range = address.range(of: "feed:", options: [.caseInsensitive, .anchored]) else {
            return address
        }
        let rest = String(address[range.upperBound...])
        return rest.hasPrefix("//") ? "https:" + rest : rest
    }

    private static func hasScheme(_ address: String) -> Bool {
        guard let colon = address.firstIndex(of: ":") else { return false }
        let scheme = address[address.startIndex..<colon]
        guard let first = scheme.first, first.isLetter else { return false }
        return scheme.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
    }

    private static func defaultPort(for scheme: String) -> Int? {
        switch scheme {
        case "http": 80
        case "https": 443
        default: nil
        }
    }
}
