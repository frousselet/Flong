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
struct EditionArchiveScreen: View {
    let model: AppModel
    let open: (UUID) -> Void

    var body: some View {
        List {
            ForEach(model.editionArchive) { published in
                Section {
                    Button {
                        open(published.edition.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            if let title = published.edition.title {
                                Text(verbatim: title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                            if let summary = published.edition.summary {
                                Text(verbatim: summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                            }
                            Text("\(published.stories.count) stories")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
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
                if let edition = published?.edition {
                    VStack(alignment: .leading, spacing: Editorial.tightRhythm) {
                        if let title = edition.title {
                            Text(verbatim: title)
                                .font(theme.headline(.title))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let summary = edition.summary {
                            (Text(Image(systemName: "sparkles")).foregroundStyle(.secondary)
                                + Text(verbatim: " ")
                                + Text(verbatim: summary))
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel(Text("Written by the model : \(summary)"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
