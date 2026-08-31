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
    let open: (Route) -> Void

    /// Carries a pill's glass from one state to the next.
    @Namespace private var pills

    /// Where the page is, so it can be put back after a pull.
    @State private var position = ScrollPosition()
    /// Whether the page is still near its top, for deciding whether putting it
    /// back after a pull is a kindness or an interruption.
    ///
    /// **A flag and not a measurement.** It held the offset itself, which
    /// changes every frame of every scroll, so the whole page was rebuilt
    /// continuously while the reader's thumb was on it, and rebuilt hardest
    /// during the one gesture that must not be disturbed.
    @State private var isNearTop = true
    /// Whether the gesture's work is still running.
    @State private var isPulling = false

    var body: some View {
        ScrollView {
            // A pinned section header rather than a bar in the safe area : the
            // bar lays out under a large title and draws itself somewhere else
            // entirely, and a header is where this one belongs anyway, at the
            // head of what it filters.
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    stories
                } header: {
                    VStack(alignment: .leading, spacing: 0) {
                        topics
                        // It grows into its height and shrinks out of it again,
                        // rather than keeping a place it does not need.
                        ActivityLine(work: model.currentWork)
                    }
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top < Self.stillAtTheTop
        } action: { _, near in
            isNearTop = near
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        // The date is the title of the page, where a newspaper puts it. Not the
        // name of the section : the tab bar says that already, and a page that
        // repeats its own label has spent a line saying nothing. A dateline says
        // what the label did not, which is how old what follows is allowed to be.
        //
        // A large title like every other section's, so it shrinks into the bar
        // as the reader scrolls into the page.
        .navigationTitle(Text(verbatim: Self.today()))
        // The sources in one corner, the reader's own menu in the other, the
        // same way round in every section.
        .toolbar {
            ToolbarItem(placement: .sectionLeading) {
                SourcesButton(open: open)
            }
            ToolbarItem(placement: .sectionLeading) {
                NotificationsButton(model: model)
            }
            ToolbarItem(placement: .primaryAction) {
                ReaderMenu(model: model, open: open)
            }
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
        // model's work carries on behind it, and the page is read back once the
        // control has retracted rather than under it.
        //
        // A Mac has no pull and keeps `⌘R` in the reader's own menu, which is
        // where the command lives on every platform.
        .refreshable {
            isPulling = true
            await model.pullToRefresh()
            isPulling = false
        }
        // **The page is put back where the pull started.**
        //
        // SwiftUI holds the refresh control out until the gesture's work
        // returns, and the space it held is not always given back : the page
        // stays pushed down by exactly its height, with the large title still
        // open, until anything at all touches the screen and forces a layout.
        // That fault is why the gesture was taken out of the application once
        // already, and four attempts at its cause missed. None of them could be
        // reproduced on a simulator either, where a synthesised drag never
        // engages the control at all.
        //
        // So this does not try to diagnose it. It asks for the one outcome the
        // reader wants, which is the page back at its top, and asking moves the
        // scroll view whether or not it had reclaimed the inset on its own.
        //
        // A beat first, so it is not fighting the control on the way out.
        //
        // And only when the reader is still near the top. A pull starts there,
        // but a refresh takes seconds and they may have scrolled off to read
        // something ; hauling them back would be the application taking the
        // page away from them.
        .onChange(of: isPulling) { _, pulling in
            guard !pulling, isNearTop else { return }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(edge: .top) }
            }
        }
        // Not while something is being brought in. `Nothing has come in yet`
        // over a page that is at that moment fetching sixty feeds is untrue,
        // and it is untrue at the one moment the reader is most likely to be
        // looking : the first launch after an import.
        .overlay {
            if model.digest.isEmpty, model.currentWork == nil {
                empty
            }
        }
        .task { await model.loadLooseArticles() }
    }

    // MARK: - The page

    @ViewBuilder
    private var stories: some View {
        if !model.digest.live.isEmpty {
            header {
                HStack(spacing: 7) {
                    LiveDot()
                    // The dot's own colour at the quiet end of its pulse : the
                    // dot is the loud thing and the word is what it means, so
                    // the pair reads as one mark rather than as two red things.
                    Text("Live stories").foregroundStyle(LiveDot.quietTint)
                }
            }
            ForEach(model.digest.live) { story in
                row(story)
            }
        }

        if !model.digest.stories.isEmpty {
            // Not "Front page" : that is what the pill above already says, and
            // a page does not need to name itself twice.
            header {
                switch model.digestTopic {
                case .frontPage: Text("Stories")
                case .named(let topic): Text(verbatim: topic)
                }
            }
            ForEach(model.digest.stories) { story in
                row(story)
            }
        }

        if model.digest.looseCount > 0 {
            header { Text("The rest") }
            ForEach(model.looseArticles.prefix(40)) { article in
                ArticleRow(article: article, zoom: zoom) { open(.article(article.id)) }
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

    private func row(_ story: DigestStory) -> some View {
        StoryRow(story: story, isLead: story.id == leadID, zoom: zoom) {
            open(.story(story.id))
        }
    }

    /// The first story on the page runs its picture across the column.
    ///
    /// A page where every story is the same size is a list, and a list makes the
    /// reader do the ranking the digest exists to do. One lead, and the rest set
    /// smaller, is how a front page has said what matters for two centuries.
    private var leadID: UUID? {
        model.digest.live.first?.id ?? model.digest.stories.first?.id
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
                Text("Add a feed, or import an OPML file to bring your subscriptions over.")
            } actions: {
                Button("Add a feed") { isAddingFeed = true }
                Button("Import an OPML file") { isChoosingFile = true }
            }
        } else if let name = model.digestTopic.name {
            ContentUnavailableView {
                Label(title: { Text(verbatim: name) }, icon: { Image(systemName: "square.stack.3d.up") })
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

    /// How far down the page still counts as being at the top of it.
    ///
    /// About a story's worth. Inside that the reader has not gone anywhere and
    /// is looking at a page pushed out of place ; past it they have left the
    /// head of the page deliberately.
    private static let stillAtTheTop: CGFloat = 240

    /// Today, spelled the way the reader's language spells it.
    ///
    /// Read at each render rather than held : the page is rebuilt on returning
    /// to the foreground, which is when a date left open overnight would
    /// otherwise be yesterday's.
    private static func today(_ date: Date = .now) -> String {
        let spelled = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        // Only the first letter : French writes `samedi 29 août`, and
        // capitalizing every word would give `Samedi 29 Août`.
        return spelled.prefix(1).localizedUppercase + spelled.dropFirst()
    }

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
            .modifier(PillShape(isCurrent: model.digestTopic == topic, topic: topic, namespace: pills))
        } else {
            Menu {
                preferences(for: topic)
            } label: {
                label(topic, title: title)
            } primaryAction: {
                choose(topic)
            }
            .buttonStyle(.plain)
            .modifier(PillShape(isCurrent: model.digestTopic == topic, topic: topic, namespace: pills))
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

        return HStack(spacing: 4) {
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
        .foregroundStyle(isCurrent ? Color.white : Color.primary)
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
    let zoom: Namespace.ID
    let open: () -> Void

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
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }

    private var lead: some View {
        VStack(alignment: .leading, spacing: 10) {
            if story.imageURL != nil {
                RemoteImage(url: story.imageURL, credit: story.imageCredit, corner: 10)
                    .padding(.bottom, 2)
            }
            VStack(alignment: .leading, spacing: 7) {
                masthead(headline: .title2)
                whatHappened
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
                whatHappened

                if story.imageURL != nil {
                    RemoteImage(url: story.imageURL, credit: story.imageCredit, width: Self.thumbnailWidth)
                }
            }
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
                rubric
                    .font(.system(.caption2, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Text(verbatim: story.title)
                .font(Editorial.headline(headline))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The subjects a story is filed under.
    ///
    /// Built as one `Text` rather than a row of views, so it stays a line of
    /// type : it is set above a headline like a rubric above a piece, and a
    /// stack of labels there would read as a control.
    ///
    /// They used to be marked where the model had named one itself. It names
    /// none now : every one of these is a section the reader has, so there is
    /// no difference left to draw.
    private var rubric: Text {
        Text(verbatim: story.topics.joined(separator: " · "))
    }

    /// What happened and who is saying it, which is what a picture sits beside.
    private var whatHappened: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let summary = story.summary, !summary.isEmpty {
                Text(verbatim: summary)
                    .font(Editorial.standfirst)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            facts
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(spacing: 3) {
            ForEach(story.feedMarks) { mark in
                SourceStamp(domain: mark.room, side: 14, showsName: false)
            }

            if story.feedCount > story.feedMarks.count {
                Text(verbatim: "+\(story.feedCount - story.feedMarks.count)")
                    .lineLimit(1)
                    .padding(.leading, 1)
            }
        }
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
    private var facts: some View {
        ViewThatFits(in: .horizontal) {
            factsLine()
            factsLine(sparkline: false)
            factsLine(sparkline: false, articles: false)
        }
        .font(Editorial.metadata)
        .foregroundStyle(.tertiary)
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

            if story.isGenerated {
                Image(systemName: "sparkles")
                    .accessibilityLabel(Text("Written by the model"))
                    .help(Text("Written by the model"))
            }
            Text(story.lastAt, format: .relative(presentation: .numeric))
                .lineLimit(1)
        }
    }
}

/// One article, in a list of articles.
struct ArticleRow: View {
    let article: ArticleSummary
    var showsImage = true
    let zoom: Namespace.ID
    let open: () -> Void

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
        let title = Text(verbatim: article.title)
        guard article.isRead else { return title }

        return title + Text(verbatim: "  ")
            + Text(Image(systemName: "checkmark")).font(.caption2).foregroundStyle(.tertiary)
    }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    headline
                        .font(Editorial.headline(.body))
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
                    .font(Editorial.metadata)
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
private struct PillShape: ViewModifier {
    let isCurrent: Bool
    let topic: DigestTopic
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .glassEffect(
                isCurrent ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                in: .capsule
            )
            .glassEffectID(topic, in: namespace)
            .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}

/// What the machinery is doing, said in one line over a rule that fills.
///
/// **The page said nothing about any of it.** A pass that fetched three hundred
/// feeds, wrote sixty headlines and exchanged with iCloud was, to the reader,
/// a page that changed under them for no stated reason, or worse, a page that
/// had not changed yet and gave no sign that it was about to.
///
/// **One bar for the whole pass, and the words above it change.** Every stage
/// used to carry its own count, so a single pass ran a bar from nothing to full
/// five times over. A reader doing one thing and waiting for one answer does
/// not read that as progress ; they read it as an application that keeps
/// starting over. ``WorkPlan`` weighs the stages against each other so the bar
/// crosses the lot once.
///
/// **It keeps its place whether or not there is anything to say.** A row that
/// appears and disappears moves the whole page under the reader's thumb twice
/// per pass. The band stays and its contents fade, which costs one line of
/// quiet under the pills and takes the jolt out of every refresh.
///
/// It lives inside the pinned header rather than in the safe area, for the same
/// reason the pills do : a bar in the safe area lays itself out under the large
/// title and draws itself somewhere else entirely.
private struct ActivityLine: View {
    let work: WorkPlan?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How tall the band is while there is something in it.
    ///
    /// It follows the type size, since what sits in it is one line of type over
    /// a rule inside a capsule. Nought the rest of the time : a place kept
    /// permanently is a hand's width of nothing under the subjects on every
    /// page, for a line that is there a few seconds an hour.
    @ScaledMetric(relativeTo: .caption) private var open: CGFloat = 40

    /// What the band is worth right now.
    private var height: CGFloat { work == nil ? 0 : open }

    var body: some View {
        ZStack(alignment: .top) {
            if let work {
                content(work)
                    // Glass of its own, like the pills above it, rather than a
                    // slab of the page's own ground running the full width. The
                    // header is pinned and the stories pass behind it, so
                    // something has to come between the two ; a band of opaque
                    // paper reads as a shelf bolted to the page, and this is a
                    // control floating over it, which is the layer the material
                    // is for.
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
                    // Fading as it goes, which is what lets the band be
                    // measured without being clipped : see below.
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // **It takes the room it needs and gives it back.** A place kept for it
        // whether or not anything is happening is quiet under the subjects on
        // every page ; a row that simply appears moves the whole page under the
        // reader's thumb. So the band grows into its height and shrinks out of
        // it, over a third of a second, which is a page making room rather than
        // a page jumping. The height is what is animated rather than the row's
        // presence, since a pinned header measuring a child that has just been
        // inserted lands on the answer a frame late and that frame is the jolt.
        //
        // **And it is not clipped to that height.** Glass casts a soft shadow,
        // and a rectangular clip cuts it off where it is still dark : what the
        // reader saw was a grey oblong with hard edges sitting behind a
        // capsule with round ones. Unclipped, the capsule spills a little
        // during the third of a second it is growing or shrinking, which is
        // covered by the fade happening over exactly the same third of a
        // second, and it spills downwards into the rubric's own top rhythm
        // rather than upwards into the subjects.
        .frame(height: height, alignment: .top)
        .animation(reduceMotion ? nil : .snappy(duration: 0.32), value: height)
        .animation(.snappy(duration: 0.28), value: work?.phase)
        // Nothing here answers to a finger : the pull underneath it is the
        // gesture, and two in one place is one the reader cannot aim.
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(work.map { Text($0.phase.title) } ?? Text(""))
        .accessibilityValue(value)
        .accessibilityHidden(work == nil)
        // So VoiceOver does not read every batch out as it lands.
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func content(_ work: WorkPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // **The words and the rule, and no figures.** A count beside them
            // is a second measure of the same thing, disagreeing with the first
            // : the rule is the whole pass and a figure can only ever be the
            // step, so `9 of 112` sat under a bar four fifths of the way along
            // and the reader had to work out which of the two to believe. The
            // bar says how far ; the words say what.
            Text(work.phase.title)
                .lineLimit(1)
                .font(Editorial.metadata)
                .foregroundStyle(.secondary)
            bar(work)
        }
        // The capsule runs the measure of the column, like the row of pills
        // above it, so the rule inside it has something to fill.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A rule that fills, which is the page's own idiom : the stories are
    /// separated by rules, and this is one of them saying how far along the
    /// pass is by how much of it is inked.
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
