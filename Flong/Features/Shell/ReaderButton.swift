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
    /// Where a source leads, once the panel is out of the way.
    var open: ((SidebarItem.Kind) -> Void)?

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
            ReaderPanel(model: model, open: open)
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
    /// Where a source leads, once the reader's panel is out of the way.
    var open: ((SidebarItem.Kind) -> Void)?

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            WorkRingItem(model: model)
        }
        ToolbarItem(placement: .primaryAction) {
            ReaderButton(model: model, open: open)
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
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let picture = model.picture {
                Image(decorative: picture, scale: displayScale)
                    .resizable()
                    .scaledToFill()
            } else if let initials = model.initials {
                Text(verbatim: initials)
                    .font(.system(size: side * 0.42, weight: .semibold))
                    .foregroundStyle(theme.onAccent(in: scheme))
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

/// The way to the back numbers, in the corner of the digest.
///
/// **It was a line under the edition's own list**, `Éditions précédentes`,
/// which put a way *out* of the page in the middle of the page : the reader met
/// it between what this edition says and the first story it leads on, on the
/// way down to the news. A masthead does not carry its own archive.
///
/// It stands in the digest and nowhere else, which is the whole argument for
/// its being in a toolbar rather than in the reader's menu : that menu holds
/// what a reader tends everywhere, and a back number is about this page alone.
///
/// It carries the panel itself rather than a route : the reader picks an
/// edition, reads it, and comes back to the one they were on.
struct EditionsButton: View {
    let model: AppModel

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            Label("Editions", systemImage: "calendar")
        }
        // An identifier beside the name, because the name is translated and a
        // test that looked for the English would pass here and fail on a device
        // set to the reader's own language.
        .accessibilityIdentifier("edition-archive")
        .sheet(isPresented: $isOpen) {
            EditionsPanel(model: model)
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

/// The ring, reading the pass itself.
///
/// **It was handed the pass, and that is what cost the page.** A screen that
/// reads `currentWork` to pass it in is a screen subscribed to it, and the pass
/// moves on every feed fetched, every headline written, every article read : a
/// fetch of three hundred feeds was three hundred rebuilds of the front page,
/// its ten rows and its pinned header, to move a ring by a third of a per cent.
/// Reading it here puts the whole of that inside one small view.
private struct WorkRingItem: View {
    let model: AppModel

    var body: some View {
        if let work = model.currentWork {
            Button {
                // Nothing. It reports and does not act : the pull is the
                // gesture, and a control that did both would be one the reader
                // cannot aim.
            } label: {
                WorkRing(work: work)
            }
            .disabled(true)
            // What the ring cannot say in a shape, said in words to a pointer
            // resting on it.
            .help(Text(work.phase.title))
        }
    }
}
