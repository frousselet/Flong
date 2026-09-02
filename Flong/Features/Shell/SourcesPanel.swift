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
    @Environment(\.theme) private var theme

    /// The publisher whose name is being written, and what is being written.
    @State private var renaming: String?
    @State private var renamed = ""
    /// What the reader has asked to delete, and whether they are being asked
    /// whether they meant it.
    ///
    /// **Two pieces of state rather than one optional**, and the reason is the
    /// dismissal : the alert stays on screen for the length of its animation
    /// after the binding that presented it has gone false, so an alert whose
    /// words were read off that same optional would spend the animation saying
    /// `Supprimer ?` about nothing. What is being deleted is put down when the
    /// next thing is picked up, not when the alert closes.
    @State private var deleting: Deletion?
    @State private var isDeleting = false
    /// What is standing over the panel, if anything is.
    @State private var presented: Presentation?
    @State private var isChoosingFile = false

    /// What the panel can put over itself.
    ///
    /// **One state and one sheet, rather than one of each per screen.** Several
    /// `sheet` modifiers on a single view is the shape SwiftUI is least
    /// reliable about : which of them answers is not something to be found out
    /// in the field, and a reader whose screen simply does not open has no way
    /// to report anything but that.
    ///
    /// The source is carried whole rather than fetched by the sheet, so what
    /// opens is the source rather than a blank that fills in a moment later.
    private enum Presentation: Identifiable, Hashable {
        case addingFeed
        case editing(Feed)

        var id: String {
            switch self {
            case .addingFeed: "adding"
            case .editing(let feed): "editing-\(feed.id)"
            }
        }
    }

    /// A source or a publisher, on its way out.
    ///
    /// The name is carried rather than looked up again : by the time the alert
    /// is answered the row it came from may already be gone.
    private struct Deletion: Hashable {
        let kind: SidebarItem.Kind
        let title: String

        /// Whether it is a whole publisher rather than one of its desks.
        var isPublisher: Bool { if case .group = kind { true } else { false } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head

            List {
                ForEach(model.sourceGroups) { group in
                    Section {
                        ForEach(group.children) { source in
                            row(source)
                                .swipeActions(edge: .leading) { favouriting(source) }
                                // The destructive one on the trailing edge, where
                                // the system puts a deletion and where a reader
                                // already expects to find one. It asks before it
                                // acts, so the swipe cannot cost them a source.
                                .swipeActions(edge: .trailing) { deleting(source) }
                                .contextMenu {
                                    favouriting(source)
                                    announcing(source)
                                    editing(source)
                                    deleting(source)
                                }
                        }
                    } header: {
                        heading(of: group)
                    }
                }

                status
            }
            .scrollContentBackground(.hidden)
            .themedRows()
            .overlay {
                if model.isEmpty {
                    ContentUnavailableView {
                        Label("No feed yet", systemImage: "dot.radiowaves.up.forward")
                    } description: {
                        Text("Add a feed, or import an OPML file to bring your subscriptions over.")
                    } actions: {
                        Button("Add a feed") { presented = .addingFeed }
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
        // **It asks, and it names what goes.** Everything else this panel does
        // is undoable by doing it again : a name comes back off a publisher, a
        // favourite is unstarred. This does not, and the articles it takes
        // include the ones the reader singled out, so the sentence says that
        // before the button does it rather than warning in the abstract.
        .alert(
            Text("Delete \(deleting?.title ?? "")?", comment: "The name of a source or of a publisher"),
            isPresented: $isDeleting,
            presenting: deleting
        ) { deletion in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await delete(deletion) }
            }
        } message: { deletion in
            if deletion.isPublisher {
                Text(
                    "Every source under it goes, and their articles with them, including the ones you starred, wrote on or filed. This cannot be undone."
                )
            } else {
                Text(
                    "Its articles go with it, including the ones you starred, wrote on or filed. This cannot be undone."
                )
            }
        }
        // The two ways in, presented over the panel rather than behind it. They
        // belong to what the reader is doing here, and a panel that had to be
        // dismissed before either could open would be asking them to put the
        // list away in order to add to it.
        .sheet(item: $presented) { presentation in
            switch presentation {
            case .addingFeed:
                AddFeedView(
                    add: { address in await model.addFeed(at: address) },
                    addPrivate: { address in await model.addPrivateFeed(at: address) }
                )
                .themed()
            case .editing(let source):
                SourceEditor(model: model, feed: source)
                    .themed()
            }
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: OPMLDocument.types) { result in
            guard case .success(let url) = result else { return }
            Task { await model.importOPML(from: url) }
        }
        .themed()
    }

    /// What the panel is, the two ways to add a source, and the way out on the
    /// platform that needs one.
    private var head: some View {
        HStack(spacing: 14) {
            Text("Sources")
                .font(theme.headline(.title3))

            Spacer(minLength: 8)

            Menu {
                Button {
                    presented = .addingFeed
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
    /// **The bar says it too now, and that is not the bar this refuses.**
    /// What is refused here is something permanent, under the reading, saying
    /// nothing most of the time. ``WorkRing`` stands beside the reader's own
    /// button while a phase is actually running and goes the moment it is over.
    /// A reader reported not knowing whether the page in front of them was
    /// current, which is a question this screen could only answer if they
    /// thought to come and ask it.
    ///
    /// What is said in both places comes from the same ``WorkPhase``, so the two
    /// cannot come to describe one pass differently. What stays here alone is
    /// what the reader has to act on : a full iCloud, a refusal, the offer to
    /// finish an import now. None of that belongs in a measure that disappears.
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
            deleting(group)
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
                if group.articleCount > 0 {
                    Text(group.articleCount, format: .number)
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

    /// Asking to be told about a source, or asking to stop.
    ///
    /// **In the menu and not in a swipe.** A swipe is for the two things a
    /// reader does often and reverses instantly, and this is neither : it is a
    /// standing request for a source to interrupt them, and one made by
    /// accident is one they would have to work out the cause of.
    ///
    /// Beside the favourite, and never the same words as it. A favourite source
    /// is one the reader wants near the top of their lists ; this is one they
    /// want to hear from, and a reader who read the two as one thing would end
    /// up with a notification for every source they like.
    ///
    /// The permission is asked by what this calls, at the moment it is called,
    /// and a refusal writes nothing.
    @ViewBuilder
    private func announcing(_ source: SidebarItem) -> some View {
        Button {
            guard case .feed(let id) = source.kind else { return }
            Task { await model.setNotifications(!source.notifies, forSource: id) }
        } label: {
            Label(
                source.notifies ? "Stop notifying new articles" : "Notify every new article",
                systemImage: source.notifies ? "bell.slash" : "bell"
            )
        }
    }

    /// Changing what a source is, which is the one thing in this panel that
    /// used to be impossible.
    ///
    /// **In the source's own menu, above the two things that are about its
    /// address and its removal**, since a reader who wants to correct anything
    /// at all about a source looks here first. What it opens holds the name,
    /// the address, the site, how often it is asked and whether it is one of
    /// the reader's own, and it is where the address parameters are reached
    /// from too : a menu is a list of what can be done, and a screen is where
    /// it is done.
    @ViewBuilder
    private func editing(_ source: SidebarItem) -> some View {
        if case .feed(let id) = source.kind {
            Button {
                Task {
                    guard let feed = await model.source(id) else { return }
                    presented = .editing(feed)
                }
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
    }

    /// Taking a source, or a whole publisher, away for good.
    ///
    /// The same button in the swipe, in the long press and in the heading's
    /// menu, since they are one action reached three ways. None of them acts :
    /// each one asks, and the alert is where it happens, so a swipe that went
    /// further than the reader meant costs them a tap and not a publisher.
    @ViewBuilder
    private func deleting(_ item: SidebarItem) -> some View {
        Button(role: .destructive) {
            deleting = Deletion(kind: item.kind, title: item.title ?? "")
            isDeleting = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func delete(_ deletion: Deletion) async {
        switch deletion.kind {
        case .feed(let id): await model.unsubscribe(id)
        case .group(let domain): await model.unsubscribe(fromPublisher: domain)
        // The fixed views are not sources and carry none of this.
        default: break
        }
    }

    private func domain(of group: SidebarItem) -> String? {
        if case .group(let domain) = group.kind { domain } else { nil }
    }

    /// One desk of one publisher, which is the only kind of row the list holds.
    ///
    /// **A source wears no mark of its own.** The mark is the publisher's and
    /// stands once, at the head of the group ; a row here is a desk of that
    /// publisher, and a favicon repeated down six desks is one column saying
    /// the same thing six times over.
    private func row(_ item: SidebarItem) -> some View {
        Button {
            go(to: item.kind)
        } label: {
            line(of: item)
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
                    .font(theme.metadata)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel(Text("Favourite source"))
            }
            Spacer(minLength: 8)
            // What that desk has given the reader. A source that has given
            // them nothing shows no `0` : a nought beside a name reads as a
            // failure of the page rather than as the state of the stream.
            if item.articleCount > 0 {
                Text(item.articleCount, format: .number)
                    .font(theme.metadata)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Verbatim : a source is called what its publisher calls it, or what the
    /// reader wrote over it.
    private func title(of item: SidebarItem) -> Text {
        Text(verbatim: item.title ?? "")
    }
}
