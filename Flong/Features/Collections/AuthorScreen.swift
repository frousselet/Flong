//
//  AuthorScreen.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// One writer, and what they signed.
///
/// The same column and the same rows as everywhere else. A writer is not a
/// different kind of place, it is the stream with one question asked of it, and
/// the question is a byline.
///
/// **The star is in the corner rather than on the page.** It is a judgement
/// about the person the page is named after, so it belongs where every page
/// keeps what can be done to it, and never in the body where it would read as
/// something to do with the article underneath it.
struct AuthorScreen: View {
    let model: AppModel
    let name: String
    /// The window's own : see ``ArticleFeedScreen`` for why it cannot be one
    /// of this screen's making.
    let zoom: Namespace.ID
    let open: (UUID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.authorArticles) { article in
                    ArticleRow(article: article, zoom: zoom) { open(article.id) }
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        // Verbatim : a person is called what they are called in every language.
        .navigationTitle(Text(verbatim: name))
        .toolbar {
            // **The bell before the star, and never merged with it.** Singling
            // a writer out gathers a page about them ; asking to be told about
            // them interrupts the reader wherever they write, which is a great
            // deal more to ask. One control doing both would have every reader
            // who liked forty bylines signed up for forty notifications a day.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.setNotifications(!notifies, forAuthor: name) }
                } label: {
                    Label(
                        notifies ? "Stop notifying new articles" : "Notify every new article",
                        systemImage: notifies ? "bell.fill" : "bell"
                    )
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.setFavouriteAuthor(name, !isFavourite) }
                } label: {
                    Label(
                        isFavourite ? "Remove from favourite authors" : "Add to favourite authors",
                        systemImage: isFavourite ? "star.fill" : "star"
                    )
                }
                .tint(isFavourite ? .yellow : nil)
            }
        }
        .overlay {
            // A favourite with nothing to their name is the ordinary way in
            // here : the decision reached this device from another one, or the
            // purge took the last of the articles it was about. The page still
            // exists, and it still says whose it is.
            if model.authorArticles.isEmpty {
                ContentUnavailableView {
                    Label("Nothing by them here", systemImage: "signature")
                } description: {
                    Text("What they signed has been purged, or has not arrived yet.")
                }
            }
        }
        .task { await model.loadAuthor(name) }
    }

    private var isFavourite: Bool {
        model.openedAuthor?.name == name && model.openedAuthor?.isFavourite == true
    }

    private var notifies: Bool {
        model.openedAuthor?.name == name && model.openedAuthor?.notifies == true
    }
}
