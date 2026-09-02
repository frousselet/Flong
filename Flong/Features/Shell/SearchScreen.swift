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

#if os(iOS)
    import UIKit
#endif

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
/// back, and at the foot of the page, directly above the field, what is worth
/// searching for this morning. Nothing here shows the whole stream, which every
/// other section already does and which nobody opened the search tab to read.
///
/// Its head is every other section's : a large title, the panels in the leading
/// corner and the reader's own menu opposite.
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
    #if os(iOS)
        /// Whether the software keyboard is up, which is what decides how much
        /// of the foot of the page the field is floating over. The system says
        /// so and nothing else can : a field is focused whether or not a
        /// keyboard was drawn for it, and a reader with one plugged in is
        /// focused with no keyboard at all.
        @State private var isKeyboardUp = false
    #endif

    /// How much of the foot of the page the search field floats over, once the
    /// keyboard is up.
    ///
    /// **A measurement, because there is nothing to ask.** With the keyboard
    /// down the field sits inside the bottom safe area and the page already
    /// stops above it ; with the keyboard up the field floats over the content,
    /// in no safe area at all, and nothing the page can ask says how tall it
    /// is. A bar put there is drawn behind it, and the keyboard's own accessory
    /// never attaches to a field a tab presents. So the page keeps this much of
    /// its foot clear, and only then.
    private static let fieldClearance: CGFloat = 56

    /// How far the search field stands from the edge of the window.
    ///
    /// **Measured, like the clearance, and for the same reason.** The subjects
    /// are the field's own furniture and have to start where it starts ; they
    /// stood in the column the rest of the application is set in, which is
    /// fourteen points further in, and a stack of pills indented from the field
    /// it belongs to reads as belonging to the page instead.
    private static let fieldInset: CGFloat = 8

    /// The air between the last subject and the field.
    ///
    /// Small on purpose : the subjects are what the field is about to be filled
    /// with, and a gap wide enough to read as a margin makes them furniture
    /// belonging to the page rather than to the field.
    private static let fieldAir: CGFloat = 12

    var body: some View {
        // **Two pages, not one page with two states.** A page of results is a
        // list that scrolls ; a page with no query is a page whose furniture
        // sits at the two ends of what is on screen, the searches at the top
        // and what is worth searching for at the bottom, just above the field.
        // One layout doing both was a layout doing neither.
        Group {
            if model.isShowingResults {
                results
            } else {
                opening
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollDismissesKeyboard(.interactively)
        // The same head as every other section : a large title that shrinks
        // into the bar as the reader scrolls into the page, the panels in one
        // corner and the reader's own menu in the other. Search used to carry
        // neither, on the theory that a reader who is searching is not
        // organizing ; what that actually did was make one section of four
        // look like a different application.
        .navigationTitle(Text("Search"))
        .toolbar {
            if let menu {
                ToolbarItem(placement: .sectionLeading) {
                    SourcesButton(model: model, open: menu)
                }
                ToolbarItem(placement: .sectionLeading) {
                    TopicsButton(model: model)
                }
                ToolbarItem(placement: .sectionLeading) {
                    NotificationsButton(model: model)
                }
                ReaderCorner(model: model, work: model.currentWork)
            }
        }
        .searchable(
            text: Binding(get: { model.searchText }, set: { model.searchText = $0 }),
            prompt: Text("Search your articles")
        )
        // **The head of the page stays put while the field is active.** The
        // system hides the navigation bar for as long as a search field is
        // presented, and this field is presented from the moment the reader
        // arrives : that left this one section of four with no title, no
        // panels and no reader's corner, which is not a search screen, it is a
        // different application. This is the modifier that asks for the
        // toolbar to be kept.
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .searchFocused($isTyping)
        .onSubmit(of: .search) { model.remember(model.searchText) }
        .overlay {
            if model.isShowingResults, model.summaries.isEmpty {
                ContentUnavailableView.search
            }
        }
        #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) {
                keyboard($0, isUp: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) {
                keyboard($0, isUp: false)
            }
        #endif
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

    /// The subjects, floating over the page for as long as there is a keyboard
    /// to float above.
    ///
    /// **They come and go with the keyboard.** They are what to type, and a
    /// reader who has put the keyboard away has stopped typing : the page is
    /// then theirs to read, and three pills standing over it are three pills
    /// in the way. They arrive from below and leave the same way, with the
    /// keyboard rather than after it, which is why the notification is what
    /// drives them and not a state change of the field's.
    ///
    /// On the Mac there is no keyboard to fold : the reader is always typing,
    /// so the subjects are always there.
    @ViewBuilder
    private var floating: some View {
        #if os(iOS)
            if isKeyboardUp {
                subjects
                    .editorialColumn()
                    .padding(.horizontal, Self.fieldInset)
                    .padding(.top, Self.fieldAir)
                    .padding(.bottom, Self.fieldClearance + Self.fieldAir)
                    .background(scrim)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        #else
            subjects
                .editorialColumn()
                .padding(.horizontal, Self.fieldInset)
                .padding(.top, Self.fieldAir)
                .padding(.bottom, Self.fieldAir)
                .background(scrim)
        #endif
    }

    #if os(iOS)
        /// Moves with the keyboard rather than after it.
        ///
        /// The notification says how long the system is taking, and taking the
        /// same time is the whole of what makes the two read as one movement :
        /// a duration of one's own is a stack of pills that arrives late or
        /// leaves early, whichever way the guess went.
        private func keyboard(_ notification: Notification, isUp: Bool) {
            let seconds = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
            withAnimation(.easeOut(duration: seconds ?? 0.25)) { isKeyboardUp = isUp }
        }
    #endif

    /// What a query answers.
    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                answered
                ForEach(model.summaries) { article in
                    ArticleRow(article: article, zoom: zoom) { read(article.id) }
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
    }

    /// The page before there is a query : what was searched for, and what is
    /// worth searching for.
    ///
    /// **The subjects are content and not a bar.** Every bar this page could
    /// hang them from is the bar the system draws the search field in once the
    /// keyboard is up, so a pinned row of pills is a row of pills behind the
    /// field ; the keyboard's own accessory never attaches to a search field a
    /// tab presents. What does work is what Photos does : the page is as tall
    /// as what is on screen, the searches sit at its head, and the subjects at
    /// its foot, which is directly above the field without anything having been
    /// pinned anywhere.
    private var opening: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { recents }
                .editorialColumn()
                .padding(.horizontal, 22)
        }
        // **Floating, not at the foot of the page.** They were the last thing
        // in the content, which is right for a page holding one or two past
        // searches and wrong for a page holding ten : the stack scrolled away
        // with the rest and passed behind the field. Pinned, they stay where
        // the reader is about to type, and the searches scroll behind them.
        //
        // The inset also reserves their height, so the last search can still
        // be scrolled clear of them.
        .safeAreaInset(edge: .bottom) { floating }
        .overlay {
            if model.recentSearches.isEmpty, model.searchSuggestions.isEmpty {
                ContentUnavailableView {
                    Label("Search", systemImage: "magnifyingglass")
                } description: {
                    Text("Say what you are looking for, in your own words.")
                }
            }
        }
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

    // MARK: - What is worth searching for

    /// What the subjects stand on.
    ///
    /// **A page passing sharply behind a pill is a pill you have to look
    /// twice at.** The subjects are held over a page that scrolls under them,
    /// and glass takes what is behind it : a headline running under a stack of
    /// them made three shapes hard to tell from the words they were sitting
    /// on. What is behind them fades into the page instead, over the top of
    /// the stack, so there is no edge anywhere.
    ///
    /// **The page's own colour, and nothing else.** A material was tried and
    /// is wrong : `.ultraThinMaterial` has a lightness of its own, so on a dark
    /// page it laid a pale film exactly where the page should have been
    /// darkest. A blur is only ever the right answer where what is behind it
    /// is worth a glimpse ; here what is behind it is a headline the reader is
    /// not reading, and the honest thing is for it to be gone.
    ///
    /// Edge to edge rather than under the pills alone : a wash that stopped
    /// where the widest pill stops would be a shape of its own, and one more
    /// thing on the page to explain.
    private var scrim: some View {
        Rectangle()
            .fill(theme.paper(in: scheme))
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.35),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }

    /// The subjects, stacked at the foot of the page.
    ///
    /// **Stacked rather than in a row.** A subject is a phrase and phrases are
    /// not the same length ; a row of them is a row that scrolls sideways, and
    /// a suggestion the reader has to go looking for is a suggestion that did
    /// not suggest anything. Three, on their own lines, left where the eye
    /// already is.
    @ViewBuilder
    private var subjects: some View {
        if !model.searchSuggestions.isEmpty {
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
            }
        }
    }

    /// What the search answered, and what it was read as answering.
    ///
    /// **A search that narrows itself has to say so.** A sentence naming a
    /// paper and a week is read as one, which is the whole point of typing a
    /// sentence, and a reader who was not told would see a third of the
    /// articles they expected and conclude the search was broken.
    ///
    /// At the head of the results rather than pinned over them : it is a fact
    /// about the search, read once, and the foot of this page belongs to the
    /// field.
    @ViewBuilder
    private var answered: some View {
        if !model.summaries.isEmpty {
            answer
                .font(.system(.footnote, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Editorial.tightRhythm)
        }
    }

    private var answer: Text {
        let understood = model.understood
        guard !understood.isEmpty else { return Text("\(model.summaries.count) results") }

        return Text("\(understood.joined(separator: " · ")) · \(model.summaries.count) results")
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
