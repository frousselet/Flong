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

    /// The same address over TLS.
    ///
    /// **App Transport Security refuses a plain `http` request outright**, and
    /// the refusal is a `-1022` in the reader's console rather than anything
    /// they can act on : the picture is simply missing and nothing says why.
    /// A feed written years ago states `http` for its pictures, its icon and
    /// sometimes for itself, long after the site started serving TLS, and the
    /// old address goes on working in a browser because the server redirects.
    /// `URLSession` never gets far enough to be redirected.
    ///
    /// So the scheme is raised at the moment an address becomes a request. A
    /// site that has no TLS at all fails either way, and fails the same way it
    /// does today ; every site that has it, which is very nearly all of them
    /// now, answers.
    ///
    /// **Only what the application fetches for itself.** A link the reader
    /// follows is opened by the browser, which is not bound by this policy and
    /// has its own opinion about upgrading, and rewriting one here would break
    /// the few sites that genuinely serve nothing but `http`.
    static func secured(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http" else { return url }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url ?? url
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
