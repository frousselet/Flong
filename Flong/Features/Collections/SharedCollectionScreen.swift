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
    /// The window's own : see ``ArticleFeedScreen`` for why it cannot be one
    /// of this screen's making.
    let zoom: Namespace.ID
    /// A piece the reader already holds, which is opened as theirs.
    let open: (UUID) -> Void
    /// An excerpt of a piece they do not, which is read here all the same.
    let read: (SharedEntry) -> Void

    /// The collection as the rest of the application names one, which is what
    /// the members of it are asked for by.
    private var kind: ArticleCollection.Kind { .shared(zone: zone, title: title) }

    var body: some View {
        ScrollView {
            // The people stay at the head of the page as it scrolls, the way
            // the subjects do on the front page and for the same reason : who
            // is in a collection is what the page is about, and the one command
            // about a person should not be somewhere a reader has to scroll
            // back up to reach.
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    // One run of rows, whoever filed each of them, and the
                    // reader's own copy of a piece where they follow the same
                    // source : see ``CollectionRows``.
                    CollectionRows(model: model, kind: kind, zoom: zoom, open: open, read: read)

                    // Under the people rather than over them : a collection
                    // with nobody's filings in it yet still has its members,
                    // and an empty state laid over the page would hide the one
                    // thing there is to see.
                    if model.collectionItems.isEmpty {
                        ContentUnavailableView {
                            Label("Nothing in it yet", systemImage: "folder.badge.person.crop")
                        } description: {
                            Text("What anyone files into this collection shows up here.")
                        }
                        .padding(.top, 40)
                    }
                } header: {
                    MembersStrip(members: model.members(of: kind), faces: model.memberFaces)
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(Text(verbatim: title))
        // **Per collection, and only once the notices are on at all.** A switch
        // that quietens one collection, on a device that has been told to say
        // nothing about any of them, is a switch with nothing to do : it would
        // read as broken the first time a reader used it and heard nothing
        // either way. Where they are off, this says where the answer lives.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if model.wantsCollaborationNotices {
                        let isQuiet = model.mutedSharedCollections.contains(zone)
                        Button {
                            model.setNotices(isQuiet, forSharedCollection: zone)
                        } label: {
                            Label(
                                isQuiet ? "Tell me about additions" : "Say nothing about this one",
                                systemImage: isQuiet ? "bell" : "bell.slash"
                            )
                        }
                    } else {
                        Label("Additions are announced from Notifications", systemImage: "bell.slash")
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis")
                }
            }
        }
        .task { await model.loadCollection(kind) }
        .task { await model.loadShareMembers() }
    }
}
