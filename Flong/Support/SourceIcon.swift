//
//  SourceIcon.swift
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

/// The mark a publisher puts on its articles.
///
/// A list of articles is a list of names, and names take reading. A mark is
/// recognized before it is read, which is the whole of what a favicon is for.
///
/// **It belongs to the publisher and not to the feed.** A favicon is a property
/// of a site : a paper with a feed per desk drew one logo, and asking for it
/// once per desk is six requests to say one thing, six entries in the cache and
/// six chances of one of them coming back different. What is asked for is
/// worked out from ``SourceIdentity``, which is resolved once per group, so
/// every row of that publisher wants the same picture and the store answers all
/// of them from the one fetch.
///
/// Three addresses are tried, in this order :
///
/// 1. **What one of its feeds states**, since the publisher chose it. Atom's
///    `icon` and JSON Feed's `icon` and `favicon` are square by their
///    specifications ; RSS's `image` is a banner, and a banner cropped to a
///    square still shows the middle of a logo, which is usually the logo.
/// 2. **`apple-touch-icon.png`**, a well-known path, square by convention and
///    large enough to stay crisp where a sixteen pixel favicon would not.
/// 3. **`favicon.ico`**, the oldest well-known path and still the most widely
///    served, since browsers ask for it whether a page mentions it or not.
///
/// Nothing is asked for until a row is on screen, and what comes back is kept
/// on disk, so a publisher costs one request and not one per appearance. One
/// that answers none of the three wears the generic mark and is asked no more
/// that session.
nonisolated enum SourceIcon {
    static let wellKnown = ["apple-touch-icon.png", "favicon.ico"]

    /// The addresses worth trying for a publisher, best first.
    static func candidates(for identity: SourceIdentity?) -> [URL] {
        guard let identity else { return [] }
        return candidates(stated: identity.iconURL, site: identity.siteURL)
    }

    /// The addresses worth trying for a site, best first.
    static func candidates(stated: URL?, site: URL?) -> [URL] {
        var addresses: [URL] = []
        // Resolved against the site, since a feed states its icon relatively
        // as often as not, and dropped when it is not an address to ask for.
        if let stated, let usable = HTTPURL.resolved(stated, against: site) { addresses.append(usable) }

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

    /// The one address to try where only one may be tried.
    ///
    /// A view asks for the three in turn and stops at the first that answers.
    /// A page cannot : the article is rendered with scripting off, so nothing
    /// in it can notice that a picture failed and reach for the next, and a
    /// stylesheet that names three addresses paints all three on top of one
    /// another rather than falling through them.
    ///
    /// So the order changes when there is only one go at it. What a feed states
    /// is still first, since the publisher chose it and it is the one address
    /// that is known to exist. Failing that it is `favicon.ico` rather than
    /// `apple-touch-icon.png` : the touch icon is the better picture and the
    /// more often absent, and the better picture is worth a try only where a
    /// miss costs another request rather than an empty space.
    static func mark(for identity: SourceIdentity?) -> URL? {
        guard let identity else { return nil }

        let addresses = candidates(for: identity)
        let chosen = identity.iconURL == nil ? addresses.last : addresses.first
        guard let chosen, HTTPURL.isFetchable(chosen) else { return nil }
        return HTTPURL.secured(chosen)
    }
}

nonisolated extension EnvironmentValues {
    /// What each publisher is called and the mark it wears, by domain.
    ///
    /// In the environment rather than handed down row by row. Every list in the
    /// application shows the publisher an article came from, and threading a
    /// dictionary through five screens to reach the row that draws it would be
    /// five signatures carrying something none of them is about. It changes
    /// when the subscriptions change, which is rarely.
    @Entry var publishers: [String: SourceIdentity] = [:]
}

/// The mark of a publisher, at the size it is shown.
struct SourceIconView: View {
    let identity: SourceIdentity?
    var side: CGFloat = 18

    @State private var image: CGImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let image {
                // Round, and set in the same hairline of glass the pictures
                // wear. A favicon arrives as whatever square its publisher
                // drew, dark on dark as often as not, and a round crop in a
                // ring is what makes a column of them read as one column
                // rather than as a row of unrelated stamps.
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(.circle)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                .separator.opacity(RemoteImage.ringOpacity),
                                lineWidth: RemoteImage.ring
                            )
                    }
            } else {
                // Not a blank : a list of articles must keep its column of
                // marks whether a publisher serves one or not.
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: side * 0.8))
                    .foregroundStyle(.secondary)
                    .frame(width: side, height: side)
            }
        }
        .accessibilityHidden(true)
        .task(id: identity) { await load() }
    }

    private func load() async {
        let candidates = SourceIcon.candidates(for: identity)
        guard !candidates.isEmpty else { return }

        let pixels = max(Int(side * displayScale), 1)

        // **Already in hand : no hop off the actor, no generic mark, no fade.**
        // A list keeps a row's state only while the row is realized, so a
        // reader running one back and forth arrives at the same publisher again
        // and again with nothing in hand, and the asynchronous path below costs
        // a hop off the main actor even when the answer is a picture that has
        // been decoded for minutes. That hop is a frame, and a frame is long
        // enough for the radiowaves glyph to be drawn : every mark on the page
        // blinked to the generic one and faded back the moment its row came on
        // screen. ``ImageStore/held(at:maximumPixels:)`` never fetches and
        // never decodes, which is what lets the mark be there before the row
        // is. ``RemoteImage`` reads the same way, for the same reason.
        for candidate in candidates {
            guard let held = ImageStore.shared.held(at: candidate, maximumPixels: pixels) else { continue }
            image = held
            return
        }

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

/// Who an article came from : the publisher's mark, and its name beside it.
///
/// **The publisher, never the feed.** A row used to carry the title of the feed
/// the article arrived through, which is how a reader following three desks of
/// one paper met `Le Monde - À la Une`, `Le Monde - International` and
/// `Le Monde - Sport` down one page and had to work out that they were one
/// paper. The desk is an implementation detail of how the paper publishes ;
/// what a reader wants to know is who wrote it. The desks are still there, in
/// the sources list, which is where a subscription is managed.
///
/// The name is looked up rather than carried on the article, so a publisher the
/// reader renames is renamed on every row at once, and an article whose feed
/// has just gone still says where it came from.
struct SourceStamp: View {
    let domain: String?
    var side: CGFloat = 13
    var showsName = true
    /// What to call the publisher where this device does not follow them.
    ///
    /// **The reader's own name wins whenever there is one.** A publisher they
    /// renamed is that publisher everywhere, and an excerpt somebody shared
    /// from a source they follow must not come back under the sender's name for
    /// it. This is only for the publishers they do not follow, where the sender
    /// said what the source is called and the bare host says less.
    var otherwise: String?

    @Environment(\.publishers) private var publishers

    private var identity: SourceIdentity? {
        guard let domain else { return nil }
        return publishers[domain]
    }

    var body: some View {
        HStack(spacing: 6) {
            SourceIconView(identity: identity, side: side)

            // Verbatim : a publisher's name is either an address or something
            // the reader wrote, and neither is translated. The address stands
            // in until the subscriptions are read back, and for an article
            // whose feed has gone.
            if showsName, let name = identity?.name ?? otherwise ?? domain {
                Text(verbatim: name).lineLimit(1)
            }
        }
    }
}
