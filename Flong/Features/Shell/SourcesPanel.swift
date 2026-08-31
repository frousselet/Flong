//
//  SourcesPanel.swift
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
/// A list of sources is something a reader touches when they are organizing,
/// which is rarely, so it does not deserve a permanent column beside what they
/// are reading, which is always. It does not deserve a section of the tab bar
/// either, for the same reason : the bar names the places there are to read,
/// and this is not one of them. It is reached from the reader's own menu, with
/// the rest of what they have decided, and the rest of the window is the
/// article.
///
/// **The sources are grouped by publisher, and there is nothing to make.** It
/// used to be a folder tree, which nothing in Flong ever let a reader build :
/// the only folders that existed came out of somebody else's OPML file, so the
/// organization was inherited and could not be tended. A publisher is worked
/// out from the address a source is served at, so it is right the moment a
/// subscription lands, it cannot go stale, and there is no empty group left
/// behind when the last of its feeds goes.
///
/// **Every source is under a heading, including the ones alone under theirs.**
/// A list where some rows sit under a publisher and others sit loose is a list
/// where the reader cannot tell in advance where a source will be, and a
/// heading over one row costs a line to say something true. The heading is also
/// the only place a group is acted on, so a group of one has to have one.
///
/// **A favourite source is marked and nothing more.** It is the reader saying
/// this publisher is one of theirs ; it does not star an article, does not
/// reorder the list and does not change what the front page ranks. What it does
/// is fill a square on the collections page, beside the starred articles, where
/// the two are plainly different things.
struct SourcesPanel: View {
    let model: AppModel
    /// Where a row leads, once the panel is out of the way.
    let open: (SidebarItem.Kind) -> Void

    @Environment(\.dismiss) private var dismiss

    /// The publisher whose name is being written, and what is being written.
    @State private var renaming: String?
    @State private var renamed = ""
    @State private var isAddingFeed = false
    @State private var isChoosingFile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head

            List {
                Section {
                    ForEach(model.smartLists.filter { $0.kind != .digest }) { item in
                        row(item)
                    }
                }

                ForEach(model.sourceGroups) { group in
                    Section {
                        ForEach(group.children) { source in
                            row(source)
                                .swipeActions(edge: .leading) { favouriting(source) }
                                .contextMenu { favouriting(source) }
                        }
                    } header: {
                        heading(of: group)
                    }
                }

                status
            }
            .scrollContentBackground(.hidden)
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
        .presentationDetents([.height(Panel.tall), .large])
        .presentationDragIndicator(.visible)
        .alert(
            Text("Rename"),
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
            presenting: renaming
        ) { domain in
            TextField("Name", text: $renamed)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let name = renamed
                Task { await model.renameGroup(domain, to: name) }
            }
        } message: { domain in
            // Verbatim : an address is the same address in every language.
            Text(
                "The sources stay where they are. Leave it empty to call it \(domain) again.",
                comment: "The address of a publisher, such as lemonde.fr"
            )
        }
        // The two ways in, presented over the panel rather than behind it. They
        // belong to what the reader is doing here, and a panel that had to be
        // dismissed before either could open would be asking them to put the
        // list away in order to add to it.
        .sheet(isPresented: $isAddingFeed) {
            AddFeedView(
                add: { address in await model.addFeed(at: address) },
                addPrivate: { address in await model.addPrivateFeed(at: address) }
            )
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: OPMLDocument.types) { result in
            guard case .success(let url) = result else { return }
            Task { await model.importOPML(from: url) }
        }
    }

    /// What the panel is, the two ways to add a source, and the way out on the
    /// platform that needs one.
    private var head: some View {
        HStack(spacing: 14) {
            Text("Sources")
                .font(Editorial.headline(.title3))

            Spacer(minLength: 8)

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
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.medium))
            }

            PanelDismiss()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    /// Where a row leads : the panel goes first, and the page it asked for
    /// arrives behind it.
    private func go(to kind: SidebarItem.Kind) {
        dismiss()
        open(kind)
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
    ///
    /// **The front page says it too now, and that is not the bar this refuses.**
    /// What is refused here is something permanent, under the reading, saying
    /// nothing most of the time. ``ActivityLine`` is at the head of the front
    /// page, exists only while a phase is actually running, and goes the moment
    /// it is over. A reader reported not knowing whether the page in front of
    /// them was current, which is a question this screen could only answer if
    /// they thought to come and ask it.
    ///
    /// What is said in both places comes from the same ``WorkPhase``, so the two
    /// cannot come to describe one pass differently. What stays here alone is
    /// what the reader has to act on : a full iCloud, a refusal, the offer to
    /// finish an import now. None of that belongs in a strip that disappears.
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

    /// The head of a group, which is also the only place a group is acted on.
    ///
    /// The heading is the control rather than carrying one : a button beside
    /// every heading in a list of two hundred sources is two hundred buttons
    /// saying the same thing, and a heading that opens is one thing the reader
    /// learns once. The chevron is what says it opens at all.
    private func heading(of group: SidebarItem) -> some View {
        Menu {
            Button {
                renamed = group.title ?? ""
                renaming = domain(of: group)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                go(to: group.kind)
            } label: {
                Label("All articles", systemImage: "tray.full")
            }
        } label: {
            HStack(spacing: 4) {
                // The mark stands here and nowhere else in the list. It belongs
                // to the publisher, so six desks of one paper are one favicon
                // shown once, rather than one column saying the same thing six
                // times over.
                SourceStamp(domain: domain(of: group), side: 16)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                Spacer(minLength: 8)
                if group.unreadCount > 0 {
                    Text(group.unreadCount, format: .number)
                }
            }
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        // A heading is set in capitals by the list, and a publisher's name is
        // not a label : `LE MONDE` is shouting, and `LEMONDE.FR` is an address
        // nobody writes that way.
        .textCase(nil)
    }

    /// Singling a source out, in the words the collections page uses for it.
    ///
    /// The same words in the swipe and in the long press, since they are one
    /// action reached two ways, and never the words the star on an article
    /// wears : a reader who is told they are adding to their favourites in both
    /// places has been told the two are one thing, and they are not.
    @ViewBuilder
    private func favouriting(_ source: SidebarItem) -> some View {
        Button {
            guard case .feed(let id) = source.kind else { return }
            Task { await model.setFavourite(id, !source.isFavourite) }
        } label: {
            Label(
                source.isFavourite ? "Remove from favourite sources" : "Add to favourite sources",
                systemImage: source.isFavourite ? "star.slash" : "star"
            )
        }
        .tint(.yellow)
    }

    private func domain(of group: SidebarItem) -> String? {
        if case .group(let domain) = group.kind { domain } else { nil }
    }

    @ViewBuilder
    private func row(_ item: SidebarItem) -> some View {
        Button {
            go(to: item.kind)
        } label: {
            // A source wears no mark of its own. The mark is the publisher's
            // and stands once, at the head of the group ; a row here is a desk
            // of that publisher, and the views above are the application's own
            // and wear the application's symbols.
            if case .feed = item.kind {
                line(of: item)
            } else {
                Label {
                    line(of: item)
                } icon: {
                    Image(systemName: Self.icon(of: item.kind))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func line(of item: SidebarItem) -> some View {
        HStack {
            title(of: item)
            // The mark of a favourite source, where a reader reads the name :
            // it is a property of this source and not a column of its own, and
            // a column would be a column of blanks.
            if item.isFavourite {
                Image(systemName: "star.fill")
                    .font(Editorial.metadata)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel(Text("Favourite source"))
            }
            Spacer(minLength: 8)
            if item.unreadCount > 0 {
                Text(item.unreadCount, format: .number)
                    .font(Editorial.metadata)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func title(of item: SidebarItem) -> some View {
        switch item.kind {
        case .digest: Text("Digest")
        case .unread: Text("Unread")
        case .today: Text("Today")
        case .starred: Text("Starred articles")
        case .all: Text("All articles")
        case .group, .feed: Text(verbatim: item.title ?? "")
        }
    }

    private static func icon(of kind: SidebarItem.Kind) -> String {
        switch kind {
        case .digest: "sparkles.rectangle.stack"
        case .unread: "circle.inset.filled"
        case .today: "sun.max"
        case .starred: "star"
        case .all: "tray.full"
        case .group, .feed: "dot.radiowaves.up.forward"
        }
    }
}
