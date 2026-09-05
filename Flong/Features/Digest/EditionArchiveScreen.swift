//
//  EditionArchiveScreen.swift
//  Flong
//
//  Created by François Rousselet on 04/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The editions that have already come out.
///
/// **A back number is a whole page and not a longer list.** What the archive is
/// for is the reader who was away this morning : they want the page as it was,
/// with the name it was given and the ten stories it led on, and not the same
/// stories folded back into today's ranking. So an edition here is exactly what
/// it was, down to the headline over each story, frozen when it closed.
/// The panel the calendar in the corner opens.
///
/// A short sheet over the page, like the sources, the subjects and the notices,
/// and for the same reason : the reader picks a back number, reads it, and
/// comes back to the edition they were on. It carries a stack of its own, since
/// one of these does lead somewhere, and hands that stack the panel's own way
/// out : a `DismissAction` read on a pushed page pops the page rather than
/// closing the sheet it is in.
struct EditionsPanel: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var opened: [UUID] = []

    var body: some View {
        NavigationStack(path: $opened) {
            EditionArchiveScreen(model: model) { opened.append($0) }
                // What a test presses and reads, since every name here is
                // translated.
                .accessibilityIdentifier("edition-archive-list")
                .navigationDestination(for: UUID.self) { id in
                    EditionScreen(model: model, id: id) { _ in }
                        .toolbar { PanelDismiss { dismiss() } }
                }
                .toolbar { PanelDismiss() }
        }
        .presentationDetents([.height(Panel.tall), .large])
        .presentationDragIndicator(.visible)
    }
}

struct EditionArchiveScreen: View {
    let model: AppModel
    let open: (UUID) -> Void

    @Environment(\.theme) private var theme

    /// One back number, as a row : the two points the model put first, and how
    /// much the edition carried.
    ///
    /// The whole list would be one back number to a screenful. The first two are
    /// the ones the model put first, which are the ones it thought mattered ;
    /// the section above the row says which edition it is, so nothing here has
    /// to name it.
    ///
    /// **It ranked its two points before the front page did, and it stops having
    /// a private opinion about how.** It set the first in `headline` and the
    /// second in `subheadline`, in the system's own face, at a call site : the
    /// instinct was right and it is the shared drawing's now, so an archive row
    /// changes face with the theme like everything around it, and gains the
    /// subject marks it never had, which cost it no width now that they are
    /// inside the line.
    ///
    /// **And it cuts nothing.** It held each point to two lines, which was one
    /// of the places a point ended in an ellipsis. What keeps this row short is
    /// the bound on the writing. See ``EditionSummarizer/maximumPointWords``.
    ///
    /// No pane here. Glass on a list row is one piece of it per row, which is
    /// the card-per-point the pane exists instead of, at the scale of a whole
    /// screen, and it would be glass laid on a grouped background besides.
    private func row(_ published: PublishedEdition) -> some View {
        VStack(alignment: .leading, spacing: Editorial.tightRhythm) {
            EditionPoints(published: published, showing: 2)

            Text("\(published.stories.count) stories")
                .font(theme.metadata)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    var body: some View {
        List {
            ForEach(model.editionArchive) { published in
                Section {
                    Button {
                        open(published.edition.id)
                    } label: {
                        row(published)
                    }
                    .buttonStyle(.plain)
                    // What a test presses, since every name on the row is
                    // either translated or whatever the model wrote that day.
                    .accessibilityIdentifier("edition-row")
                } header: {
                    HStack(spacing: 6) {
                        Text(published.edition.slot.title)
                        Text(verbatim: "·")
                        Text(published.edition.openedAt, format: .dateTime.weekday(.wide).day().month())
                    }
                }
            }
        }
        .navigationTitle(Text("Editions"))
        .overlay {
            if model.editionArchive.isEmpty {
                ContentUnavailableView {
                    Label("No edition yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("An edition appears here once it has come out and been written.")
                }
            }
        }
    }
}

/// One back number, as it was.
///
/// The rows are the edition's own frozen heads rather than a read of the story
/// table : a purge that took an article shrinks a story and can tidy it away
/// altogether, and a page from last Tuesday that lost a row would be an archive
/// nobody could trust. Tapping one opens the story where the story is still
/// there ; where it is not, the headline is what is left of it, which is the
/// honest thing for an archive to hold.
struct EditionScreen: View {
    let model: AppModel
    let id: UUID
    let open: (UUID) -> Void

    @Environment(\.theme) private var theme

    private var published: PublishedEdition? {
        model.editionArchive.first { $0.edition.id == id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let published, !published.edition.points.isEmpty {
                    // **The same head as this morning's, and not a plainer copy
                    // of it.** It was drawn again here by hand, with a mark set
                    // at a different weight, a different gap after it, a
                    // different spacing between points and the same cap of
                    // three lines : a reader who opened yesterday's edition from
                    // the calendar met a plainer version of the same three
                    // sentences and nothing on the page explained why.
                    //
                    // **And the pane comes with it, which is not a fourth place
                    // for the material.** `docs/technical/interface.md` licenses
                    // it for the few points at the head of *an edition*, and
                    // this is the head of an edition, with ten stories of body
                    // type under it and the same problem of telling the page's
                    // own voice from the news. It reads plainer here and it
                    // should : the material resolves against the sheet's own
                    // paper rather than against the colour a lead photograph
                    // gives the front page, so what carries it here is its rim
                    // and its inset rather than what shows through it.
                    //
                    // **What does not come with it is the sinking.** A masthead
                    // held back against the scroll is right on a page the reader
                    // lives on ; in a half-height sheet opened to read one
                    // edition it would be gone before the sheet had finished
                    // presenting, and this screen writes no ``PageOffset`` for
                    // it to read.
                    EditionPoints(published: published)
                        .editionPane()
                        .padding(.top, Editorial.tightRhythm)
                        .padding(.bottom, Editorial.rhythm)
                }

                ForEach(published?.stories ?? [], id: \.position) { story in
                    Button {
                        open(story.storyID)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: story.title)
                                .font(theme.headline(.headline))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if let summary = story.summary {
                                Text(verbatim: summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .navigationTitle(published.map { Text($0.edition.slot.title) } ?? Text("Edition"))
    }
}
