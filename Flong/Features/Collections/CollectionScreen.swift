//
//  CollectionScreen.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// One square, opened.
///
/// The same column and the same rows as everywhere else. A collection is not a
/// different kind of place, it is the stream with one question asked of it.
struct CollectionScreen: View {
    let model: AppModel
    let kind: ArticleCollection.Kind
    /// The window's own : see ``ArticleFeedScreen`` for why it cannot be one
    /// of this screen's making.
    let zoom: Namespace.ID
    let open: (UUID) -> Void

    @State private var isRenaming = false
    @State private var renamed = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.collectionArticles) { article in
                    ArticleRow(article: article, zoom: zoom) { open(article.id) }
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(CollectionSquare.name(of: kind))
        // Only what the reader made can be renamed or thrown away. The rest is
        // a question the kept articles answer about themselves, and there is
        // nothing there to rename.
        .toolbar {
            if kind.isTheReaders {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        // Only a made collection can be shared. A dynamic one
                        // is a description rather than a set of articles, so
                        // sharing it would hand somebody a question answered
                        // against their own reading and not the reader's : a
                        // different thing, and not this one.
                        if case .made(let name) = kind {
                            ShareLink(
                                item: model.invitation(toCollectionNamed: name),
                                preview: SharePreview(name, image: Image(systemName: "folder"))
                            ) {
                                Label(
                                    model.sharedCollectionNames.contains(name)
                                        ? "Manage the collaboration" : "Invite to collaborate",
                                    systemImage: "person.crop.circle.badge.plus"
                                )
                            }

                            Button {
                                renamed = name
                                isRenaming = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                        }
                        Button(role: .destructive) {
                            Task {
                                await model.deleteCollection(kind)
                                dismiss()
                            }
                        } label: {
                            Label("Delete the collection", systemImage: "trash")
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis")
                    }
                }
            }
        }
        .alert(Text("Rename"), isPresented: $isRenaming) {
            TextField("Name", text: $renamed)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                guard case .made(let name) = kind else { return }
                let renamed = renamed
                Task {
                    await model.renameCollection(name, to: renamed)
                    dismiss()
                }
            }
        } message: {
            // The page is named after the collection, so the page goes with the
            // name : coming back to a title that is no longer true would be
            // stranger than coming back to the grid.
            Text("The articles stay where they are.")
        }
        .task {
            await model.loadCollection(kind)
            await model.loadSharedCollections()
        }
    }
}
