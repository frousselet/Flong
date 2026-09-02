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
    /// Opens an excerpt somebody sent, which is read in the application like
    /// anything else rather than handed to a browser.
    let read: (SharedEntry) -> Void

    @State private var isRenaming = false
    @State private var renamed = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            // The people the reader let in stay at the head of the page as it
            // scrolls, the way the subjects do on the front page : the one
            // command about a person should not be somewhere they have to
            // scroll back up to reach. Nothing at all for a collection that was
            // never shared, which is most of them.
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    // **One run of rows, whoever filed each of them.** What the
                    // reader filed and what the other people in the collection
                    // filed were two bands under two headings, which said the
                    // two were different kinds of thing. They are not : they
                    // are what is in the collection, and who put a thing there
                    // is a line on the row rather than a wall between them.
                    CollectionRows(model: model, kind: kind, zoom: zoom, open: open, read: read)
                } header: {
                    MembersStrip(
                        members: model.members(of: kind),
                        faces: model.memberFaces,
                        mayRemove: model.mayRemoveMembers(of: kind)
                    ) { member in
                        guard case .made(let name) = kind else { return }
                        Task { await model.removeMember(member, fromCollectionNamed: name) }
                    }
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
            await model.loadShareMembers()
        }
    }
}
