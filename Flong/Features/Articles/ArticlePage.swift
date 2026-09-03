//
//  ArticlePage.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// An article, shown when there is an article to show.
///
/// **A page half drawn is what gives a reader a browser.** A web view hands
/// over what it has as it gets it : the words land, then the type they are set
/// in, then the pictures push everything down the page. Every one of those
/// steps is a page loading rather than a page being read, and none of them is
/// anything the reader can do with. So the view is laid out where nobody can
/// see it, and it is faded in once it says it is finished, which for a web view
/// is after its pictures have arrived and not before.
///
/// **And the wait has two clocks.** A page built from what is already on the
/// device is up before anybody could see a ring, so the ring waits a moment
/// before it appears rather than blinking on every article ; and a picture a
/// publisher serves slowly must not keep the words off the screen, so the page
/// is shown after a second and a half whether the last of them has arrived or
/// not.
struct ArticlePage: View {
    let html: String

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// The document the view has finished laying out, where it has finished
    /// one. It is the document itself rather than a flag, since the reader may
    /// swap the feed's version for the whole article while they read : what
    /// matters is whether what is on screen is what was asked for.
    @State private var painted: String?
    /// Whether the wait has gone on long enough to be worth saying so.
    @State private var isSaying = false

    /// How long a page has to take before the reader is told it is coming.
    private static let patience = Duration.milliseconds(350)
    /// And how long it may take before it is shown regardless.
    private static let ceiling = Duration.milliseconds(1500)

    private var isReady: Bool { painted == html }

    var body: some View {
        ArticleWebView(html: html) { document in
            show(document)
        }
        .opacity(isReady ? 1 : 0)
        .overlay {
            if !isReady, isSaying {
                WaitingRing()
            }
        }
        // The paper of the page itself, behind the page and behind the bar
        // over it : the web view is transparent until it has painted, the bar
        // has nothing of its own, and a band of another colour anywhere in
        // there is the one thing that would say `document` rather than
        // `article`. Stated from the palette rather than left to the system,
        // since a sheet is drawn on the raised grey rather than on the black
        // the page is printed on.
        .background(theme.palette(in: scheme).paper.color.ignoresSafeArea())
        .task(id: html) {
            isSaying = false

            try? await Task.sleep(for: Self.patience)
            guard !Task.isCancelled, painted != html else { return }
            withAnimation(.easeIn(duration: 0.2)) { isSaying = true }

            try? await Task.sleep(for: Self.ceiling - Self.patience)
            guard !Task.isCancelled else { return }
            show(html)
        }
    }

    private func show(_ document: String) {
        guard document == html, painted != document else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            painted = document
            isSaying = false
        }
    }
}
