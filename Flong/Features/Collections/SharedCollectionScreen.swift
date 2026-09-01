//
//  SharedCollectionScreen.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// A collection somebody else shared, opened.
///
/// **It looks like the stream and it is not the stream, and the rows say so.**
/// What is here is the excerpt each feed published, sent by whoever filed it,
/// from sources this reader may not follow. There is no body to open, no read
/// state of theirs and nothing to star : a row opens the publisher's own page,
/// because that is where the article actually is.
///
/// The alternative was to make these look exactly like the reader's own rows,
/// and it would have been a lie the first time somebody tapped one and left the
/// application.
struct SharedCollectionScreen: View {
    let model: AppModel
    let zone: String
    let title: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.sharedArticles, id: \.guid) { entry in
                    SharedArticleRow(entry: entry, by: model.filedBy[entry.guid]) {
                        guard let address = entry.url.flatMap(URL.init(string:)) else { return }
                        openURL(address)
                    }
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(Text(verbatim: title))
        .overlay {
            if model.sharedArticles.isEmpty {
                ContentUnavailableView {
                    Label("Nothing in it yet", systemImage: "folder.badge.person.crop")
                } description: {
                    Text("What anyone files into this collection shows up here.")
                }
            }
        }
        .task { await model.loadCollection(.shared(zone: zone, title: title)) }
    }
}

/// One excerpt, in a collection somebody else shared.
///
/// The publisher and the byline as everywhere else, then the headline, then the
/// excerpt. What it does not carry is what it does not have : no tick for read,
/// no star, and no picture at the size the reader's own rows use, because an
/// excerpt is a promise of an article rather than the article.
struct SharedArticleRow: View {
    let entry: SharedEntry
    /// Whoever put it here, where they can be named.
    ///
    /// Nothing for the reader's own filings, and nothing for a participant
    /// CloudKit will not name : an opaque identifier is worse than silence,
    /// because it looks like information.
    var by: String?
    let open: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if let source = entry.sourceTitle {
                        Text(verbatim: source)
                            .font(theme.metadata)
                            .foregroundStyle(.secondary)
                    }

                    Text(verbatim: entry.title)
                        .font(.system(.headline))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    if let excerpt = entry.excerpt {
                        Text(verbatim: excerpt)
                            .font(.system(.subheadline))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }

                    // The byline and whoever filed it are two different people
                    // and the row says so : one wrote the piece, the other
                    // thought it was worth passing on.
                    HStack(spacing: 6) {
                        if let author = entry.author {
                            Text(verbatim: author)
                        }
                        if let by {
                            if entry.author != nil { Text(verbatim: "·") }
                            Label {
                                Text("Filed by \(by)")
                            } icon: {
                                Image(systemName: "person.crop.circle")
                            }
                        }
                    }
                    .font(theme.metadata)
                    .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                if entry.imageURL != nil {
                    RemoteImage(url: entry.imageURL.flatMap(URL.init(string:)), aspect: 1, corner: 8)
                        .frame(width: 64, height: 64)
                }
            }
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // It leaves the application, and a reader is owed that before they tap
        // rather than after.
        .accessibilityHint(Text("Opens the article on its own site"))
        .overlay(alignment: .bottom) { Divider() }
    }
}
