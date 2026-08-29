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
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if model.hasOutstandingWork {
                    OutstandingWorkView(
                        feeds: model.outstandingFeeds,
                        isWorking: model.isWorking
                    ) {
                        Task { await model.finishSetup() }
                    }
                }
                SyncStatusView(status: model.syncStatus) {
                    Task { await model.purge() }
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

/// What synchronization is doing, when there is anything worth saying.
///
/// Silence is the usual state. A reader with no iCloud account is not doing
/// anything wrong, and a device that is up to date has nothing to report, so
/// neither is told anything. What does get said is what a reader can act on.
private struct SyncStatusView: View {
    let status: SyncStatus
    let purge: () -> Void

    var body: some View {
        switch status {
        case .unavailable:
            EmptyView()

        case .idle(let date):
            if let date {
                row {
                    Text("Synchronized \(date, format: .relative(presentation: .named))")
                }
            }

        case .working:
            row {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Synchronizing")
                }
            }

        case .waiting:
            row {
                Label("Waiting for iCloud", systemImage: "clock")
            }

        case .quotaExceeded:
            VStack(spacing: 4) {
                Label("iCloud storage is full", systemImage: "exclamationmark.icloud")
                    .font(.footnote)
                Button("Free up space", action: purge)
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.bar)

        case .failed(let reason):
            row {
                Label("iCloud is not answering", systemImage: "exclamationmark.icloud")
                    .help(Text(verbatim: reason))
            }
        }
    }

    private func row(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.bar)
    }
}

/// What is left of a long job, and the way to get on with it.
///
/// An import leaves a thousand subscriptions and nothing in any of them, and a
/// reader who is not told will conclude that the import failed. The work is
/// resumable, so this says how much is left and offers to press on.
private struct OutstandingWorkView: View {
    let feeds: Int
    let isWorking: Bool
    let start: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            if feeds > 0 {
                Text("\(feeds) feeds left to fetch")
            } else {
                Text("Finishing in the background")
            }

            if isWorking {
                ProgressView().controlSize(.small)
            } else {
                Button("Finish now", action: start)
                    .buttonStyle(.borderless)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
