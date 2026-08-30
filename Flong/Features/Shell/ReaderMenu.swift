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
                open(.topics)
            } label: {
                Label("Subjects", systemImage: "square.stack.3d.up")
            }

            Button {
                open(.subscribedSites)
            } label: {
                Label("Subscribed sites", systemImage: "key")
            }

            Button {
                open(.notifications)
            } label: {
                Label("Notifications", systemImage: "bell")
            }

            Divider()

            // The only way to ask for a refresh, and deliberately a deliberate
            // one. There is no pull anywhere : a gesture that is always under
            // the thumb invites being used, and a reader refreshing a wire
            // every few seconds is a reader their own reader has made anxious.
            // The page keeps itself up to date without being asked.
            Button {
                Task { await model.refreshAll() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isRefreshing)

            Button {
                Task { await model.rewriteDigest() }
            } label: {
                Label("Write the digest again", systemImage: "sparkles")
            }
            .disabled(model.isRewriting || OnDeviceModel.absence != nil)
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
