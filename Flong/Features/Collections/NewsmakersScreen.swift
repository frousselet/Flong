//
//  NewsmakersScreen.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Everybody the articles are about, in a line rather than in squares.
///
/// **The same shape as the writers, and it has to be.** A reader who has just
/// learnt that one square on this page opens on a list of names should not have
/// to learn it twice : the two directories are read as a pair, so they are
/// built as a pair. The alphabetical list, the band of favourites at the top,
/// the search field, the star on the row and the bell in the menu are the ones
/// ``AuthorsScreen`` has, and they mean the same thing here.
///
/// **What is different is what the count under a name is.** A writer's number
/// is what they signed ; a person's is how many articles are *about* them,
/// which is a number that moves with the news rather than with anybody's
/// output. Somebody in the middle of a story has forty and somebody nobody is
/// writing about has one.
///
/// **The list can be long, and it is meant to be.** A stream of a hundred
/// thousand articles names thousands of people, most of them once. That is what
/// the search field is for : a directory is not a thing to scroll through, it
/// is a thing to look somebody up in, and the favourites at the top are the
/// handful the reader comes back to.
struct NewsmakersScreen: View {
    let model: AppModel
    /// Where a name leads : that person's own page.
    let open: (String) -> Void

    @State private var search = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Headings only when there is something to tell apart, exactly
                // as on the writers' page.
                if favourites.isEmpty {
                    band(nil, of: others)
                } else {
                    band("Favourite newsmakers", of: favourites)
                    band("All newsmakers", of: others)
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(Text("Newsmakers"))
        .searchable(text: $search, prompt: Text("Search newsmakers"))
        .overlay {
            if model.newsmakers.isEmpty {
                ContentUnavailableView {
                    Label("Nobody named yet", systemImage: "person.crop.rectangle.stack")
                } description: {
                    // Two reasons a page here is empty, and neither is that
                    // something is broken : the articles have not been read
                    // yet, which is a job that finishes on its own, or nobody
                    // has been named often enough. The reader is told both.
                    Text(
                        "Flong reads the people out of the articles themselves, in the background. Somebody appears here once five articles have named them."
                    )
                }
            } else if found.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .task { await model.loadNewsmakers() }
    }

    /// One band of names, which draws nothing at all when it holds nothing.
    @ViewBuilder
    private func band(_ title: LocalizedStringKey?, of people: [Newsmaker]) -> some View {
        if !people.isEmpty {
            Section {
                ForEach(people) { person in
                    NewsmakerRow(newsmaker: person) {
                        open(person.name)
                    } favourite: {
                        Task { await model.setFavouriteNewsmaker(person.name, !person.isFavourite) }
                    } notify: {
                        Task { await model.setNotifications(!person.notifies, forNewsmaker: person.name) }
                    }
                }
            } header: {
                if let title { heading(title) }
            }
        }
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(.footnote, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Editorial.rhythm)
            .padding(.bottom, 6)
    }

    /// The names the search leaves, or all of them when nothing was typed.
    ///
    /// Matched by any part of the name and without minding the accents, which
    /// is how a reader looks a person up : somebody typing `Zelensky` means
    /// `Volodymyr Zelensky`, and somebody typing `eluard` means Éluard.
    private var found: [Newsmaker] {
        let wanted = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return model.newsmakers }

        return model.newsmakers.filter {
            $0.name.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private var favourites: [Newsmaker] { found.filter(\.isFavourite) }
    private var others: [Newsmaker] { found.filter { !$0.isFavourite } }
}

/// One person, in a list of people.
///
/// The count is how many articles this device holds about them, set in the
/// metadata face beside the name rather than announced : it says how much of
/// them is here, which is a claim about the stream and not about the person.
///
/// **The marks say which papers are writing about them.** A name on its own is
/// a name in a list of thousands ; the same name with `Le Monde` and
/// `Libération` after it places the person and says something the directory
/// exists to say : who is covering this, and who is not. A story carried by one
/// paper and a story carried by six look different at a glance.
struct NewsmakerRow: View {
    let newsmaker: Newsmaker
    let open: () -> Void
    let favourite: () -> Void
    let notify: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.publishers) private var publishers

    /// How many marks a row has room for, and the writers' number for the same
    /// reasons : a hint of where, and never an inventory of it.
    private static let marks = 4

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 8) {
                    Text(verbatim: newsmaker.name)
                        .font(theme.headline(.body))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    marks

                    Spacer(minLength: 8)

                    // Nought is a real answer and says something : somebody the
                    // reader kept whose articles have all been purged. It is
                    // left off rather than printed, since `0` beside a name
                    // reads as a failure of the page.
                    if newsmaker.count > 0 {
                        Text(newsmaker.count, format: .number)
                            .font(theme.metadata)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            // Built out of the pieces rather than written as one sentence, so
            // the count keeps the plural the rest of the application has and
            // the name stays a name in every language.
            .accessibilityLabel(
                ([newsmaker.name, String(localized: "\(newsmaker.count) articles")] + named)
                    .joined(separator: ", ")
            )

            Button(action: favourite) {
                Image(systemName: newsmaker.isFavourite ? "star.fill" : "star")
                    .foregroundStyle(newsmaker.isFavourite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                newsmaker.isFavourite
                    ? Text("Remove from favourite newsmakers") : Text("Add to favourite newsmakers")
            )
        }
        .contextMenu {
            Button(action: favourite) {
                Label(
                    newsmaker.isFavourite ? "Remove from favourite newsmakers" : "Add to favourite newsmakers",
                    systemImage: newsmaker.isFavourite ? "star.slash" : "star"
                )
            }

            // In the menu and not beside the star, exactly as on a writer's
            // row : being told about somebody is a standing request to be
            // interrupted, and one made by a mis-tap is one the reader would
            // have to work out the cause of.
            Button(action: notify) {
                Label(
                    newsmaker.notifies ? "Stop notifying articles about them" : "Notify every article about them",
                    systemImage: newsmaker.notifies ? "bell.slash" : "bell"
                )
            }
        }
        .overlay(alignment: .top) { Divider() }
    }

    /// The marks of the publishers writing about them, the ones the row has
    /// room for.
    @ViewBuilder
    private var marks: some View {
        if !newsmaker.publishers.isEmpty {
            HStack(spacing: 4) {
                ForEach(newsmaker.publishers.prefix(Self.marks), id: \.self) { domain in
                    SourceIconView(identity: publishers[domain], side: 14)
                }
            }
        }
    }

    /// What those publishers are called, for a reader who is listening.
    private var named: [String] {
        newsmaker.publishers.prefix(Self.marks).map { publishers[$0]?.name ?? $0 }
    }
}
