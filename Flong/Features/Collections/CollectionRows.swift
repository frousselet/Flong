//
//  CollectionRows.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What is in an opened collection, as one run of rows in date order.
///
/// **One list, whoever filed each row.** What the reader filed and what the
/// other people in the collection filed stood in two bands under two headings,
/// which said the two were different kinds of thing. They are not : they are
/// what is in the collection. Who put a thing there is a line on the row, which
/// is where it belongs.
///
/// **A row is drawn by what this device holds, never by who sent it.** A piece
/// the reader follows the source of is their own article, with its picture, its
/// read state and their marks ; one from a feed they do not follow is the
/// excerpt its publisher put in the feed. ``CollectionItem`` decides which, and
/// both open in the reader.
///
/// **Taking a row out is offered where it can actually be done.** The reader
/// takes back what they put in ; the owner of the collection may take down
/// anything. ``AppModel/mayTakeDown(_:in:)`` is the whole of that rule.
struct CollectionRows: View {
    let model: AppModel
    let kind: ArticleCollection.Kind
    let zoom: Namespace.ID
    var open: (UUID) -> Void = { _ in }
    var read: (SharedEntry) -> Void = { _ in }

    @State private var removing: CollectionItem?

    var body: some View {
        ForEach(model.items(in: kind)) { item in
            row(item)
                // A long press rather than a swipe : these rows are laid out
                // in a stack and not in a list, and a swipe action belongs to
                // a list. The same command is on the article's own page, so a
                // reader who never finds this one is not stuck with the row.
                .contextMenu {
                    if model.mayTakeDown(item, in: kind) {
                        Button(role: .destructive) {
                            removing = item
                        } label: {
                            Label("Remove from the collection", systemImage: "minus.circle")
                        }
                    }
                }
                .accessibilityActions {
                    if model.mayTakeDown(item, in: kind) {
                        Button("Remove from the collection") { removing = item }
                    }
                }
        }

        // **The dialog hangs off a strip of nothing, on purpose.** A modifier
        // written after a `ForEach` is applied to every view it makes, so this
        // one would be one dialog per row, all bound to the same state and all
        // trying to present at once. Out here there is one of it.
        Color.clear
            .frame(height: 0)
            .confirmationDialog(
                Text("Remove from the collection?"),
                isPresented: .init(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let removing { Task { await model.takeDown(removing, from: kind) } }
                    removing = nil
                }
                Button("Cancel", role: .cancel) { removing = nil }
            } message: {
                // What is taken out is the filing and never the article : a
                // piece the reader follows the source of stays in their
                // stream, and one somebody else filed stays in theirs.
                Text("It leaves the collection for everyone. The article itself is untouched.")
            }
    }

    @ViewBuilder
    private func row(_ item: CollectionItem) -> some View {
        switch item {
        case .held(let article):
            ArticleRow(article: article, zoom: zoom) { open(article.id) }

        case .excerpt(let entry):
            SharedArticleRow(entry: entry, by: model.filedBy[entry.guid]) { read(entry) }
        }
    }
}

/// One excerpt, of a piece this device does not hold.
///
/// **Drawn exactly as the reader's own rows are**, because a collection is one
/// list and a row that looked different would be saying the wrong thing : what
/// separates these from the rest is not who filed them but that this device has
/// no article behind them, and that is not something a reader acts on.
///
/// **Under the reader's own name for the publisher.** A source they renamed is
/// that source everywhere, so a row is stamped from the publishers this device
/// knows and falls back to what the sender called it only where they follow
/// nobody at that address. See ``SourceStamp``.
///
/// The one thing it carries that a stream row does not is who put it here,
/// which is the whole of what a collection several people fill has to say.
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

    /// The publisher, worked out from the addresses the excerpt carries, so the
    /// stamp can look them up among the ones this device follows.
    private var domain: String? {
        FeedURL.publisher(
            site: entry.url.flatMap(URL.init(string:)),
            feed: entry.feedURL.flatMap(URL.init(string:))
        )
    }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: entry.title)
                        .font(theme.headline(.body))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let excerpt = entry.excerpt, !excerpt.isEmpty {
                        Text(verbatim: excerpt)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: 6) {
                        SourceStamp(domain: domain, otherwise: entry.sourceTitle)
                            .padding(.trailing, 2)
                        ArticleMoment(sent: entry)
                        if let by {
                            Text(verbatim: "·")
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
                .frame(maxWidth: .infinity, alignment: .leading)

                if entry.imageURL != nil {
                    RemoteImage(
                        url: entry.imageURL.flatMap(URL.init(string:)),
                        width: Self.thumbnailWidth,
                        corner: 6
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }

    /// The same width the stream gives a picture, since these are the same rows.
    private static let thumbnailWidth: CGFloat = 78
}
