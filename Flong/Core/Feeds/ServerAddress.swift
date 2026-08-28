//
//  ServerAddress.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Turns what someone types into the base URL of an instance.
nonisolated enum ServerAddress {
    /// A bare host gets `https://`, and trailing slashes are dropped so the API
    /// path can be appended without doubling the separator.
    ///
    /// - Returns: `nil` when the result has no host, the only thing that makes
    ///   an address unusable.
    static func normalized(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let lowercased = text.lowercased()
        if !lowercased.hasPrefix("http://") && !lowercased.hasPrefix("https://") {
            text = "https://" + text
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }

        guard let url = URL(string: text), let host = url.host(), !host.isEmpty else { return nil }
        return url
    }
}
