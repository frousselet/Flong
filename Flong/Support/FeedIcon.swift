//
//  FeedIcon.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import SwiftUI

/// The mark a source puts on its own articles.
///
/// A list of feeds is a list of names, and names take reading. A mark is
/// recognized before it is read, which is the whole of what a favicon is for.
///
/// Three addresses are tried, in this order :
///
/// 1. **What the feed states**, since the publisher chose it. Atom's `icon` and
///    JSON Feed's `icon` and `favicon` are square by their specifications ;
///    RSS's `image` is a banner, and a banner cropped to a square still shows
///    the middle of a logo, which is usually the logo.
/// 2. **`apple-touch-icon.png`**, a well-known path, square by convention and
///    large enough to stay crisp where a sixteen pixel favicon would not.
/// 3. **`favicon.ico`**, the oldest well-known path and still the most widely
///    served, since browsers ask for it whether a page mentions it or not.
///
/// Nothing is asked for until a row is on screen, and what comes back is kept
/// on disk, so a feed costs one request and not one per appearance. A feed that
/// answers none of the three wears the generic mark and is asked no more that
/// session.
nonisolated enum FeedIcon {
    static let wellKnown = ["apple-touch-icon.png", "favicon.ico"]

    /// The addresses worth trying for a source, best first.
    static func candidates(stated: URL?, site: URL?) -> [URL] {
        var addresses: [URL] = []
        if let stated { addresses.append(stated) }

        // The well-known paths hang off the root of the site, never off the page
        // the feed happens to point at.
        if let site, let host = site.host(), let scheme = site.scheme,
            var root = URL(string: "\(scheme)://\(host)")
        {
            if let port = site.port { root = URL(string: "\(scheme)://\(host):\(port)") ?? root }
            addresses.append(contentsOf: wellKnown.map { root.appending(path: $0) })
        }

        var seen = Set<URL>()
        return addresses.filter { seen.insert($0).inserted }
    }
}

/// The mark of a source, at the size it is shown.
struct FeedIconView: View {
    let stated: URL?
    let site: URL?
    var side: CGFloat = 18

    @State private var image: CGImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(.rect(cornerRadius: side / 4.5))
            } else {
                // Not a blank : a list of feeds must keep its column of marks
                // whether a publisher serves one or not.
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: side * 0.8))
                    .foregroundStyle(.secondary)
                    .frame(width: side, height: side)
            }
        }
        .accessibilityHidden(true)
        .task(id: stated ?? site) { await load() }
    }

    private func load() async {
        let candidates = FeedIcon.candidates(stated: stated, site: site)
        guard !candidates.isEmpty else { return }

        let pixels = max(Int(side * displayScale), 1)
        for candidate in candidates {
            guard !Task.isCancelled else { return }
            guard let found = try? await ImageStore.shared.image(at: candidate, maximumPixels: pixels) else {
                continue
            }

            withAnimation(.easeOut(duration: 0.15)) { image = found }
            return
        }
    }
}
