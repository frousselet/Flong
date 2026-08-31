//
//  ReaderMenu.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The reader's own menu, in the same corner of every section.
///
/// It used to sit in the digest alone, which made it the digest's menu rather
/// than the reader's : what it holds belongs to the person and not to the page,
/// and a thing that belongs to the person is in the same place wherever they
/// are. One button, top trailing, in all four sections.
///
/// Not an account. There is no account, nothing here belongs to anyone but the
/// person holding the device, and the face on the button is the reader's own
/// picture rather than a sign that they are signed in to something.
///
/// The sources are not in it. They were, and they were the one thing in it a
/// reader opens often : a thing opened often is a button, not a line in a menu.
/// They sit in the opposite corner instead, where ``SourcesButton`` puts them.
///
/// The notices are not in it either, nor the subjects, and for the other half
/// of the same reason. Neither is opened often, but what a reader does in both
/// is said about the page they are looking at : they answer one question, or
/// nudge a subject and watch the page take it, and go back to reading. A line
/// in a menu leading to a whole screen is a poor shape for that, however rarely
/// it is done. ``NotificationsButton`` and ``TopicsButton`` stand beside the
/// sources and open panels over the page.
struct ReaderMenu: View {
    let model: AppModel
    let open: (Route) -> Void

    var body: some View {
        Menu {
            Button {
                open(.profile)
            } label: {
                Label {
                    if let name = model.name {
                        Text(verbatim: name)
                    } else {
                        Text("Your profile")
                    }
                } icon: {
                    Image(systemName: "person.crop.circle")
                }
            }

            Divider()

            Button {
                open(.subscribedSites)
            } label: {
                Label("Subscribed sites", systemImage: "key")
            }

            Divider()

            // Asking for a refresh from anywhere in the application, and the
            // only way to ask on a Mac, which has no pull. The front page has
            // the gesture as well ; this is the same work, reachable from the
            // sections that do not. The page keeps itself up to date without
            // either of them.
            Button {
                Task { await model.refreshAll() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isRefreshing)

            #if DEBUG
                // A development command, and only there. The engine decides
                // when to send and when to fetch and is right far more often
                // than a button would be : this is for watching an exchange
                // happen on demand while something is being built. It forgets
                // the change tokens, the tags the server gave each record and
                // the archives already read, then sends and fetches the whole
                // of the zone, which is the repair path and spends the record
                // budget of section 7 in one go. That is why it does not ship.
                Button {
                    Task { await model.forceSynchronization() }
                } label: {
                    Label("Force a synchronization", systemImage: "arrow.trianglehead.2.clockwise")
                }
            #endif
        } label: {
            ReaderMark(model: model)
        }
        .accessibilityLabel(Text("Settings"))
    }
}

/// The reader, as one small round thing.
///
/// Three states, in the order a reader arrives at them : the picture they
/// chose, the initials of the name they typed, and the generic face of somebody
/// who has told the application nothing about themselves. The third is not a
/// failure and is not nagged at : a reader who never opens the profile is a
/// reader for whom Flong works exactly as well.
struct ReaderMark: View {
    let model: AppModel
    var side: CGFloat = 26

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let picture = model.picture {
                Image(decorative: picture, scale: displayScale)
                    .resizable()
                    .scaledToFill()
            } else if let initials = model.initials {
                Text(verbatim: initials)
                    .font(.system(size: side * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Circle().fill(.tint))
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: side * 0.9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

/// The way to the sources, in the corner opposite the reader's own menu.
///
/// One press rather than two. Everything else the menu holds is opened once in
/// a while and reasoned about ; the sources are opened to add a feed, to read
/// one on its own, or to see what the machinery is doing, which is often
/// enough to be worth a corner of its own.
///
/// The three sections a reader reads in carry it. Search does not : its bar
/// belongs to the field, and a reader who is searching is not organizing.
struct SourcesButton: View {
    let open: (Route) -> Void

    var body: some View {
        Button {
            open(.sources)
        } label: {
            Label("Sources", systemImage: "square.stack")
        }
    }
}

/// The way to what Flong may interrupt the reader for, beside the sources.
///
/// **It was a line in the reader's menu and is a button now.** Not because it
/// is opened often, which it is not, but because of the shape of what a reader
/// does there : they answer one question about being interrupted and go back to
/// reading. Two presses to reach a whole screen with a way back on it is the
/// wrong shape for that, however rarely it is done.
///
/// It carries the panel itself rather than a route. Everything else in the
/// leading corner leads somewhere and comes back ; this opens over the page and
/// closes onto it, so there is nothing for a navigation stack to hold.
struct NotificationsButton: View {
    let model: AppModel

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            Label("Notifications", systemImage: "bell")
        }
        .sheet(isPresented: $isOpen) {
            NotificationsPanel(model: model)
        }
    }
}

/// The way to every subject there is, beside the notices.
///
/// **The pills are the other half of this.** A reader forms an opinion about a
/// subject while they are looking at the page it sorted, and saying it there
/// costs one press. What the pills cannot hold is the subjects that have fallen
/// off the page, and a preference nobody can find is a preference nobody can
/// undo : this is where the whole list lives.
///
/// So it opens over the page rather than in place of it. Nudging a subject is
/// said about the page behind the panel, and a screen pushed onto a stack put
/// that page out of sight for the whole of it.
struct TopicsButton: View {
    let model: AppModel

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            Label("Subjects", systemImage: "circle.grid.2x2")
        }
        .sheet(isPresented: $isOpen) {
            TopicsPanel(model: model)
        }
    }
}

nonisolated extension ToolbarItemPlacement {
    /// The corner opposite the reader's own menu.
    ///
    /// The two platforms name it differently and neither will answer to the
    /// other's name : `topBarLeading` is declared on macOS and marked
    /// unavailable there, and a Mac window's leading edge is `navigation`.
    static var sectionLeading: ToolbarItemPlacement {
        #if os(iOS)
            .topBarLeading
        #else
            .navigation
        #endif
    }
}
