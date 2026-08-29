//
//  SidebarView.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The first level : what to read.
struct SidebarView: View {
    let model: AppModel
    @Binding var isAddingFeed: Bool
    @Binding var isChoosingFile: Bool

    var body: some View {
        List(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
            Section {
                ForEach(model.smartLists) { row($0) }
            }

            if !model.feedItems.isEmpty {
                Section {
                    ForEach(model.feedItems) { item in
                        row(item)
                        ForEach(item.children) { child in
                            row(child).padding(.leading, 16)
                        }
                    }
                } header: {
                    Text("Feeds")
                }
            }
        }
        .navigationTitle(Text(verbatim: "Flong"))
        .toolbar {
            ToolbarItem {
                Button {
                    isAddingFeed = true
                } label: {
                    Label("Add a feed", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button {
                    isChoosingFile = true
                } label: {
                    Label("Import an OPML file", systemImage: "square.and.arrow.down")
                }
            }
        }
        .overlay {
            if model.isEmpty {
                ContentUnavailableView {
                    Label("No feed yet", systemImage: "dot.radiowaves.up.forward")
                } description: {
                    Text("Add a feed, or import an OPML file to bring your subscriptions over.")
                } actions: {
                    Button("Add a feed") { isAddingFeed = true }
                    Button("Import an OPML file") { isChoosingFile = true }
                }
            }
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label {
            title(of: item)
        } icon: {
            Image(systemName: Self.icon(of: item.kind))
        }
        .badge(item.unreadCount)
        .tag(item.kind)
    }

    @ViewBuilder
    private func title(of item: SidebarItem) -> some View {
        switch item.kind {
        case .unread: Text("Unread")
        case .today: Text("Today")
        case .library: Text("Library")
        case .starred: Text("Starred")
        case .all: Text("All articles")
        case .folder, .feed: Text(verbatim: item.title ?? "")
        }
    }

    private static func icon(of kind: SidebarItem.Kind) -> String {
        switch kind {
        case .unread: "circle.inset.filled"
        case .today: "sun.max"
        case .library: "books.vertical"
        case .starred: "star"
        case .all: "tray.full"
        case .folder: "folder"
        case .feed: "dot.radiowaves.up.forward"
        }
    }
}
