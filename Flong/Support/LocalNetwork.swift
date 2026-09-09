//
//  LocalNetwork.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Whether an address is one on the reader's own network.
///
/// **It exists so that a refusal can be a sentence.** App Transport Security
/// carries plain HTTP to the private ranges and to nothing else, and a request
/// it refuses fails with a number the reader can do nothing with. Asking the
/// same question here means the editor can say `not encrypted, this only works
/// on your own network` under an address that will work, and refuse one that
/// will not before it is ever saved.
///
/// It is a floor and not a policy : it says what the system will carry, and
/// what Flong does about it is decided where the address is typed.
nonisolated enum LocalNetwork {
    /// The names that never leave the machine or the network it is on.
    private static let names: Set<String> = ["localhost"]

    static func isPrivate(_ host: String) -> Bool {
        let host = host.lowercased()
        if names.contains(host) || host.hasSuffix(".local") { return true }

        if let bytes = fourBytes(of: host) {
            // 10/8, 172.16/12, 192.168/16, 127/8 and the link-local 169.254/16.
            if bytes[0] == 10 || bytes[0] == 127 { return true }
            if bytes[0] == 172, (16...31).contains(bytes[1]) { return true }
            if bytes[0] == 192, bytes[1] == 168 { return true }
            if bytes[0] == 169, bytes[1] == 254 { return true }
            return false
        }

        // The sixth version, written as the reader would type it into a field :
        // the loopback, the link-local range and the unique local one.
        let bare = host.hasPrefix("[") ? String(host.dropFirst().dropLast()) : host
        if bare == "::1" { return true }
        if bare.hasPrefix("fe8") || bare.hasPrefix("fe9") || bare.hasPrefix("fea") || bare.hasPrefix("feb") {
            return true
        }
        if bare.hasPrefix("fc") || bare.hasPrefix("fd") { return true }

        return false
    }

    /// The four numbers of an address written the way a reader types one, or
    /// nothing where it is a name rather than an address.
    private static func fourBytes(of host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        let bytes = parts.compactMap { Int($0) }
        guard bytes.count == 4, bytes.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return bytes
    }

    /// Whether an address may be spoken to in the clear.
    ///
    /// A model server the reader runs on their own machine has no TLS and never
    /// will, and it is the one configuration of this whole feature that sends
    /// nothing to anybody. Everywhere else, `https` or nothing.
    static func allowsPlainHTTP(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http" else { return true }
        guard let host = url.host() else { return false }
        return isPrivate(host)
    }
}
