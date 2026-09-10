//
//  DigestScreen.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The front page.
///
/// One column, held to a readable measure whatever the window does, with the
/// stories set as an editor would set them : a rule, a headline, a line, and the
/// facts underneath. No cards, no boxes, no glass. Boxes are what an interface
/// reaches for when it does not trust its own typography, and they turn a page
/// into a control panel.
struct DigestScreen: View {
    let model: AppModel
    let zoom: Namespace.ID
    @Binding var isAddingFeed: Bool
    @Binding var isChoosingFile: Bool
    @Binding var isSeeingPopular: Bool
    /// The reader arriving from another reader, which is the commonest way a
    /// first launch has anything to show at all.
    @Binding var isImportingService: Bool
    let open: (Route) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    /// Carries a pill's glass from one state to the next.
    @Namespace private var pills

    /// How far the page has been scrolled, which the wash behind it follows.
    ///
    /// An object rather than a number, so that a scroll moves the wash without
    /// rebuilding the page it is behind. See ``PageOffset``.
    @State private var offset = PageOffset()

    /// Where the seam between today's paper and the back numbers sits, measured
    /// down the page's own content.
    ///
    /// State, and it can afford to be : it is measured in a coordinate space
    /// that does not move with the scroll, so it is written when the layout
    /// changes and not on every frame. `nil` until there is an archive under
    /// the page, and the catch does nothing then.
    @State private var seam: CGFloat?

    /// Whether the reader has crossed into the back numbers, which is what is
    /// felt rather than what is drawn.
    @State private var isReadingBackNumbers = false

    /// Where each paper on the page begins, and what the bar should say over
    /// it.
    ///
    /// An object, written from the layout of a lazy stack and read from the
    /// scroll, so neither of those rebuilds the page. See ``Datelines``.
    @State private var datelines = Datelines()

    /// What the bar is saying, or nothing where it is saying today's.
    ///
    /// State, and it can afford to be : it is assigned when the reader crosses
    /// from one paper into the next and not on every frame of getting there.
    @State private var naming: Datelines.Mark?

    /// How far past the foot of today's paper the reader is pulling.
    ///
    /// An object rather than a number, so a gesture moves the seam without
    /// rebuilding the page it is at the foot of. See ``FootPull``.
    @State private var pull = FootPull()

    /// The page's own content, which the seam is measured down.
    private static let page = "digest-page"

    /// How far back above the seam the reader has to come before they have left
    /// the archive again.
    ///
    /// A dead band, and it is not decoration : a scroll settling on the seam
    /// jitters by a point or two, and a boundary tested exactly would fire the
    /// tap half a dozen times for one crossing.
    private static let seamHysteresis: CGFloat = 44

    var body: some View {
        ScrollView {
            // The gesture, from UIKit. It draws nothing and takes no room here ;
            // it is in the content only so that it can find the scroll view it
            // is inside and hand it a control. `PullToRefresh` sets out why
            // SwiftUI's own modifier is not what does this.
            PullToRefresh {
                await model.pullToRefresh()
            }

            // A pinned section header rather than a bar in the safe area : the
            // bar lays out under a large title and draws itself somewhere else
            // entirely, and a header is where this one belongs anyway, at the
            // head of what it filters.
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    stories
                } header: {
                    topics
                        // Pinned is not the same as in front : without this the
                        // rows pass over the pills rather than under them, and
                        // a headline crossing the row is drawn on top of it.
                        // The wire's chart carries the same line for the same
                        // reason.
                        .zIndex(1)
                }

                // **A section of its own, and the pills do not follow into
                // it.** The subjects narrow today's stories ; a back number is
                // a page that was already narrowed by nothing and cannot be
                // narrowed now. Held in the section above, the pinned row of
                // pills would ride over last Tuesday's paper offering to filter
                // it, which is a control that would answer nothing.
                Section { backNumbers }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
            // The seam measures itself down this, which is the page's own
            // content and does not move when the page is scrolled : the head
            // sinks by a transform and takes no room away as it goes, so what
            // is measured here changes when the layout changes and never per
            // frame.
            .coordinateSpace(.named(Self.page))
        }
        // Felt on the way back up as well as down : the tap that opens the
        // archive is the pull's own, and this is the boundary being crossed
        // afterwards, which a reader who felt it once expects to feel again.
        .sensoryFeedback(trigger: isReadingBackNumbers) { was, now in
            was == now || !model.backNumbersAreOpen ? nil : .impact(flexibility: .soft, intensity: 0.6)
        }
        // **Behind the scroll view, and the width of the page.** It was the
        // background of the column of type, which is held to a measure and
        // inset by its own margins, inside a scroll view that clips : at rest
        // the clip fell on the edges of the screen and nothing showed, and the
        // moment a transition turned the page into an inset card the
        // rectangle's own three edges came into view as hard lines across it.
        // It still scrolls away with the head of the page, from the offset
        // below rather than by being carried along.
        .background(alignment: .top) {
            PageWash(url: leadPicture, offset: offset)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, position in
            // The wash follows through the object, which costs no rebuild.
            offset.scrolled = position
            crossed(at: position)
            name(at: position)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        // Narrowing to a subject replaces the page, so where the papers began
        // is a question about a page that is no longer there.
        .onChange(of: model.digestTopic) {
            datelines.marks.removeAll()
            naming = nil
        }
        // **The pull, on the front page and nowhere else.** The page does keep
        // itself up to date : it follows the store, so anything that arrives
        // reaches it, and a clock asks the publishers what politeness allows.
        // The gesture is not how the page keeps up ; it is how a reader says
        // now rather than soon, and it is the gesture every reader already
        // reaches for on the page they open first. The wire needs none : it is
        // a list of what has arrived, and what arrives reaches it on its own.
        //
        // It fetches every feed and groups what arrived, and it ends there. The
        // model's work carries on behind it.
        //
        // **The gesture takes and lets go.** The control used to be held out
        // for the whole of the fetching, which is what dragged the page down,
        // sometimes left it there, and made every question about this page a
        // question about an inset. It reports the pull was heard and retracts
        // on the beat now ; the band at the head of ``ReaderPanel`` is what
        // says the work is running, which is where a reader goes to ask rather
        // than on the page they are reading.
        //
        // A Mac has no pull and no command either, since the command came out
        // of the reader's menu : it keeps up through the clock, the full pass
        // at rest, and the watcher that follows the store.
        //
        // **It is `PullToRefresh` and not `refreshable`.** SwiftUI's modifier
        // draws a control for a `List` ; on a scroll view it is accepted and
        // unreliable, and on this one it never drew anything at all. A reader
        // pulling a page that does not flinch, while the same work runs
        // perfectly from the menu, is one of the two paths never being called.

        // The date is the title of the page, where a newspaper puts it. Not the
        // name of the section : the tab bar says that already, and a page that
        // repeats its own label has spent a line saying nothing. A dateline says
        // what the label did not, which is how old what follows is allowed to be.
        //
        // A large title like every other section's, so it shrinks into the bar
        // as the reader scrolls into the page.
        // **Whichever paper is under the reader's eye.** The bar is the
        // dateline, and a page that scrolls through a year of papers has to say
        // which one this is : it said today's whatever they were looking at, so
        // a reader four papers down was being told the wrong day by the one
        // line on the screen whose whole job is to say the day.
        .navigationTitle(Text(verbatim: naming?.day ?? Self.today()))
        // **Which edition, under the date the page is titled with.** It stood
        // over the list, which put a second heading under the date : two lines
        // saying when, one above the other, and the reader had read the day
        // before reaching either. A masthead puts the edition under the
        // dateline, and so does this.
        //
        // Empty where there is no edition, since a subtitle about a page that
        // does not exist is a line saying nothing.
        .navigationSubtitle(Text(verbatim: naming?.line ?? dateline))
        // The sources in one corner, the reader's own menu in the other, the
        // same way round in every section.
        .toolbar {
            // **One thing in this corner, and it is about this page.** It
            // held the sources, the subjects, the notices and then the figures,
            // which is four glyphs before the page has said anything : a
            // toolbar is not a menu, and a reader looking for one of them was
            // reading pictures. All four are rows in the reader's own menu now,
            // named in words. A back number is the one control left that is
            // about this page rather than about the whole of what a reader
            // reads, which is the whole argument for its being here.
            ReaderCorner(model: model) { open(.view($0)) }
        }
        // Not while something is being brought in. `Nothing has come in yet`
        // over a page that is at that moment fetching sixty feeds is untrue,
        // and it is untrue at the one moment the reader is most likely to be
        // looking : the first launch after an import.
        .overlay {
            // Three pages that look identical and are not : one with no feeds,
            // one narrowed to a subject holding nothing, and one whose edition
            // will never be written. The last is the new one, and it is the one
            // that most looks like a fault when it is not : a device with no
            // model will never have an edition, and saying so is the whole of
            // section 14's no-model path here.
            //
            // **Said only where the absence is permanent.** An edition that is
            // merely being written is a page that is about to arrive, and
            // telling the reader there is none would be untrue for the minute
            // it takes. That case draws the shape of the page instead, above.
            if model.digestTopic == .frontPage, model.edition == nil, !isWaitingForAnEdition {
                NoEdition(hasSchedule: !model.editionSchedule.slots.isEmpty, absence: model.editionsAbsence) {
                    open(.view(.unread))
                }
            } else if model.digest.isEmpty, model.currentWork == nil {
                empty
            }
        }
    }

    // MARK: - The page

    @ViewBuilder
    private var stories: some View {
        // **The page and its lead are one value.**
        //
        // The lead was worked out here, from the two lists, which is the right
        // rule in the wrong place : a story moves between the two as it gains
        // articles and keeps its identifier, and a lead derived by whatever
        // happens to be rendering is one the row that was the lead and the row
        // that is can disagree about, until the application is opened again.
        // It is decided where the page is built now : see ``Digest/leadID``.
        let page = model.digest
        let live = page.live
        let rest = page.stories
        let lead = page.leadID

        // **The front page is an edition, and a subject is a question about
        // everything.** Ten stories is what a person reads over a coffee, and
        // it is what an edition carries ; narrowing to a subject is the reader
        // asking what there is about one thing, which ten of anything would
        // answer badly. So the cap belongs to the page and not to the store,
        // and a pill still reads the whole of the three days.
        if model.digestTopic == .frontPage, let published = model.edition {
            EditionHead(published: published)
                // Today's paper says where it begins too, or the bar would have
                // nothing to go back to once the reader comes up out of the
                // archive.
                .dateline(datelines, of: published, day: Self.today(), in: Self.page)
                // **The animation is here and nowhere above.** It was three
                // `.animation(_:value:)` on the `LazyVStack` itself, which is
                // where it does the most harm : an animation attribute on a
                // container is inherited by every descendant, so one story
                // arriving animated the layout of every realized row and of the
                // pinned header at once, the stack's height interpolated for
                // three tenths of a second, and the scroll view re-derived its
                // visible range against a moving geometry on every frame of it.
                // Rows realized and de-realized under the reader's thumb.
                //
                // What actually swaps is the head : a skeleton becomes a page.
                // That is one view, it is at the top, and animating it costs
                // the rows nothing.
                .transition(.opacity)
                .animation(.smooth(duration: 0.35), value: published.edition.id)
                // **It goes back rather than up.** Every other row of the
                // page leaves by the top edge, which is right for a story : it
                // is one of forty and the next one takes its place. What the
                // edition says is the page's own voice and there is one of it,
                // so it holds its ground, shrinks, softens and is gone by the
                // time the first headline reaches where it stood, and the news
                // slides over it.
                .modifier(EditionSinking(offset: offset))

            // Joined on the model, where the page and the edition are both
            // settled, rather than here where the body runs. See
            // ``AppModel/frontPageStories``.
            let shown = model.frontPageStories
            ForEach(shown) { story in
                row(story, isLead: story.id == shown.first?.id, isFirst: story.id == shown.first?.id)
            }
        } else if isWaitingForAnEdition {
            // **The shape of the page, before there is one.** An edition is not
            // published until the model has written the whole of it, so the
            // front page stood empty for as long as that takes and then arrived
            // all at once, pushing everything below it down the screen. A
            // reader who had started reading lost their place to a page they
            // had not asked to change.
            EditionPlaceholder()
                .transition(.opacity)
            StoryPlaceholder(isLead: true)
            StoryPlaceholder()
        } else {
            if !live.isEmpty {
                header {
                    HStack(spacing: 7) {
                        LiveDot()
                        // The dot's own colour at the quiet end of its pulse :
                        // the dot is the loud thing and the word is what it
                        // means, so the pair reads as one mark rather than as
                        // two red things.
                        Text("Live stories").foregroundStyle(LiveDot.quietTint(theme))
                    }
                }
                ForEach(live) { story in
                    row(story, isLead: story.id == lead, isFirst: story.id == lead)
                }
            }

            if !rest.isEmpty {
                // Not "Front page" : that is what the pill above already says,
                // and a page does not need to name itself twice.
                header {
                    switch model.digestTopic {
                    case .frontPage: Text("Stories")
                    case .named(let topic): Text(verbatim: topic)
                    }
                }
                ForEach(rest) { story in
                    row(story, isLead: story.id == lead, isFirst: story.id == lead)
                }
            }
        }
    }

    /// Says whether the reader is in the archive, and only when the answer
    /// moves.
    ///
    /// Written from the scroll, so it has to be cheap : the comparison is two
    /// numbers, and the state behind it is assigned once per crossing rather
    /// than once per frame.
    private func crossed(at position: CGFloat) {
        guard let seam else {
            if isReadingBackNumbers { isReadingBackNumbers = false }
            return
        }

        let bound = isReadingBackNumbers ? seam - Self.seamHysteresis : seam
        let inside = position >= bound
        if inside != isReadingBackNumbers { isReadingBackNumbers = inside }
    }

    /// Says which paper the bar is naming, and only when the answer moves.
    ///
    /// Written from the scroll, so it has to be cheap : a sweep of a dictionary
    /// with one entry per paper, and the state behind it assigned once per
    /// crossing rather than once per frame.
    private func name(at position: CGFloat) {
        // **Today's, on a page narrowed to a subject.** A pill reads the whole
        // of the three days and has no papers under it, so nothing there
        // reports a dateline ; left to the marks a previous scroll wrote, the
        // bar would name a back number over a page that is not one.
        guard model.digestTopic == .frontPage else {
            if naming != nil { naming = nil }
            return
        }

        let named = datelines.naming(at: position)
        if named != naming { naming = named }
    }

    // MARK: - The back numbers

    /// Every edition before this one, under it, as far as the reader goes.
    ///
    /// **Only under the front page.** A subject is a question about the whole
    /// of the three days and never about one paper, so a narrowed page has no
    /// archive to put under it ; and a device that has never published an
    /// edition has no history to show for a page it does not have.
    @ViewBuilder
    private var backNumbers: some View {
        if model.digestTopic == .frontPage, model.edition != nil {
            // The foot of today's paper, and the gesture that opens what is
            // under it. It draws nothing and takes no room : it is a point of
            // contact and not a thing on the page.
            PullForBackNumbers(pull: pull) { model.openBackNumbers() }

            // The foot of the page saying it has one. It goes with the pull
            // it explains : once the archive is open there is nothing left to
            // ask for.
            if !model.backNumbersAreOpen {
                PullMark(drawn: min(pull.pulled / PullForBackNumbers.threshold, 1))
            }

            BackNumbersMasthead(pull: pull, isOpen: model.backNumbersAreOpen)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .named(Self.page)).minY
                } action: { measured in
                    if seam != measured { seam = measured }
                }

            if model.backNumbersAreOpen {
                ForEach(model.editionArchive) { published in
                    BackNumber(published: published, marks: model.digest.symbols, zoom: zoom) {
                        open(.story($0))
                    }
                    .dateline(
                        datelines,
                        of: published,
                        day: Datelines.day(published.edition.openedAt),
                        in: Self.page
                    )
                }

                // **Reached rather than pressed.** The row is realized a little
                // before it comes into sight, so the next few pages are in hand
                // by the time the thumb arrives. Keyed on what is already held,
                // or the task would run once and the archive would stop at the
                // first batch.
                if model.hasOlderEditions {
                    MoreBackNumbers()
                        .task(id: model.editionArchive.count) { await model.readOlderEditions() }
                }
            }
        }
    }

    private func header(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .font(.system(.footnote, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.secondary)
            .padding(.top, Editorial.rhythm)
            .padding(.bottom, Editorial.tightRhythm)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The first story on the page runs its picture across the column.
    ///
    /// A page where every story is the same size is a list, and a list makes the
    /// reader do the ranking the digest exists to do. One lead, and the rest set
    /// smaller, is how a front page has said what matters for two centuries.
    ///
    /// Which one that is arrives as an argument rather than being worked out
    /// here : ``stories`` reads the page and its lead in one go, and a row that
    /// asked the store again would be asking at a moment of the layout's
    /// choosing.
    private func row(_ story: DigestStory, isLead: Bool, isFirst: Bool = false) -> some View {
        StoryRow(story: story, isLead: isLead, isFirst: isFirst, marks: model.digest.symbols, zoom: zoom) {
            open(.story(story.id))
        }
    }

    /// An empty page, an empty subject and an empty account are three
    /// different emptinesses.
    ///
    /// A reader who follows nothing needs a feed, not an explanation of what
    /// grouping is : this is the first page they land on and there is no tab of
    /// sources beside it any more, so the two ways in are offered where they
    /// are already looking. A reader who has just written a subject nothing has
    /// been filed under yet is looking at a page working exactly as it should,
    /// and telling either of them that nothing has come in would be telling
    /// them something untrue.
    @ViewBuilder
    private var empty: some View {
        if model.isEmpty {
            ContentUnavailableView {
                Label("No feed yet", systemImage: "dot.radiowaves.up.forward")
            } description: {
                Text("Add a feed, bring your subscriptions over, or see what other readers follow.")
            } actions: {
                Button("Add a feed") { isAddingFeed = true }
                Button("Import from FreshRSS") { isImportingService = true }
                Button("Import an OPML file") { isChoosingFile = true }
                Button("Popular feeds") { isSeeingPopular = true }
            }
        } else if let name = model.digestTopic.name {
            ContentUnavailableView {
                Label(title: { Text(verbatim: name) }, icon: { Image(systemName: "circle.grid.2x2") })
            } description: {
                Text("Nothing has been filed under this subject yet.")
            } actions: {
                Button("Front page") { withAnimation { model.digestTopic = .frontPage } }
            }
        } else {
            ContentUnavailableView {
                Label("Nothing has come in yet", systemImage: "newspaper")
            } description: {
                Text("Flong groups your articles into stories as they arrive.")
            } actions: {
                Button("Group now") { Task { await model.rebuildDigest() } }
            }
        }
    }

    /// The mark a pill wears.
    ///
    /// The front page is not a subject and is in no vocabulary, so its own is
    /// written here : the paper itself, which is what that pill selects.
    private func mark(of topic: DigestTopic) -> String {
        guard let name = topic.name else { return "newspaper" }
        return model.digest.symbols[name] ?? Topic.defaultSymbol
    }

    /// The colour a pill is drawn in : its glass, its mark, and its type where
    /// it is the one chosen.
    ///
    /// Taken from the mark rather than from the name, for the reason
    /// ``StandardTopics/families`` gives.
    ///
    /// **The front page keeps the accent, being no subject.** It is the one
    /// pill that names the whole page rather than a kind of news, and a row
    /// whose first capsule is the theme's own colour is a row a reader can find
    /// their way back along.
    private func colour(of topic: DigestTopic) -> Color {
        guard topic.name != nil else { return theme.accent(in: scheme) }
        return StandardTopics.family(of: mark(of: topic)).color(in: scheme)
    }

    /// The edition's stories, in the edition's order, as the page holds them.
    ///
    /// **Resolved through a dictionary and once.** It was
    /// `published.stories.compactMap { page.all.first { ... } }`, which is ten
    /// linear scans of up to sixty stories, and `Digest.all` is
    /// `live + stories` : a fresh array of the whole page allocated on each of
    /// the ten. That is ten copies of the page to resolve ten identifiers,

    /// The stories the page is showing, by identity.
    ///
    /// What the arrival of a row is animated against. The page itself is a
    /// large value that changes whenever anything about any story does, an
    /// article marked read included, and animating on that would run a
    /// transition every time somebody opened something.
    private var shownStories: [UUID] {
        guard model.digestTopic == .frontPage, model.edition != nil else {
            return model.digest.all.map(\.id)
        }
        return model.frontPageStories.map(\.id)
    }

    /// The picture the head of the page is washed in the colours of.
    ///
    /// **The one the page actually leads on, which is not what `Digest.lead`
    /// answers any more.** That is the lead of the whole three-day page, worked
    /// out from the front page's own ranking ; what the reader sees at the top
    /// is the first story of the *edition*, in the edition's order. The two are
    /// usually different stories, so the head was washed in the colours of a
    /// photograph further down the page or not on it at all.
    ///
    /// Off the edition where there is one, and off the page's own lead where
    /// there is not, which is a subject narrowed to a pill and the wire behind
    /// a device with no model.
    private var leadPicture: URL? {
        guard model.digestTopic == .frontPage, model.edition != nil else {
            return model.digest.lead?.imageURL
        }

        return model.frontPageStories.first?.imageURL
    }

    /// Whether an edition is on its way rather than absent for good.
    ///
    /// The two look identical on screen and are not : a device with no model
    /// will never have one, a reader who switched every edition off asked for
    /// none, and a reader who follows nothing has nothing to make one from. Any
    /// of those is a page that has to say so. Everything else is a page about
    /// to arrive, and the shape of it is drawn while it does.
    private var isWaitingForAnEdition: Bool {
        model.digestTopic == .frontPage
            && model.edition == nil
            && !model.isEmpty
            && !model.editionSchedule.slots.isEmpty
            && model.writesEditions
    }

    /// Which edition the page is showing, and when it came out.
    ///
    /// **The moment comes from the schedule where no edition has been published
    /// yet.** The boundary is known from the clock and the reader's own hours,
    /// long before the model has written a word, so the line can be right from
    /// the moment the page opens rather than appearing when the edition lands.
    /// A subtitle that arrives is one more thing moving on a page that has just
    /// been asked to stop moving.
    ///
    /// Empty where there is no edition to come at all : a device with no model
    /// never has one, and a subtitle about a page that will not exist is a line
    /// saying nothing.
    private var dateline: String {
        let named: (slot: EditionSlot, opened: Date)? =
            model.edition.map { (slot: $0.edition.slot, opened: $0.edition.openedAt) } ?? scheduled

        guard let named else { return "" }
        return "\(String(localized: named.slot.title)) · \(named.opened.formatted(.dateTime.hour().minute()))"
    }

    /// Which edition the page is, read off the reader's own hours where the
    /// edition itself has not arrived yet.
    ///
    /// **Decided at the first frame, and it has to be.** A navigation bar
    /// measures the height of its title area once : a subtitle that appears
    /// under the title later does not make it measure again, and the page
    /// opened nineteen points short of where it belongs and stayed there until
    /// the first scroll pushed the bar into laying itself out again. The reader
    /// saw the page settle downwards the moment they touched it.
    ///
    /// So every term of this is known before anything is read : the hours come
    /// from the preferences, which are held rather than fetched, and whether
    /// there is a model to write an edition at all is a question about what the
    /// reader has chosen and what the device can do, both of which are held.
    /// Waiting on the store, as this did, is what made the line arrive
    /// a beat late. Empty only where no edition is coming, ever : no hours set,
    /// or no model to write one.
    private var scheduled: (slot: EditionSlot, opened: Date)? {
        guard model.digestTopic == .frontPage,
            !model.editionSchedule.slots.isEmpty,
            model.writesEditions
        else { return nil }

        return model.editionSchedule.current()
    }

    /// Today, spelled the way the reader's language spells it.
    ///
    /// Read at each render rather than held : the page is rebuilt on returning
    /// to the foreground, which is when a date left open overnight would
    /// otherwise be yesterday's.
    private static func today(_ date: Date = .now) -> String { Datelines.day(date) }

    /// The subjects the model found, as pills that scroll.
    ///
    /// They replace the day, week and month selector. A period is a question
    /// about the calendar, and nobody watching a subject asks it : they ask what
    /// is happening, and then what is happening about one thing.
    ///
    /// This is the one place in the application that draws glass of its own, and
    /// it is allowed here for the reason the rest is not : a pill is a control
    /// floating over the page, which is the layer Apple's material is for. It
    /// sits in the content and scrolls away with it rather than pinning itself
    /// under the tab bar, since glass directly under glass is the stacking the
    /// same guidance forbids.
    ///
    /// They stay at the head of the page as it scrolls, since a filter that
    /// leaves the screen is a filter a reader has to go back up to change.
    ///
    /// Where there is no model there are no subjects, and no pills : the front
    /// page is entire on its own, and section 14 asks for exactly that.
    @ViewBuilder
    private var topics: some View {
        if !model.digest.topics.isEmpty {
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    // **Eager, and it has to be.** The row was made lazy to
                    // stop fifteen panes of glass being resolved for the whole
                    // of every scroll, and it bought that at a price nobody
                    // would have paid knowingly : a pill that is not realized
                    // has not been laid out, so scrolling it into view is not
                    // the row moving under the reader's finger, it is a shape
                    // entering the glass container. Every pill here carries a
                    // ``glassEffectID``, which is what tells the container the
                    // shape is the same one it was drawing a moment ago, and a
                    // shape it has never drawn before is an insertion. The
                    // container animates an insertion, because that is what it
                    // is for, so each subject morphed into existence at the
                    // edge of the screen as the reader reached it.
                    //
                    // Fifteen capsules of type at the head of one page is not
                    // the cost that was worth chasing anyway. What was
                    // expensive was `interactive()`, which follows a finger for
                    // as long as the row is on screen and this row is always on
                    // screen ; that came off in the same change and stays off.
                    HStack(spacing: 8) {
                        pill(.frontPage, title: Text("Front page"))
                        ForEach(model.digest.topics, id: \.self) { topic in
                            pill(.named(topic), title: Text(verbatim: topic))
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private func pill(_ topic: DigestTopic, title: Text) -> some View {
        // A menu with a primary action rather than a button with a context menu :
        // a tap does the tap, a long press opens the menu, and both are the
        // control's own business. A context menu over glass never fired at all,
        // measured on the simulator, and there is nothing to say about the front
        // page anyway, so that one stays a button.
        if topic.name == nil {
            Button {
                choose(topic)
            } label: {
                label(topic, title: title)
            }
            .buttonStyle(.plain)
            .modifier(
                PillShape(
                    isCurrent: model.digestTopic == topic,
                    topic: topic,
                    colour: colour(of: topic),
                    namespace: pills
                )
            )
        } else {
            Menu {
                preferences(for: topic)
            } label: {
                label(topic, title: title)
            } primaryAction: {
                choose(topic)
            }
            .buttonStyle(.plain)
            .modifier(
                PillShape(
                    isCurrent: model.digestTopic == topic,
                    topic: topic,
                    colour: colour(of: topic),
                    namespace: pills
                )
            )
            // The Mac says the same thing by right-clicking.
            .contextMenu { preferences(for: topic) }
        }
    }

    private func choose(_ topic: DigestTopic) {
        withAnimation(.snappy(duration: 0.26)) { model.digestTopic = topic }
    }

    private func label(_ topic: DigestTopic, title: Text) -> some View {
        let isCurrent = model.digestTopic == topic
        let score = topic.name.map { model.digest.scores[$0] ?? 0 } ?? 0

        return HStack(spacing: 5) {
            // **The mark leads, and it is the one thing on a pill that is not a
            // word.** A row reading `Politique · Économie · Cinéma · Sport` is
            // four words a reader has to read on every scroll ; the same row
            // with a glyph in front of each is four shapes they recognize. It
            // is hidden from VoiceOver, the name beside it saying the same
            // thing and saying it better.
            // It says nothing about its colour : the whole pill is set in the
            // subject's own now, and a mark stating the same thing again is a
            // second place to change it.
            Image(systemName: mark(of: topic))
                .font(.system(.caption, weight: .medium))
                .accessibilityHidden(true)

            // Only when there is something to say : a row of arrows on every
            // pill would be a row of arrows nobody reads.
            if score != 0 {
                Image(systemName: score > 0 ? "arrow.up" : "arrow.down")
                    .font(.system(.caption2, weight: .semibold))
                    .accessibilityLabel(score > 0 ? Text("Seeing more") : Text("Seeing less"))
            }
            title
                // One weight for every pill, chosen or not. Bolder when chosen
                // made the pill wider when chosen, and every pill after it moved
                // as the reader tapped.
                .font(.system(.footnote, weight: .medium))
                .lineLimit(1)
        }
        // **The colour is in the ink, and it was in the ground.** Every pill
        // carried a wash of its own subject, which is fifteen tinted capsules
        // across the head of the page and the type on all of them the page's
        // own ink. It is the other way about : the ground is the plain material
        // and the subject's colour is what the words and the mark are set in,
        // so the row is the page's own paper with fifteen colours of type on
        // it. Chosen, the pill is a pane of that colour and the type turns to
        // the paper, which is the one thing always on the far side of whatever
        // is printed on it.
        .foregroundStyle(
            isCurrent ? AnyShapeStyle(theme.onAccent(in: scheme)) : AnyShapeStyle(colour(of: topic))
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// What a reader can say about a subject, on a long press.
    ///
    /// A subject is the only thing on the page general enough to have an
    /// opinion about : more of this, less of this. An article is one article
    /// and a story is one event, and a preference about either would be a
    /// preference about something that will not happen again.
    ///
    /// The front page has no preferences : it is where everything is.
    @ViewBuilder
    private func preferences(for topic: DigestTopic) -> some View {
        if let name = topic.name {
            let score = model.digest.scores[name] ?? 0

            Button {
                Task { await model.prefer(name, by: 1) }
            } label: {
                Label("See more of this", systemImage: "arrow.up")
            }
            .disabled(score >= TopicPreferences.limit)

            Button {
                Task { await model.prefer(name, by: -1) }
            } label: {
                Label("See less of this", systemImage: "arrow.down")
            }
            .disabled(score <= -TopicPreferences.limit)

            if score != 0 {
                Divider()
                Button {
                    Task { await model.forgetPreference(of: name) }
                } label: {
                    Label("No preference", systemImage: "minus")
                }
            }
        }
    }

}

/// One story, set as an editor would set it.
///
/// The lead runs its picture across the column, above a larger headline. The
/// others keep theirs to a square at the side, where it says which story this is
/// without competing with the story above it.
///
/// **Every picture is credited.** A story is several rooms and its picture is
/// one room's, so the marks beside the headline do not say whose it is. The
/// name sits in the corner of the picture, on a pill of glass, at both sizes :
/// a credit shown on the lead and withheld from the rest would be a courtesy
/// paid to whichever publisher happened to be first that morning.
struct StoryRow: View {
    let story: DigestStory
    var isLead = false
    /// Whether this is the first row of the page, which is the one row that
    /// carries no rule above it.
    var isFirst = false
    /// The mark each subject wears, which is what its rubric is printed from :
    /// see ``StandardTopics/families``.
    var marks: [String: String] = [:]
    let zoom: Namespace.ID
    let open: () -> Void

    @Environment(\.theme) private var theme

    /// The width of the picture beside a story that is not the lead. Its
    /// height follows from the one ratio every picture is shown in.
    private static let thumbnailWidth: CGFloat = 96

    var body: some View {
        Button(action: open) {
            Group {
                if isLead {
                    lead
                } else {
                    standard
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: story.id, in: zoom)
        // **A rule between two rows, and none above the first.** The rule is
        // what separates one story from the next ; over the first it is a
        // border round the page, and it fell directly under what the edition
        // says, which already stands on a pane of its own and needs nothing
        // drawn under it to be told apart from the news.
        .overlay(alignment: .top) { if !isFirst { Divider() } }
        .accessibilityElement(children: .combine)
    }

    /// The story the page leads on : its picture across the column, and its
    /// type a step up from everything under it.
    ///
    /// **A lead that is two points larger is not a lead.** It ran at `title2`
    /// over a page set in `title3`, which is twenty-two points against twenty :
    /// a difference a reader cannot see is a difference that is not there, and
    /// a page where every story is the same size is a list, which makes the
    /// reader do the ranking the digest exists to do.
    ///
    /// So it takes the next step of the scale in both, `title` over the rest's
    /// `title3` and `body` over their `subheadline`, which is what a front page
    /// has always done and what makes the picture above it read as belonging to
    /// something rather than as the top of a list. Steps of the scale rather
    /// than sizes in points, so the whole of it still follows Dynamic Type.
    private var lead: some View {
        VStack(alignment: .leading, spacing: 10) {
            if story.imageURL != nil {
                RemoteImage(url: story.imageURL, credit: story.imageCredit, corner: 10)
                    .padding(.bottom, 2)
            }
            VStack(alignment: .leading, spacing: 7) {
                masthead(headline: .title)
                whatHappened(standfirst: .body)
                facts
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var standard: some View {
        // **The headline crosses the whole measure ; the picture comes in
        // beside what follows it.** A headline is the widest thing a story
        // says and the thing a reader scans for, and one squeezed into the
        // column left over by a thumbnail breaks over three lines where it
        // would have taken two.
        //
        // So the picture is not beside the story, it is beside the summary :
        // the rubric and the headline run the full width above it, and what
        // explains them shares the line with it.
        VStack(alignment: .leading, spacing: 7) {
            masthead(headline: .title3)

            HStack(alignment: .top, spacing: 14) {
                whatHappened()

                if story.imageURL != nil {
                    RemoteImage(url: story.imageURL, credit: story.imageCredit, width: Self.thumbnailWidth)
                }
            }

            // **Under the picture and not beside it.** The facts end in the
            // moment the story was last added to, which is pushed to the far
            // end of the line ; beside a thumbnail that end is the thumbnail's
            // edge, and without one it is the measure. So the times marched
            // down the page in two columns, alternating with whichever stories
            // happened to carry a picture, and a column that moves is a column
            // a reader stops reading. Across the measure there is one edge for
            // every row, the lead included.
            facts
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the story is filed under and what it is called, which run the
    /// whole measure whether there is a picture or not.
    private func masthead(headline: Font.TextStyle) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // The subject above the headline : a reader scanning the page reads
            // it before the headline, the way a rubric is read before the piece
            // under it.
            if !story.topics.isEmpty {
                Rubric(topics: story.topics, marks: marks)
                    .lineLimit(1)
            }

            Text(verbatim: story.title)
                .font(theme.headline(headline))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What happened, which is what a picture sits beside.
    ///
    /// It is set larger on the lead, for the reason the headline above it is :
    /// see ``lead``.
    ///
    /// The facts used to be under it, inside this column. They are under the
    /// whole row now, for the reason ``standard`` gives.
    @ViewBuilder
    private func whatHappened(standfirst: Font.TextStyle = .subheadline) -> some View {
        if let summary = story.summary, !summary.isEmpty {
            StorySummary(
                summary: summary,
                isGenerated: story.isGenerated,
                isTranslated: story.isTranslated,
                style: standfirst,
                lines: 3
            )
        } else {
            // A story the model said nothing about still has its picture at
            // the end of the line rather than at the start of it : an empty
            // column of the full width is what keeps it there.
            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
        }
    }

    /// Who is saying it, by their marks rather than by a count of them.
    ///
    /// `4 rédactions` is a number a reader has to turn back into rooms. Four
    /// marks are the rooms, and they say which ones, which is the question
    /// behind the number : a story every paper is running and a story only the
    /// trade press is running are not the same story.
    ///
    /// The count survives for anyone listening to the page rather than looking
    /// at it, and for the rooms there was no room to show.
    private var rooms: some View {
        MarkRow(domains: story.feedMarks.map(\.room), total: story.feedCount)
            .accessibilityElement()
            .accessibilityLabel(Text("\(story.feedCount) rooms"))
    }

    /// Why this is here : who is saying it, how many of them, and how fast.
    ///
    /// It is the explanation the 2026 trend towards visible reasoning asks for,
    /// and it happens to be the only interesting thing about a story anyway.
    ///
    /// Beside a picture on a phone there is not room for all of it, and a line
    /// that wraps to hyphenate `rédac-tions` is worse than a line that says less.
    /// The sparkline goes first, then the article count : what is left is who is
    /// talking and when they last did, which is the irreducible part.
    ///
    /// **Nothing at all where there is nothing to say.** A back number keeps
    /// its ten however a purge has thinned the stream underneath it, so a row
    /// can outlive the story it was printed from. Drawn anyway it claimed
    /// nought rooms, which VoiceOver reads out as a fact, an empty sparkline,
    /// and a moment computed off the edition's own dateline standing in for a
    /// date nobody knows. A headline with no figures is a headline.
    @ViewBuilder private var facts: some View {
        if story.hasFigures {
            ViewThatFits(in: .horizontal) {
                factsLine()
                factsLine(sparkline: false)
                factsLine(sparkline: false, articles: false)
            }
            .font(theme.metadata)
            .foregroundStyle(.tertiary)
        }
    }

    private func factsLine(sparkline: Bool = true, articles: Bool = true) -> some View {
        HStack(spacing: 10) {
            rooms

            if articles {
                Text("\(story.articleCount) articles")
                    .lineLimit(1)
            }

            if sparkline {
                Sparkline(values: story.arrivals)
                    .frame(width: 36, height: 9)
            }

            Spacer(minLength: 4)

            // What a model wrote is said in front of the line it wrote, by
            // ``StorySummary``, and not at the far end of the facts : the mark
            // used to be a screen's width from the sentence it was about.
            StoryMoment(date: story.lastAt)
        }
    }
}

/// One article, in a list of articles.
struct ArticleRow: View {
    let article: ArticleSummary
    var showsImage = true
    let zoom: Namespace.ID
    let open: () -> Void

    @Environment(\.theme) private var theme

    /// The width of the picture beside an article.
    private static let thumbnailWidth: CGFloat = 78

    /// The headline, with a tick at the end of it when the article has been
    /// read.
    ///
    /// At the end of the words rather than beside them, so it sits where the
    /// reader stopped reading and costs the row no width. Every headline keeps
    /// one weight and one colour : a page of half-grey rows is a page that
    /// looks stale, and a story worth reading is worth reading whether it has
    /// been opened once already or not.
    private var headline: Text {
        guard article.isRead else { return Text(verbatim: article.title) }

        let tick = Text(Image(systemName: "checkmark")).font(.caption2).foregroundStyle(.tertiary)
        return Text(
            "\(Text(verbatim: article.title))  \(tick)",
            comment: "A headline, and the tick that says the article has been read"
        )
    }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    headline
                        .font(theme.headline(.body))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let excerpt = article.excerpt, !excerpt.isEmpty {
                        Text(verbatim: excerpt)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: 6) {
                        SourceStamp(domain: article.domain)
                            .padding(.trailing, 2)
                        ArticleMoment(article: article)
                        if article.isStarred {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .accessibilityLabel(Text("Starred"))
                        }
                        if article.hasMedia {
                            Image(systemName: "play.circle")
                                .accessibilityLabel(Text("Holds media"))
                        }
                    }
                    .font(theme.metadata)
                    .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsImage, article.imageURL != nil {
                    RemoteImage(url: article.imageURL, width: Self.thumbnailWidth, corner: 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: article.id, in: zoom)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
        // The dot says unread by colour and shape alone, which says nothing at
        // all to a reader who is listening to the page.
        .accessibilityLabel(
            article.isRead ? Text("\(article.title), read") : Text("\(article.title), unread")
        )
    }
}

/// The glass a subject pill is drawn on.
///
/// Its own modifier so a button and a menu wear exactly the same one, and so
/// that what changes when a pill is chosen is its colour and nothing about its
/// size.
///
/// **The plain material until it is chosen, and the colour is in the ink.**
/// Every pill carried a wash of its own subject and the type on all of them was
/// the page's own ink, which is fifteen tinted capsules across the head of the
/// page : the row read as the coloured thing and the words as what was written
/// on it. Turned about, the ground is the material the rest of the page's
/// controls are made of and the colour is what the words and the mark are set
/// in, so a reader still finds `Sport` by its orange before they have read a
/// word and the row is quiet behind them.
///
/// Chosen, the pill is a pane of that colour at full strength, which is the one
/// state that has to be legible across a whole row at a glance : the subject's
/// own colour rather than an accent that would say nothing about it.
private struct PillShape: ViewModifier {
    let isCurrent: Bool
    let topic: DigestTopic
    /// The subject's own colour : see ``DigestScreen/colour(of:)``.
    let colour: Color
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            // **Not `interactive`.** Interactive glass follows a touch, which
            // means it is live for as long as the row is on screen, and this
            // row is pinned : it is on screen for the whole of every scroll. A
            // pill answers a tap ; it does not need to answer a finger passing
            // over it.
            .glassEffect(isCurrent ? .regular.tint(colour) : .regular, in: .capsule)
            .glassEffectID(topic, in: namespace)
            .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}
