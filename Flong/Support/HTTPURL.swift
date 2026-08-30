//
//  HTTPURL.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// An address there is any point asking a server for.
///
/// A feed states addresses relatively as often as absolutely, and a relative
/// address handed to `URLSession` comes back as `NSURLErrorUnsupportedURL`, in
/// the reader's console, with the path and nothing to act on. That is not an
/// error worth reporting : it is an address that should never have been asked
/// for.
///
/// Every place that is about to ask the network for something goes through
/// here, so the check is one thing in one place rather than a habit each caller
/// has to remember.
nonisolated enum HTTPURL {
    /// Whether an address is one a server can answer.
    static func isFetchable(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// The address made absolute against where it was found, or `nil` when it
    /// is not one to ask for at all.
    static func resolved(_ url: URL, against base: URL?) -> URL? {
        if isFetchable(url) { return url }

        // Only a relative address is worth resolving : `mailto:` and `data:`
        // have a scheme and are simply not this.
        guard url.scheme == nil, let base else { return nil }

        let absolute = URL(string: url.relativeString, relativeTo: base)?.absoluteURL
        return isFetchable(absolute) ? absolute : nil
    }
}
