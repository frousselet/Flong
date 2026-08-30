//
//  SourcesScreen.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Where the sources live now.
///
/// A folder tree is something a reader touches when they are organizing, which
/// is rarely, so it does not deserve a permanent column beside what they are
/// reading, which is always. It does not deserve a section of the tab bar
/// either, for the same reason : the bar names the places there are to read,
/// and this is not one of them. It is reached from the reader's own menu, with
/// the rest of what they have decided, and the rest of the window is the
/// article.
struct SourcesScreen: View {
    let model: AppModel
    @Binding var isAddingFeed: Bool
    @Binding var isChoosingFile: Bool
    let open: (SidebarItem.Kind) -> Void

    var body: some View {
        Group {
            List {
                Section {
                    ForEach(model.smartLists.filter { $0.kind != .digest }) { item in
                        row(item)
                    }
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
                        Text("Subscriptions")
                    }
                }

                status
            }
            .navigationTitle(Text("Sources"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isAddingFeed = true
                        } label: {
                            Label("Add a feed", systemImage: "plus")
                        }
                        Button {
                            isChoosingFile = true
                        } label: {
                            Label("Import an OPML file", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("Add a feed", systemImage: "plus")
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
    }

    /// What synchronization is doing, and what is left of a long job.
    ///
    /// Silence is the usual state. A reader with no iCloud account is not doing
    /// anything wrong, and a device that is up to date has nothing to report, so
    /// neither is told anything. What does get said is what a reader can act on.
    ///
    /// It lives here rather than pinned to the bottom of the window : this is
    /// the one section a reader opens when they want to know what the
    /// application is up to, and a permanent bar under the reading would be one
    /// more thing between them and the article.
    @ViewBuilder
    private var status: some View {
        if model.hasOutstandingWork || Self.isWorthSaying(model.syncStatus) {
            Section {
                if model.hasOutstandingWork {
                    HStack {
                        if model.outstandingFeeds > 0 {
                            Text("\(model.outstandingFeeds) feeds left to fetch")
                        } else {
                            Text("Finishing in the background")
                        }
                        Spacer(minLength: 8)
                        if model.isWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Finish now") { Task { await model.finishSetup() } }
                                .buttonStyle(.borderless)
                        }
                    }
                }

                synchronization
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var synchronization: some View {
        switch model.syncStatus {
        case .unavailable:
            EmptyView()

        case .idle(let date):
            if let date {
                Text("Synchronized \(date, format: .relative(presentation: .named))")
            }

        case .working:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Synchronizing")
            }

        case .waiting:
            Label("Waiting for iCloud", systemImage: "clock")

        case .quotaExceeded:
            Label("iCloud storage is full", systemImage: "exclamationmark.icloud")
            Button("Free up space") { Task { await model.purge() } }
                .buttonStyle(.borderless)

        case .failed(let reason):
            Label("iCloud is not answering", systemImage: "exclamationmark.icloud")
                .help(Text(verbatim: reason))
        }
    }

    /// A device that is up to date and has never synchronized says nothing.
    private static func isWorthSaying(_ status: SyncStatus) -> Bool {
        switch status {
        case .unavailable: false
        case .idle(let date): date != nil
        default: true
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Button {
            open(item.kind)
        } label: {
            Label {
                HStack {
                    title(of: item)
                    Spacer(minLength: 8)
                    if item.unreadCount > 0 {
                        Text(item.unreadCount, format: .number)
                            .font(Editorial.metadata)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                // A feed wears its own mark ; the views above it are the
                // application's own and wear the application's symbols.
                if case .feed = item.kind {
                    FeedIconView(stated: item.iconURL, site: item.siteURL)
                } else {
                    Image(systemName: Self.icon(of: item.kind))
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func title(of item: SidebarItem) -> some View {
        switch item.kind {
        case .digest: Text("Digest")
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
        case .digest: "sparkles.rectangle.stack"
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
