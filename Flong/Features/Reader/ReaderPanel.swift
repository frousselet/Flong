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
    /// Where a source leads, once the panel is out of the way.
    ///
    /// `nil` where there is nowhere to go : a feed opened from inside a feed
    /// has no sidebar to send the reader back to, and the row is not offered.
    var open: ((SidebarItem.Kind) -> Void)?

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
    /// Taller than a panel holding a list, and for a reason of its own : one
    /// of those opens at a height a reader pulls from, and this holds rows and
    /// nothing else. A menu whose last row is under the fold is a menu hiding
    /// the one row nobody thinks to look for, and `À propos` is exactly that
    /// row.
    ///
    /// **It counts what is actually drawn.** Everything above the six rows is
    /// optional : the picture, the name, the town, and the one line about
    /// iCloud. A panel that stood at the height of all four would open on a
    /// hand's breadth of nothing under the last row for the reader who has
    /// none of them, and one that stood at the height of none would put `À
    /// propos` under the fold for the reader who has them all.
    private var height: CGFloat {
        /// The rows themselves, and the air around them. Eleven of them now,
        /// and the four cards' worth of air between them.
        var height: CGFloat = 452 + 6 * 56 + 16
        if model.picture != nil { height += 126 }
        if model.name != nil { height += 32 }
        if model.place != nil { height += 28 }
        if synchronization != nil { height += 26 }
        return height
    }

    /// What the panel opens on, which is the reader and no control at all.
    private var root: some View {
        ScrollView {
            // **What the machinery is doing, at the head and nowhere else.** It
            // was a ring in the corner of every section, which put a measure
            // that runs a few seconds an hour in the bar of every page all day.
            // This is where a reader comes to ask what Flong is up to, so it is
            // where the answer is : a line of words over a rule that fills, in
            // the room it opens for itself and gives straight back.
            //
            // Outside the stack below rather than in it : a stack's spacing is
            // paid whether or not its first child has any height, and this one
            // has none most of the time.
            VStack(spacing: 0) {
                ActivityLine(work: model.currentWork)

                VStack(spacing: 24) {
                    portrait
                    cards
                }
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
    /// Cards and not one list : what the reader tends, then the reader
    /// themselves, then what they offer and are offered outside this device,
    /// then what the device and the iCloud behind it hold. A group of two is a
    /// group, and a rule between two rows that have nothing to do with each
    /// other is a rule saying nothing.
    ///
    /// **What they tend comes first, and it used to be three buttons in the
    /// opposite corner.** The sources, the subjects and the notices each had a
    /// glyph of their own beside the page, which is four controls in a corner
    /// before the page has said anything : a toolbar is not a menu, and a
    /// reader looking for one of them was reading glyphs. They are rows here,
    /// named in words, in the one place a reader already looks for what is
    /// theirs.
    ///
    /// The sources row is offered only where there is somewhere for a source to
    /// lead. A feed opened from inside a feed has no sidebar to send the reader
    /// back to.
    private var cards: some View {
        VStack(spacing: 16) {
            card(open == nil ? [.subjects, .notifications] : [.sources, .subjects, .notifications])
            card([.statistics, .profile, .appearance, .editions])
            card([.popular, .sites, .models])
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
        case .sources:
            SourcesPanel(model: model, open: open ?? { _ in }, close: close)
        case .subjects:
            TopicsPanel(model: model)
        case .notifications:
            NotificationsPanel(model: model)
        case .statistics: StatisticsPanel(model: model)
        case .profile: ProfileSettings(model: model, close: close)
        case .appearance: AppearanceSettings(model: model, close: close)
        case .editions: EditionSettings(model: model)
        case .popular: PoolSettings(model: model, close: close)
        case .sites: SiteSettings(model: model, close: close)
        case .models: ModelSettings(model: model, close: close)
        case .providerCalls: ProviderCallsScreen(model: model, close: close)
        case .data: DataSettings(model: model, close: close)
        case .about: AboutScreen(close: close)
        }
    }

    private func close() {
        dismiss()
    }
}

/// What the machinery is doing, as a line of words over a rule that fills.
///
/// **The shape the reader asked for, back where they can find it.** The pass
/// was drawn as a ring in the toolbar for a while : one small round thing in
/// the corner of every section, which says how far along something is and
/// cannot say what. A bar has room for both, and the reader's own panel is the
/// place a person goes to ask what the application is doing, so a measure that
/// runs a few seconds an hour belongs there rather than in the bar of every
/// page all day.
///
/// It reads ``AppModel/currentWork`` through whoever hands it in : the panel is
/// already subscribed to the model, and a pass moves on every feed fetched and
/// every headline written.
private struct ActivityLine: View {
    let work: WorkPlan?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    /// How tall the band is while there is something in it.
    ///
    /// The line of type over its rule, and the air under it that keeps it off
    /// the reader's own portrait. It follows the type size, since what sits in
    /// it is one line of type over a rule inside a capsule.
    ///
    /// Nought the rest of the time : a place kept permanently is a strip of
    /// nothing at the head of a panel opened many times a day, for a measure
    /// that runs a few seconds an hour.
    @ScaledMetric(relativeTo: .caption) private var open: CGFloat = 56

    /// What the band is worth right now.
    private var height: CGFloat { work == nil ? 0 : open }

    var body: some View {
        ZStack(alignment: .top) {
            if let work {
                content(work)
                    // Glass of its own rather than a slab of the panel's ground
                    // running the full width : a band of opaque paper reads as a
                    // shelf bolted to the top of the sheet, and this is a
                    // control floating over it, which is the layer the material
                    // is for.
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
                    // **It grows out of the top rather than materializing.** A
                    // fade on its own put the capsule on screen at full size in
                    // a band that was still opening, which reads as a thing
                    // arriving from nowhere over a panel that has not made room
                    // for it yet. Anchored at the top, it comes up out of the
                    // edge the room is opening from, which is the same motion
                    // the band is making.
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // **It takes the room it needs and gives it back.** The height is what
        // is animated rather than the row's presence, since a stack measuring a
        // child that has just been inserted lands on the answer a frame late
        // and that frame is the jolt.
        //
        // **And it is not clipped to that height.** Glass casts a soft shadow,
        // and a rectangular clip cuts it off where it is still dark : what that
        // leaves is a grey oblong with hard edges behind a capsule with round
        // ones. Unclipped, the capsule spills a little during the third of a
        // second it is growing or shrinking, which the fade over exactly the
        // same third of a second covers.
        .frame(height: height, alignment: .top)
        .animation(reduceMotion ? nil : .snappy(duration: 0.32), value: height)
        // The same curve and the same third of a second for the capsule's own
        // coming and going, so the room and the thing in it move together : two
        // animations of different lengths on one event is a capsule that lands
        // before the space exists or hangs about after it has gone.
        .animation(reduceMotion ? nil : .snappy(duration: 0.32), value: work == nil)
        .animation(.snappy(duration: 0.28), value: work?.phase)
        // Nothing here answers to a finger : it reports and does not act.
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(work.map { Text($0.phase.title) } ?? Text(""))
        .accessibilityValue(value)
        .accessibilityHidden(work == nil)
        // So VoiceOver does not read every batch out as it lands.
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func content(_ work: WorkPlan) -> some View {
        VStack(spacing: 6) {
            // **The words and the rule, and no figures.** A count beside them is
            // a second measure of the same thing, disagreeing with the first :
            // the rule is the whole pass and a figure can only ever be the step,
            // so `9 of 112` sat under a bar four fifths of the way along and the
            // reader had to work out which of the two to believe. The bar says
            // how far ; the mark and the words say what.
            //
            // **Centred over the rule**, because the rule runs the whole width
            // and a label set against its left end reads as a caption for the
            // first fifth of it rather than for the measure.
            HStack(spacing: 6) {
                // **The stage's own glyph, without the ring round it.** The
                // ring was one symbol doing both jobs, the circle inked round
                // as the measure and the thing inside it saying which work ;
                // here the rule underneath is the measure, so an enclosure
                // would be a second and emptier one beside it.
                //
                // It pulses because a mark that only changed at each stage
                // would sit perfectly still through the minute the model takes,
                // which is the one moment a reader is looking to see whether
                // anything is happening at all. Still under Reduce Motion,
                // where the words and the rule already say it.
                Image(systemName: work.phase.glyph)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                    // The same Magic Replace the ring had : the stages follow
                    // one another several times a pass, and a mark that cut
                    // from one glyph to the next is a jump where the rule
                    // beneath it is running smoothly.
                    .contentTransition(.symbolEffect(.replace))

                Text(work.phase.title)
                    .lineLimit(1)
            }
            .font(theme.metadata)
            .foregroundStyle(.secondary)

            bar(work)
        }
        .frame(maxWidth: .infinity)
    }

    /// A rule that fills, which is the application's own idiom : the stories on
    /// the front page are separated by rules, and this is one of them saying how
    /// far along the pass is by how much of it is inked.
    @ViewBuilder
    private func bar(_ work: WorkPlan) -> some View {
        if let fraction = work.fraction {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: fraction)
        } else if reduceMotion {
            // A bar that runs for ever is motion for its own sake, and the line
            // above has already said what is happening.
            Capsule().fill(.tint.opacity(0.35)).frame(height: 3)
        } else {
            ProgressView().progressViewStyle(.linear)
        }
    }

    private var value: Text {
        guard let work else { return Text("") }
        guard let fraction = work.fraction else { return Text("In progress") }
        return Text(fraction.formatted(.percent.precision(.fractionLength(0))))
    }
}

/// The subjects the reader's panel leads to.
///
/// A case rather than a `NavigationLink` written out per row : a mark, a name,
/// a line and an identifier are four facts about one subject, and four facts
/// written at four call sites are four places to forget one.
enum ReaderPage: Hashable, CaseIterable {
    /// What they follow, and what the machinery is doing about it.
    case sources
    /// Every subject there is, and what they have said about each.
    case subjects
    /// Everything Flong may interrupt them for.
    case notifications
    /// What their reading adds up to.
    case statistics
    /// The reader's own face, name and town.
    case profile
    /// The face the page is set in, and the paper it is printed on.
    case appearance
    /// When the four editions of the digest come out.
    case editions
    /// What they offer the other readers, and who they brought in.
    case popular
    /// The sites they pay for and are signed in to.
    case sites
    /// Which model writes what, and the accounts they brought of their own.
    case models
    /// What has been sent to one of those accounts. Reached from the page
    /// above and never from the panel itself, which is why it is not in a card.
    case providerCalls
    /// What this device and the reader's iCloud hold, down to taking it all
    /// back.
    case data
    /// The application itself, which is the one row here that is not about the
    /// reader.
    case about

    var title: LocalizedStringResource {
        switch self {
        case .sources: "Sources"
        case .subjects: "Subjects"
        case .notifications: "Notifications"
        case .statistics: "Statistics"
        case .profile: "Profile"
        case .appearance: "Appearance"
        case .editions: "Editions"
        case .popular: "Popular feeds"
        case .sites: "Subscribed sites"
        case .models: "Models"
        case .providerCalls: "Outgoing calls"
        case .data: "Your data"
        case .about: "About"
        }
    }

    var mark: String {
        switch self {
        case .sources: "square.stack"
        case .subjects: "circle.grid.2x2"
        case .notifications: "bell"
        case .statistics: "chart.pie"
        case .profile: "person.crop.circle"
        case .appearance: "paintpalette"
        case .editions: "newspaper"
        case .popular: "person.2"
        case .sites: "key"
        case .models: "text.line.3.summary"
        case .providerCalls: "arrow.up.forward"
        case .data: "icloud"
        case .about: "info.circle"
        }
    }

    /// What a test presses, which is never a translated name.
    var identifier: String {
        switch self {
        case .sources: "sources"
        case .subjects: "subjects"
        case .notifications: "notifications"
        case .statistics: "statistics"
        case .profile: "reader-profile"
        case .appearance: "reader-appearance"
        case .editions: "reader-editions"
        case .popular: "reader-popular"
        case .sites: "reader-sites"
        case .models: "reader-models"
        case .providerCalls: "reader-provider-calls"
        case .data: "reader-data"
        case .about: "reader-about"
        }
    }
}
