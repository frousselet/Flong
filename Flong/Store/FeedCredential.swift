//
//  FeedCredential.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CryptoKit
import Foundation

/// What a subscription needs to prove it is entitled to a feed.
///
/// Section 9 of the specification names four, and they are the four that keep
/// working : a per-subscriber secret address, which is what most subscription
/// platforms hand out, HTTP Basic, a bearer token and a fixed header.
///
/// Every one of them is a secret. None is ever written to the database, to a
/// log, to an error message or to a default export : they live in the keychain
/// and nowhere else.
nonisolated enum FeedCredential: Hashable, Sendable, Codable {
    /// The address itself is the secret, which is the dominant case : a
    /// platform hands each subscriber a feed nobody else can guess.
    case secretURL(URL)
    case basic(user: String, password: String)
    case bearer(String)
    /// A header a platform asks for by name, for the ones that invented their
    /// own scheme.
    case header(name: String, value: String)

    /// What the interface says about it, which is never the secret.
    var summary: LocalizedStringResource {
        switch self {
        case .secretURL: "Secret address"
        case .basic(let user, _): "Signed in as \(user)"
        case .bearer: "Bearer token"
        case .header(let name, _): "Header \(name)"
        }
    }

    /// The header a request carries for it, when it carries one.
    ///
    /// A secret address carries none : the secret is the address, and it has
    /// already been used by the time a request exists.
    var header: (name: String, value: String)? {
        switch self {
        case .secretURL:
            nil
        case .basic(let user, let password):
            ("Authorization", "Basic " + Data("\(user):\(password)".utf8).base64EncodedString())
        case .bearer(let token):
            ("Authorization", "Bearer \(token)")
        case .header(let name, let value):
            (name, value)
        }
    }
}

/// The public face of a secret address.
///
/// A feed is identified by its canonical URL, and a feed whose URL is a secret
/// cannot be identified by something the database is not allowed to hold. So the
/// database holds this : the origin the reader recognizes, and a digest of the
/// real address in place of the part that must not be written down.
///
/// It is a URL like any other, so `FeedURL.canonical` and everything built on it
/// work unchanged. It is unique per secret address, so two subscriptions to one
/// platform stay two subscriptions. And it is one way : the digest gives nothing
/// back, and the real address lives only in the keychain.
nonisolated enum MaskedURL {
    /// The path a masked address wears, which says what it is.
    static let marker = "private"

    static func mask(_ url: URL) -> URL? {
        guard let scheme = url.scheme, let host = url.host() else { return nil }

        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()

        var origin = "\(scheme)://\(host)"
        if let port = url.port { origin += ":\(port)" }
        return URL(string: "\(origin)/\(marker)/\(digest)")
    }

    /// Whether an address is one of these rather than a real one.
    static func isMasked(_ url: URL) -> Bool {
        let parts = url.pathComponents.filter { $0 != "/" }
        return parts.count == 2 && parts[0] == marker && parts[1].count == 16
            && parts[1].allSatisfy(\.isHexDigit)
    }
}
