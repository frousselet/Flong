//
//  NewsmakerScreen.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// One person, and what is written about them.
///
/// The same column and the same rows as everywhere else. A person is not a
/// different kind of place : it is the stream with one question asked of it,
/// and the question is a name in the prose rather than a name in a field.
///
/// **What it gathers is the thing a feed reader could not do before.** A
/// subscription follows a publisher and a favourite writer follows a byline ;
/// neither of them can answer *what is being written about this person*. This
/// page is that answer, across every paper the reader follows, which is why the
/// row it opens from is worth a square of its own.
///
/// **The star and the bell are in the corner rather than on the page**, exactly
/// as on a writer's. They are judgements about the person the page is named
/// after, so they belong where every page keeps what can be done to it, and
/// never in the body where they would read as something to do with the article
/// underneath.
struct NewsmakerScreen: View {
    let model: AppModel
    let name: String
    /// The window's own : see ``ArticleFeedScreen`` for why it cannot be one
    /// of this screen's making.
    let zoom: Namespace.ID
    let open: (UUID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.newsmakerArticles) { article in
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
            // somebody out gathers a page about them ; asking to be told about
            // them interrupts the reader every time any paper writes about
            // them, which for somebody in the middle of a story is a great deal
            // more than they meant to ask for.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.setNotifications(!notifies, forNewsmaker: name) }
                } label: {
                    Label(
                        notifies ? "Stop notifying articles about them" : "Notify every article about them",
                        systemImage: notifies ? "bell.fill" : "bell"
                    )
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.setFavouriteNewsmaker(name, !isFavourite) }
                } label: {
                    Label(
                        isFavourite ? "Remove from favourite newsmakers" : "Add to favourite newsmakers",
                        systemImage: isFavourite ? "star.fill" : "star"
                    )
                }
                .tint(isFavourite ? .yellow : nil)
            }
        }
        .overlay {
            // A favourite with nothing to their name is the ordinary way in
            // here : the decision reached this device from another one, or the
            // purge took the last article that named them. The page still
            // exists, and it still says whose it is.
            if model.newsmakerArticles.isEmpty {
                ContentUnavailableView {
                    Label("Nothing about them here", systemImage: "person.crop.rectangle.stack")
                } description: {
                    Text("What named them has been purged, or has not arrived yet.")
                }
            }
        }
        .task { await model.loadNewsmaker(name) }
    }

    private var isFavourite: Bool {
        model.openedNewsmaker?.name == name && model.openedNewsmaker?.isFavourite == true
    }

    private var notifies: Bool {
        model.openedNewsmaker?.name == name && model.openedNewsmaker?.notifies == true
    }
}
