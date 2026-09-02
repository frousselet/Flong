//
//  SearchScreen.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Search, where the system puts search.
///
/// Its own section rather than a field bolted to the front page : a query
/// language with fields, states and dates is a place a reader goes, not a
/// decoration on a page they were already reading.
///
/// **A section a reader goes to is a section that is ready for them.** The
/// cursor is in the field the moment they arrive, the keyboard is up, and the
/// page under it is about searching rather than about articles : what they
/// looked for before, which is the thing worth offering somebody who has come
/// back, and above the keyboard the words the language is made of. Nothing
/// here shows the whole stream, which every other section already does and
/// which nobody opened the search tab to read.
struct SearchScreen: View {
    let model: AppModel
    let zoom: Namespace.ID
    /// Whether the reader is in this section.
    ///
    /// It is what puts the cursor in the field, and it has to be asked rather
    /// than assumed : a tab is built once and kept, so appearing is something
    /// this view does on the first visit and on no other, while arriving is
    /// something the reader does every time.
    var isCurrent = true
    /// Where the reader's menu goes : the same corner as in every other section.
    var menu: ((Route) -> Void)?
    let open: (UUID) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @FocusState private var isTyping: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                name
                if model.isShowingResults {
                    ForEach(model.summaries) { article in
                        ArticleRow(article: article, zoom: zoom) { read(article.id) }
                    }
                } else {
                    recents
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        // And at the foot as well, which no other section needs : this is the
        // one page whose own content sits in the bottom safe area, and a count
        // with the page passing sharply through it is not a count anybody can
        // read.
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(Text("Search"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if menu != nil {
                ReaderCorner(model: model, work: model.currentWork)
            }
        }
        .searchable(
            text: Binding(get: { model.searchText }, set: { model.searchText = $0 }),
            prompt: Text("Search your articles")
        )
        .searchFocused($isTyping)
        .onSubmit(of: .search) { model.remember(model.searchText) }
        .overlay {
            if !model.isShowingResults, model.recentSearches.isEmpty {
                ContentUnavailableView {
                    Label("Search", systemImage: "magnifyingglass")
                } description: {
                    Text("Say what you are looking for, in your own words.")
                }
            } else if model.isShowingResults, model.summaries.isEmpty {
                ContentUnavailableView.search
            }
        }
        .safeAreaInset(edge: .bottom) { above }
        .task {
            model.selection = .all
            await model.loadArticles()
        }
        // Arriving is what puts the cursor in the field, and arriving happens
        // more than once. The pause is the field being installed : asked for
        // in the same turn the section becomes current, the focus lands on a
        // field the system has not put on screen yet and is quietly dropped.
        .task(id: isCurrent) {
            guard isCurrent else { return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            isTyping = true
        }
    }

    /// The name of the section, in the page rather than in a bar.
    ///
    /// **Because there is no bar.** The system hides the navigation bar for as
    /// long as a search field is presented, and this field is presented from
    /// the moment the reader arrives, so a page that left its name to
    /// ``navigationTitle`` would be a page with nothing at the top of it at
    /// all. The title stays declared for the Mac, where the field lives in the
    /// toolbar and the window says its own name.
    @ViewBuilder
    private var name: some View {
        #if os(iOS)
            Text("Search")
                .font(.system(.largeTitle, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .padding(.bottom, Editorial.tightRhythm)
                .accessibilityAddTraits(.isHeader)
        #endif
    }

    // MARK: - What the reader looked for before

    @ViewBuilder
    private var recents: some View {
        if !model.recentSearches.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(.system(.footnote, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Button("Clear") { model.forgetSearches() }
                    .font(.system(.footnote, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, Editorial.tightRhythm)
            .padding(.bottom, 2)

            ForEach(model.recentSearches, id: \.self) { query in
                RecentSearchRow(
                    query: query,
                    run: { run(query) },
                    forget: { model.forget(search: query) }
                )
            }
        }
    }

    // MARK: - What is offered above the keyboard

    /// What sits between the page and the search field.
    ///
    /// Two things, never both : what the query is answering, once there is a
    /// query, and what is worth searching for before there is one. A count and
    /// a stack of pills on top of each other would push the page a further line
    /// up every time the reader typed a character.
    ///
    /// **Stacked rather than in a row.** A subject is a phrase and phrases are
    /// not the same length ; a row of them is a row that scrolls sideways, and
    /// a suggestion the reader has to go looking for is a suggestion that did
    /// not suggest anything. Three, on their own lines, left where the eye
    /// already is.
    @ViewBuilder
    private var above: some View {
        if model.isShowingResults, !model.summaries.isEmpty {
            Text("\(model.summaries.count) results")
                .font(theme.metadata)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if !model.searchSuggestions.isEmpty {
            GlassEffectContainer(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.searchSuggestions, id: \.self) { subject in
                        Button {
                            take(subject)
                        } label: {
                            Text(verbatim: subject)
                                .font(.system(.body, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Doing what was asked

    /// Runs a search the reader had run before, and moves it back to the top.
    private func run(_ query: String) {
        model.searchText = query
        model.remember(query)
        isTyping = false
    }

    /// Searches for a subject the reader was offered.
    ///
    /// A whole search rather than half of one : a subject is what somebody
    /// would have typed, so taking it is the same as having typed it, keyboard
    /// down and results up.
    private func take(_ subject: String) {
        model.searchText = subject
        model.remember(subject)
        isTyping = false
    }

    /// Opens an article a search found.
    ///
    /// **The search is kept here rather than only on submit.** Results follow
    /// what is typed, so a reader who finds what they wanted never presses
    /// return, and a list of past searches fed by the return key alone would
    /// stay empty for exactly the readers it is for.
    private func read(_ article: UUID) {
        model.remember(model.searchText)
        open(article)
    }
}

/// One search the reader ran before.
///
/// The whole row runs it again ; the cross at the end drops it. Two controls
/// rather than a swipe, since this is a stack of rows in a scroll view and not
/// a list, and a gesture nothing on screen announces is a gesture nobody finds.
private struct RecentSearchRow: View {
    let query: String
    let run: () -> Void
    let forget: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: run) {
                Label {
                    Text(verbatim: query)
                        .font(.system(.body))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button(action: forget) {
                Image(systemName: "xmark")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Forget this search"))
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider() }
    }
}
