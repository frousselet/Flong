//
//  ArticleFeedScreen.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// A plain list of articles : unread, a feed, a folder, the library.
///
/// The same column and the same rows as the front page. A view of the stream is
/// not a different kind of place, it is the same place with a narrower question.
struct ArticleFeedScreen: View {
    let model: AppModel
    let kind: SidebarItem.Kind
    let open: (UUID) -> Void

    @Namespace private var zoom

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.summaries) { article in
                    ArticleRow(article: article, zoom: zoom) { open(article.id) }
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await model.toggleRead(article) }
                            } label: {
                                Label(
                                    article.isRead ? "Mark as unread" : "Mark as read",
                                    systemImage: article.isRead ? "circle" : "checkmark.circle"
                                )
                            }
                        }
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.markAllRead() }
                } label: {
                    Label("Mark all as read", systemImage: "checkmark.circle")
                }
                .disabled(model.summaries.allSatisfy(\.isRead))
            }
        }
        .refreshable { await model.refreshAll() }
        .overlay {
            if model.summaries.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to read", systemImage: "checkmark.circle")
                } description: {
                    Text("Everything here has been read.")
                }
            }
        }
        .task {
            model.selection = kind
            await model.loadArticles()
        }
    }

    private var title: Text {
        switch kind {
        case .digest: Text("Digest")
        case .unread: Text("Unread")
        case .today: Text("Today")
        case .library: Text("Library")
        case .starred: Text("Starred")
        case .all: Text("All articles")
        case .folder(let path): Text(verbatim: FolderPath.name(of: path))
        case .feed: Text(verbatim: model.title(of: kind) ?? "")
        }
    }
}
