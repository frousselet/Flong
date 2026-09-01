//
//  AuthorsScreen.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Everybody who signed something, in a line rather than in squares.
///
/// **The one square on the collections page that opens on people.** Every other
/// one opens on articles, and a grid is right for those : a square carries a
/// picture and a picture is what a reader recognizes a kept article by. A name
/// has no picture. What a reader does here is look somebody up, and looking a
/// name up in a list of names is what an alphabetical list is for.
///
/// **The favourites are a band of their own, at the top.** A reader who
/// singled out a dozen writers out of two thousand bylines would otherwise have
/// to find them again every time, which is the whole of what they were trying
/// to avoid. With no favourites there is no heading either : one plain list,
/// nothing labelled, exactly as the collections page draws a single band.
///
/// **The star is a button on the row and not only a swipe.** A swipe says
/// nothing until it is tried, exists on one platform of the three, and this is
/// the only way in to the favourite there is. The long press carries the same
/// action in words, for whoever reaches for it there.
struct AuthorsScreen: View {
    let model: AppModel
    /// Where a name leads : that writer's own page.
    let open: (String) -> Void

    @State private var search = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Headings only when there is something to tell apart. A reader
                // with no favourites is shown a list, not a list under a label
                // saying it is the rest of something.
                if favourites.isEmpty {
                    band(nil, of: others)
                } else {
                    band("Favourite authors", of: favourites)
                    band("All authors", of: others)
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(Text("Authors"))
        .searchable(text: $search, prompt: Text("Search authors"))
        .overlay {
            if model.authors.isEmpty {
                ContentUnavailableView {
                    Label("Nobody signed yet", systemImage: "person.2")
                } description: {
                    Text("Feeds that name who wrote an article put them here, and you can keep the ones you follow.")
                }
            } else if found.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .task { await model.loadAuthors() }
    }

    /// One band of names, which draws nothing at all when it holds nothing.
    @ViewBuilder
    private func band(_ title: LocalizedStringKey?, of authors: [Author]) -> some View {
        if !authors.isEmpty {
            Section {
                ForEach(authors) { author in
                    AuthorRow(author: author) {
                        open(author.name)
                    } favourite: {
                        Task { await model.setFavouriteAuthor(author.name, !author.isFavourite) }
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
    /// Matched the way a reader searches for a person, which is by any part of
    /// the name and without minding the accents : somebody looking for `Eluard`
    /// means Éluard, and a list that answered nothing would be telling them the
    /// writer is not there.
    private var found: [Author] {
        let wanted = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return model.authors }

        return model.authors.filter {
            $0.name.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private var favourites: [Author] { found.filter(\.isFavourite) }
    private var others: [Author] { found.filter { !$0.isFavourite } }
}

/// One writer, in a list of writers.
///
/// The count is what they signed on this device and not what they ever wrote,
/// so it is set in the metadata face beside the name rather than announced :
/// it says how much of them is here, which is a different claim.
struct AuthorRow: View {
    let author: Author
    let open: () -> Void
    let favourite: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 8) {
                    Text(verbatim: author.name)
                        .font(theme.headline(.body))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    // Nought is a real answer and says something : a writer the
                    // reader kept whose articles have all gone. It is left off
                    // rather than printed, since `0` beside a name reads as a
                    // failure of the page rather than as the state of the
                    // stream.
                    if author.count > 0 {
                        Text(author.count, format: .number)
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
            // Built out of the two pieces rather than written as one sentence,
            // so the count keeps the plural the rest of the application already
            // has and the name stays a name in every language.
            .accessibilityLabel(
                Text(verbatim: author.name) + Text(verbatim: ", ") + Text("\(author.count) articles")
            )

            Button(action: favourite) {
                Image(systemName: author.isFavourite ? "star.fill" : "star")
                    .foregroundStyle(author.isFavourite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                author.isFavourite
                    ? Text("Remove from favourite authors") : Text("Add to favourite authors")
            )
        }
        .contextMenu {
            Button(action: favourite) {
                Label(
                    author.isFavourite ? "Remove from favourite authors" : "Add to favourite authors",
                    systemImage: author.isFavourite ? "star.slash" : "star"
                )
            }
        }
        .overlay(alignment: .top) { Divider() }
    }
}
