//
//  SearchScreen.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Search, where the system puts search.
///
/// Its own section rather than a field bolted to the front page : a query
/// language with fields, states and dates is a place a reader goes, not a
/// decoration on a page they were already reading.
struct SearchScreen: View {
    let model: AppModel
    let zoom: Namespace.ID
    let open: (UUID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.summaries) { article in
                    ArticleRow(article: article, zoom: zoom) { open(article.id) }
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(Text("Search"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(
            text: Binding(get: { model.searchText }, set: { model.searchText = $0 }),
            prompt: Text("Search")
        ) {
            ForEach(model.searchSuggestions, id: \.self) { suggestion in
                Text(verbatim: suggestion).searchCompletion(suggestion)
            }
        }
        .overlay {
            if model.summaries.isEmpty {
                if model.isShowingResults {
                    ContentUnavailableView.search
                } else {
                    ContentUnavailableView {
                        Label("Search", systemImage: "magnifyingglass")
                    } description: {
                        Text("Words, or a query : title:, author:, tag:, is:unread, after:2026-01.")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.isShowingResults, !model.summaries.isEmpty {
                Text("\(model.summaries.count) results")
                    .font(Editorial.metadata)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .task {
            model.selection = .all
            await model.loadArticles()
        }
    }
}
