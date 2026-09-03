//
//  ReaderButton.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The reader's own panel, in the same corner of every section.
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
/// **It was a menu and is a panel now**, like the three in the other corner. A
/// menu of lines leading to screens is the wrong shape for what is behind them:
/// a name and a face, and the sites the reader pays for, are things they set
/// and come straight back from. ``ReaderPanel`` is what it opens.
///
/// The sources are not in it, nor the subjects, nor the notices. They belong to
/// the page rather than to the person, and they have a corner of their own.
struct ReaderButton: View {
    let model: AppModel

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            ReaderMark(model: model)
        }
        .accessibilityLabel(Text("Settings"))
        // An identifier beside the label, because the label is translated and
        // a test that looked for `Settings` would pass in English and fail on
        // the reader's own device. An identifier is not a string the reader
        // ever sees and is not in the catalogue.
        .accessibilityIdentifier("reader")
        .sheet(isPresented: $isOpen) {
            ReaderPanel(model: model)
        }
    }
}

/// The reader's own corner, and what the machinery is doing beside it.
///
/// Two items rather than one, so that the ring is there only while there is
/// something to say. A place kept for it permanently is a hole in the bar of
/// every section for a measure that runs a few seconds an hour.
///
/// **The pass is read by the page and handed down.** The ring moves with every
/// batch that lands, and a toolbar that went and asked the model for it would
/// be a toolbar nothing tells when the answer changes : the section reads it in
/// its own body, where the observation is, and passes it in.
///
/// One corner for the whole application. The reader's button is in the same
/// place in every section, so the one measure of what Flong is doing is in the
/// same place too, rather than on the front page alone as the band it replaces
/// was.
struct ReaderCorner: ToolbarContent {
    let model: AppModel
    /// The pass as it stands, or nothing at all when nothing is running.
    let work: WorkPlan?

    var body: some ToolbarContent {
        if let work {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // Nothing. It reports and does not act : the pull is the
                    // gesture, and a control that did both would be one the
                    // reader cannot aim.
                } label: {
                    WorkRing(work: work)
                }
                .disabled(true)
                // What the ring cannot say in a shape, said in words to a
                // pointer resting on it.
                .help(Text(work.phase.title))
            }
        }
        ToolbarItem(placement: .primaryAction) {
            StatisticsButton(model: model)
        }
        ToolbarItem(placement: .primaryAction) {
            ReaderButton(model: model)
        }
    }
}

/// The way to what the reader's stream adds up to, beside the reader themselves.
///
/// **In this corner rather than the other one.** The corner opposite holds what
/// a reader tends : the sources they follow, the subjects they nudge, what
/// Flong may interrupt them for. Nothing here is tended. It is a page about the
/// person and their reading, in the same sense as the face beside it, and it
/// belongs where the rest of what is theirs already is.
///
/// A chart for a mark, since what it opens is chart-shaped and there is no
/// glyph for arithmetic. Beside the face and not behind it : a figure nobody
/// can find is a figure nobody reads, and two presses is where a page like this
/// goes to be forgotten.
struct StatisticsButton: View {
    let model: AppModel

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            Label("Statistics", systemImage: "chart.pie")
        }
        .accessibilityIdentifier("statistics")
        .sheet(isPresented: $isOpen) {
            StatisticsPanel(model: model)
        }
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
/// It opens a panel like the two beside it. A reader who picks a source is
/// going somewhere, so the panel goes and the page they asked for arrives
/// behind it : a screen that stayed on the stack behind every feed they opened
/// would be a way back nobody asked for.
///
/// The three sections a reader reads in carry it. Search does not : its bar
/// belongs to the field, and a reader who is searching is not organizing.
struct SourcesButton: View {
    let model: AppModel
    let open: (Route) -> Void

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            Label("Sources", systemImage: "square.stack")
        }
        .sheet(isPresented: $isOpen) {
            SourcesPanel(model: model) { kind in open(.view(kind)) }
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
        .accessibilityIdentifier("notifications")
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
