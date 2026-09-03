//
//  ReaderPanel.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The reader's own panel : who they are, and the way to what only they answer.
///
/// **There is no account here and this is not one.** Section 3 says there is no
/// server and nothing to sign in to, and a name typed into a feed reader is not
/// an exception to that : the name and the picture are the reader's own, kept
/// in the reader's own iCloud beside their other preferences, and there is
/// nowhere for them to be sent. What they buy is that a device the reader picks
/// up looks like theirs, which is the whole of it.
///
/// **It was one column of every switch there is, and a column is not an
/// arrangement.** A face, two name fields, a town, three themes, the pool and
/// everything the pool drags with it, a repair, the sites, and at the foot the
/// command that deletes it all : eleven sections in one scroll, in the order
/// they happened to be written. A reader who came for the theme went past their
/// own name and the popular feeds to reach it, and a reader who came for
/// nothing at all was shown all of it.
///
/// **So the panel shows, and the pages set.** It opens on the reader : the
/// picture they chose at ninety-six points where they have chosen one, their
/// name under it, where they read from, and one quiet line saying when their
/// iCloud last agreed with this device. Not one thing on it can be changed, which is
/// what makes it readable at a glance. What can is behind the rows under it,
/// one per subject, each leading to a page holding all of that subject and
/// nothing else.
///
/// **And `About` stands alone at the foot**, in a card of its own : it is the
/// one row that is about the application rather than about the reader, and a
/// row that belongs to a different subject does not belong in the same card.
struct ReaderPanel: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            root
                .themed()
                .navigationDestination(for: ReaderPage.self) { page in
                    destination(page)
                        .themed()
                }
        }
        .presentationDetents([.height(height), .large])
        .presentationDragIndicator(.visible)
        .task { await model.loadSubscribedSites() }
        .themed()
    }

    /// How tall it opens.
    ///
    /// Taller than the three panels in the other corner, and for a reason of
    /// its own : those hold a list to scroll and open at a height a reader
    /// pulls from, this holds six rows and nothing else. A menu whose last row
    /// is under the fold is a menu hiding the one row nobody thinks to look
    /// for, and `About` is exactly that row.
    ///
    /// **It counts what is actually drawn.** Everything above the six rows is
    /// optional : the picture, the name, the town, and the one line about
    /// iCloud. A panel that stood at the height of all four would open on a
    /// hand's breadth of nothing under the last row for the reader who has
    /// none of them, and one that stood at the height of none would put `À
    /// propos` under the fold for the reader who has them all.
    private var height: CGFloat {
        /// The rows themselves, and the air around them.
        var height: CGFloat = 452
        if model.picture != nil { height += 126 }
        if model.name != nil { height += 32 }
        if model.place != nil { height += 28 }
        if synchronization != nil { height += 26 }
        return height
    }

    /// What the panel opens on, which is the reader and no control at all.
    private var root: some View {
        ScrollView {
            VStack(spacing: 24) {
                portrait
                cards
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .editorialColumn()
        }
        .scrollBounceBehavior(.basedOnSize)
        #if os(iOS)
            // **Untitled, where the three panels in the other corner are not.**
            // They are places a reader went to on purpose and a word says which
            // of the three arrived over the page. This one opens on the reader
            // themselves : nothing a title could say about who it is about
            // would say it better, and a bar drawn to hold no title is a bar
            // spent on nothing. The pages behind it carry theirs, as pages do.
            .toolbar(.hidden, for: .navigationBar)
        #endif
        #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { PanelDismiss() }
            }
        #endif
    }

    // MARK: - Who the reader is

    /// The reader, drawn rather than asked about.
    ///
    /// Everything here is optional and nothing is nagged at : a reader who has
    /// told the application nothing gets no face, no name, no town, and an
    /// application that works exactly as well. What is missing simply leaves no
    /// line behind it.
    ///
    /// **A picture, or nothing at all.** The mark in the corner has three
    /// states and needs all three, a button having to be somewhere for a thumb
    /// to land on ; this is a drawing on a page and has no such duty. The
    /// generic face at ninety-six points is a large portrait of nobody, and a
    /// reader who has typed a name has it set below in the theme's own headline
    /// face, which says who this is about better than two letters in a circle.
    ///
    /// **And it is given room.** It is the one picture on the page and the
    /// thing the panel opens on : air above and below is what makes it read as
    /// a portrait rather than as the first row of a list.
    private var portrait: some View {
        VStack(spacing: 8) {
            if model.picture != nil {
                ReaderMark(model: model, side: 96)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
            }

            // Verbatim : a person is called what they are called in every
            // language, and so is the town they live in.
            if let name = model.name {
                Text(verbatim: name)
                    .font(theme.headline(.title2))
                    .multilineTextAlignment(.center)
            }

            if let place = model.place {
                Text(verbatim: place.line)
                    .font(theme.standfirst(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            standing
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
    }

    /// The one line of fact under the face : whether the reader's other devices
    /// agree with this one.
    ///
    /// **A dateline rather than a dashboard.** It carried a count of the
    /// sources this device follows, which is a number nobody was asking : the
    /// reader who wants to know what they follow opens the sources, where the
    /// sources are. What is left is the one thing about this device that is
    /// said nowhere a reader would think to look.
    ///
    /// A device with no iCloud account says nothing at all. It is not doing
    /// anything wrong : section 3 has Flong working perfectly well on one
    /// device without one, and a line reporting the absence would be a reproach.
    @ViewBuilder
    private var standing: some View {
        if let synchronization {
            synchronization
                .font(theme.metadata)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    /// What the exchange with iCloud has to say, where it has anything.
    ///
    /// The same states the sources panel names, said in the same words, since
    /// two places describing one exchange differently is two places to keep
    /// true. Nothing at all where a reader can neither act on it nor care :
    /// no account, or an account this device has never yet spoken to.
    private var synchronization: Text? {
        switch model.syncStatus {
        case .unavailable:
            nil
        case .idle(let date):
            date.map { Text("Synchronized \($0, format: .relative(presentation: .named))") }
        case .working:
            Text("Synchronizing")
        case .waiting:
            Text("Waiting for iCloud")
        case .quotaExceeded:
            Text("iCloud storage is full")
        case .failed:
            Text("iCloud is not answering")
        }
    }

    // MARK: - The way to everything that is set

    /// The subjects, grouped by what they are about.
    ///
    /// Three cards and not one list : the reader themselves, then what they
    /// offer and are offered outside this device, then what the device and the
    /// iCloud behind it hold. A group of two is a group, and a rule between two
    /// rows that have nothing to do with each other is a rule saying nothing.
    private var cards: some View {
        VStack(spacing: 16) {
            card([.profile, .appearance])
            card([.popular, .sites])
            card([.data])
            card([.about])
        }
    }

    /// One card of rows, hairlined between them and nowhere else.
    private func card(_ pages: [ReaderPage]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(pages.enumerated()), id: \.element) { index, page in
                if index > 0 {
                    // Indented past the mark, so the rule separates the rows
                    // rather than cutting the card in half.
                    Divider().padding(.leading, 54)
                }
                row(page)
            }
        }
        .background(theme.surface(in: scheme), in: .rect(cornerRadius: 18))
    }

    /// One subject : its mark and its name, and nothing under either.
    ///
    /// **A row of a menu is a word, not a paragraph.** A line under each name
    /// explaining what was behind it made six rows into six small essays, and a
    /// reader looking for the theme read four of them to find it. The names are
    /// the words a reader already has for these things.
    private func row(_ page: ReaderPage) -> some View {
        NavigationLink(value: page) {
            HStack(spacing: 14) {
                Image(systemName: page.mark)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 24)

                Text(page.title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // An identifier beside the name, because the name is translated and a
        // test that looked for the English would pass here and fail on a
        // device set to the reader's own language.
        .accessibilityIdentifier(page.identifier)
    }

    /// The page one row leads to, each handed the panel's own way out.
    ///
    /// **A `DismissAction` read on a pushed page pops that page**, which is the
    /// right answer for a back button and the wrong one for the `Done` a Mac
    /// needs and for the moment everything has just been deleted. So the way out
    /// is handed down from here, where `dismiss` still means the sheet.
    @ViewBuilder
    private func destination(_ page: ReaderPage) -> some View {
        switch page {
        case .profile: ProfileSettings(model: model, close: close)
        case .appearance: AppearanceSettings(model: model, close: close)
        case .popular: PoolSettings(model: model, close: close)
        case .sites: SiteSettings(model: model, close: close)
        case .data: DataSettings(model: model, close: close)
        case .about: AboutScreen(close: close)
        }
    }

    private func close() {
        dismiss()
    }
}

/// The subjects the reader's panel leads to.
///
/// A case rather than a `NavigationLink` written out per row : a mark, a name,
/// a line and an identifier are four facts about one subject, and four facts
/// written at four call sites are four places to forget one.
enum ReaderPage: Hashable, CaseIterable {
    /// The reader's own face, name and town.
    case profile
    /// The face the page is set in, and the paper it is printed on.
    case appearance
    /// What they offer the other readers, and who they brought in.
    case popular
    /// The sites they pay for and are signed in to.
    case sites
    /// What this device and the reader's iCloud hold, down to taking it all
    /// back.
    case data
    /// The application itself, which is the one row here that is not about the
    /// reader.
    case about

    var title: LocalizedStringResource {
        switch self {
        case .profile: "Profile"
        case .appearance: "Appearance"
        case .popular: "Popular feeds"
        case .sites: "Subscribed sites"
        case .data: "Your data"
        case .about: "About"
        }
    }

    var mark: String {
        switch self {
        case .profile: "person.crop.circle"
        case .appearance: "paintpalette"
        case .popular: "person.2"
        case .sites: "key"
        case .data: "icloud"
        case .about: "info.circle"
        }
    }

    /// What a test presses, which is never a translated name.
    var identifier: String {
        switch self {
        case .profile: "reader-profile"
        case .appearance: "reader-appearance"
        case .popular: "reader-popular"
        case .sites: "reader-sites"
        case .data: "reader-data"
        case .about: "reader-about"
        }
    }
}
