//
//  StatisticsPanel.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What the reader's stream adds up to.
///
/// **A page and not a dashboard.** A dashboard is a wall of gauges about a
/// machine somebody operates ; nobody operates a feed reader. What is here is a
/// page about a person's reading, read the way any other page is : from the top,
/// in order, in the same type as the rest of the application. The figures are
/// large because they are the headline, the charts are quiet because they are
/// the picture, and there is no needle, no dial to the red and nothing that
/// scores anybody.
///
/// **It refuses the one number a feed reader is usually about.** There is no
/// unread count here and there is no streak. The stream carries neither on
/// purpose : section 5 has the wire as something to watch rather than something
/// to finish, and a page that opened on `vous êtes en retard de 4 812 articles`
/// would undo that in one line. Everything counted here is something that
/// happened, never something outstanding.
///
/// **The window is the whole interaction.** Eight of them, from a day to the
/// lot, and every figure and every chart is about the one the reader picked.
/// They sit on glass at the head of the page and stay there as it scrolls,
/// since a filter that leaves the screen is a filter a reader has to go back up
/// to change.
struct StatisticsPanel: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.publishers) private var publishers
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.calendar) private var calendar

    /// Carries a pill's glass from one window to the next.
    @Namespace private var pills

    var body: some View {
        ScrollView {
            page
                .editorialColumn()
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
        }
        // **The windows are a bar and not a pinned header any more.**
        //
        // They were a pinned section header, the way the subjects are on the
        // front page, and that is why three helpings of air round them changed
        // nothing : a pinned header keeps its place in the scroll and draws no
        // ground of its own, so the padding round the pills was space the cards
        // were passing through rather than space between them. Eight points,
        // then thirteen, then twenty-two, and the card was against the pill
        // every time, because what was under the pill was the card.
        //
        // An inset in the safe area reserves the room instead. The page is laid
        // out below it, so the air is air ; the soft edge under it is what the
        // cards go into as they pass, which is still something moving behind
        // the glass and still the reason the glass is there.
        .safeAreaInset(edge: .top, spacing: 0) { windows }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .themed()
        // Read when the page opens and whenever the window changes, and put
        // down on the way out : see ``AppModel/statistics``.
        .task(id: model.statisticsRange) {
            await model.loadStatistics(for: model.statisticsRange)
        }
        .onDisappear { model.forgetStatistics() }
    }

    // MARK: - The head there is not

    /// **Untitled, and the windows are the head of it.**
    ///
    /// It carried `Statistiques` in the theme's own headline face, over the row
    /// of windows, which is a line spent naming the page to a reader who
    /// arrived by pressing the one control that opens it. What it cost was the
    /// top of the screen : the figures are the thing, and a bar above the
    /// filter above them pushed the first of them down out of the opening view.
    ///
    /// The windows say what the page is anyway. A row reading `24 h` and
    /// `1 semaine` over a column of counts is not a page anybody has to be told
    /// the name of, and ``ReaderPanel`` drops its own title for the neighbouring
    /// reason : a panel that opens on the thing itself needs no word about it.
    ///
    /// **A Mac still needs its way out**, and gets that and nothing else. A
    /// sheet on iOS is flicked away and the indicator at the top says so ; a Mac
    /// sheet cannot be flicked, and a reader with no button is a reader
    /// stranded. See ``PanelDismiss``.
    #if os(macOS)
        private var wayOut: some View {
            HStack {
                Spacer(minLength: 0)
                PanelDismiss()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .background(alignment: .bottom) {
                // The paper under it rather than a material : the pills below
                // are the glass on this page, and a second surface directly
                // above them is the stacking the guidance forbids.
                Rectangle().fill(theme.paper(in: scheme)).ignoresSafeArea()
            }
        }
    #endif

    /// The eight windows, on glass, at the head of the page.
    ///
    /// **This is where the material belongs and the one place it does.** A pill
    /// is a control floating over a page that moves behind it, which is the
    /// layer Apple's glass is for : the charts pass underneath as the reader
    /// scrolls, and the row shows them through itself. Everything else here is
    /// content, and content is ink on paper.
    ///
    /// One container for the eight, so the glass merges where they meet rather
    /// than stacking eight sheets side by side, and the chosen one carries its
    /// own identity through the change : the colour slides from the pill that
    /// was to the pill that is instead of blinking between them.
    private var windows: some View {
        VStack(spacing: 0) {
            #if os(macOS)
                wayOut
            #endif

            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(StatisticsRange.allCases) { range in
                            pill(range)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, Figures.brim)
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        // The page's own ground, so what passes underneath goes into the soft
        // edge rather than up against the pills.
        .background {
            Rectangle().fill(theme.paper(in: scheme)).ignoresSafeArea(edges: .top)
        }
    }

    private func pill(_ range: StatisticsRange) -> some View {
        let isCurrent = model.statisticsRange == range

        return Button {
            guard !isCurrent else { return }
            model.statisticsRange = range
        } label: {
            Text(range.name)
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isCurrent ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
            in: .capsule
        )
        .glassEffectID(range, in: pills)
        .accessibilityIdentifier(range.identifier)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    // MARK: - The page

    @ViewBuilder
    private var page: some View {
        if let report = model.statistics {
            if report.isEmpty {
                nothing
            } else {
                VStack(alignment: .leading, spacing: Figures.gap) {
                    figures(report)
                    flow(report)
                    hours(report)
                    weekdays(report)
                    days(report)
                    sources(report)
                    subjects(report)
                    people(report)
                    bylines(report)
                    languages(report)
                }
            }
        } else if model.isCounting {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        }
    }

    /// A window with nothing in it, which is a fact about the window rather
    /// than a failure.
    private var nothing: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie")
                .font(.system(size: 34))
                .foregroundStyle(.quaternary)
            Text("No articles over this period")
                .font(theme.standfirst(.subheadline))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    // MARK: - The headline figures

    /// Four numbers, large, on the page rather than in a card.
    ///
    /// **The page opens on them for the reason ``ReaderPanel`` opens on a
    /// face.** They are what the reader came for ; everything under them is the
    /// working. Each carries one line under it, and the line is the thing that
    /// makes a number mean anything : how it compares with the window before,
    /// or what share of the whole it is.
    private func figures(_ report: Statistics) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: Figures.gap),
            GridItem(.flexible(), spacing: Figures.gap),
        ]

        return LazyVGrid(columns: columns, spacing: Figures.gap) {
            Figure(
                value: Text(report.arrived.formatted()),
                caption: Text("Articles"),
                footnote: change(from: report.previous?.arrived, to: report.arrived)
            )
            Figure(
                value: Text(report.read.formatted()),
                caption: Text("Read"),
                footnote: report.arrived > 0 && report.read > 0
                    ? Text("\(share(report.read, of: report.arrived)) of the articles") : nil
            )
            Figure(
                value: Text(report.publishers.formatted()),
                caption: Text("Sources"),
                footnote: Text("\(report.feeds) feeds")
            )
            Figure(
                value: Text(report.duplicates.formatted()),
                caption: Text("Duplicates"),
                footnote: report.duplicates > 0
                    ? Text("\(share(report.duplicates, of: report.arrived + report.duplicates)) of the total") : nil
            )
        }
    }

    /// What the window before held, where there was one.
    ///
    /// **The count and not a change in per cent.** It read
    /// `+915 % par rapport à la période précédente`, which is three problems in
    /// one line : it does not fit, so at a large type size it truncated in the
    /// middle of a word ; a device collecting for ten days makes a number like
    /// that out of nothing ; and a percentage of a percentage is arithmetic the
    /// reader has to undo to get at the fact. `Période précédente : 391` beside
    /// `3 989` is the same comparison, made by the reader, in four words.
    ///
    /// **And it is two words rather than four.** `Période précédente` is itself
    /// two lines in a tile at an accessibility size, which left the number it
    /// was introducing off the end of the third. The window is named on the
    /// pill at the top of the page, so `Avant` is the whole of what has to be
    /// said here.
    private func change(from before: Int?, to now: Int) -> Text? {
        guard let before, before > 0 else { return nil }
        return Text("Before: \(before)")
    }

    /// One count as a share of another, written the way a share is read.
    ///
    /// **A share that rounds to nothing is written with a figure in it.**
    /// Twenty-three articles out of four thousand eight hundred is half a
    /// percent, and `0 %` says the reader read none of them, which is not what
    /// happened. Under a percent it keeps one significant figure ; above it,
    /// nobody wants the decimal.
    private func share(_ part: Int, of whole: Int) -> String {
        let share = Double(part) / Double(whole)
        return share > 0 && share < 0.01
            ? share.formatted(.percent.precision(.significantDigits(1)))
            : share.formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: - The cards

    private func flow(_ report: Statistics) -> some View {
        card(Text("Articles received"), note: report.showsReading ? Text("Received and read") : nil) {
            FlowChart(flow: report.flow, grain: report.grain, showsReading: report.showsReading)
        }
    }

    /// The hours of a day, round a clock.
    private func hours(_ report: Statistics) -> some View {
        card(Text("Articles per hour")) {
            centred {
                Dial(
                    counts: report.arrivalsByHour,
                    reading: report.readingByHour,
                    marks: [0: "0", 6: "6", 12: "12", 18: "18"],
                    middle: { Text(Self.hour($0), format: .dateTime.hour()) },
                    caption: "Peak hour",
                    spoken: "Articles per hour",
                    showsReading: report.showsReading
                )
            }
        }
    }

    /// The days of a week, round a dial that starts where the reader's week
    /// does.
    ///
    /// **Turned to the reader's own first weekday.** SQLite counts a week from
    /// Sunday whatever anybody's calendar says, so the counts arrive in that
    /// order and are rotated here : a French reader's dial begins on Monday and
    /// an American one on Sunday, and neither of them is being shown somebody
    /// else's week.
    @ViewBuilder
    private func weekdays(_ report: Statistics) -> some View {
        let first = calendar.firstWeekday - 1
        let order = (0..<7).map { ($0 + first) % 7 }
        let symbols = calendar.veryShortStandaloneWeekdaySymbols

        if report.range.turns(every: Cycle.week) {
            card(Text("Articles per weekday")) {
                centred {
                    Dial(
                        counts: order.map { report.arrivalsByWeekday[$0] },
                        reading: order.map { report.readingByWeekday[$0] },
                        marks: Dictionary(
                            uniqueKeysWithValues: order.enumerated().map { place, weekday in
                                (place, symbols.indices.contains(weekday) ? symbols[weekday] : "")
                            }
                        ),
                        middle: { Text(verbatim: Self.weekday(order[$0], in: calendar)) },
                        caption: "Peak day",
                        spoken: "Articles per weekday",
                        showsReading: report.showsReading
                    )
                }
            }
        }
    }

    /// The days of a month, round a dial of thirty-one.
    ///
    /// **The last three spokes stand for fewer days than the others**, a
    /// thirty-first coming round in seven months of twelve, so over a long
    /// window they are quieter for a reason that is about the calendar rather
    /// than about the news. The count is what the card says it is : see
    /// ``Statistics/arrivalsByDay``.
    @ViewBuilder
    private func days(_ report: Statistics) -> some View {
        if report.range.turns(every: Cycle.month) {
            card(Text("Articles per day of the month")) {
                centred {
                    Dial(
                        counts: report.arrivalsByDay,
                        reading: report.readingByDay,
                        marks: [0: "1", 9: "10", 19: "20", 29: "30"],
                        middle: { Text(verbatim: ($0 + 1).formatted()) },
                        caption: "Peak day",
                        spoken: "Articles per day of the month",
                        showsReading: report.showsReading
                    )
                }
            }
        }
    }

    /// A dial sits in the middle of its card, the drawing being the whole of
    /// what the card holds.
    private func centred(@ViewBuilder _ dial: () -> some View) -> some View {
        HStack {
            Spacer(minLength: 0)
            dial()
            Spacer(minLength: 0)
        }
    }

    /// A moment standing for an hour of the day, so the hour is written the way
    /// the reader's own clock writes it : `17 h` or `5 PM`, never both.
    private static func hour(_ hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
    }

    /// A day of the week by its own name, Sunday being nought.
    private static func weekday(_ weekday: Int, in calendar: Calendar) -> String {
        let names = calendar.standaloneWeekdaySymbols
        guard names.indices.contains(weekday) else { return "" }
        return names[weekday].localizedCapitalized
    }

    /// The publishers, loudest first, each with its own shape beside it.
    ///
    /// **Named by what the sources list calls them.** A publisher is one row
    /// there whatever number of feeds it is followed through, and the name is
    /// the reader's own where they have given it one : two places calling
    /// `lemonde.fr` two different things is two places to keep true.
    private func sources(_ report: Statistics) -> some View {
        card(Text("Sources")) {
            VStack(spacing: 0) {
                ForEach(Array(report.sources.enumerated()), id: \.element.id) { index, source in
                    if index > 0 {
                        Divider().padding(.leading, 30)
                    }
                    row(source, loudest: report.sources.first?.count ?? 1)
                }
            }
        }
    }

    private func row(_ source: SourceTally, loudest: Int) -> some View {
        let identity = source.domain.flatMap { publishers[$0] }

        return HStack(spacing: 10) {
            SourceIconView(identity: identity, side: 20)

            Text(verbatim: identity?.name ?? source.name)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            // **The shape goes when the type grows.** It is a picture of the
            // row and the number beside it is the row's fact : holding sixty
            // points for the picture at an accessibility size cut
            // `news.ycombinator.com` down to `news.yc…`, which is the one thing
            // in the row nobody can do without.
            if !source.flow.isEmpty, !typeSize.isAccessibilitySize {
                Sparkline(values: source.flow)
                    .frame(width: 62, height: 18)
            }

            Text(source.count.formatted())
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(source.count == loudest ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(minWidth: 34, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: identity?.name ?? source.name))
        .accessibilityValue(Text("\(source.count) articles"))
    }

    /// What it was all about, as the digest filed it.
    ///
    /// **Said to be about the stories and not about the stream.** A subject
    /// reaches an article through the story it was grouped into, and the digest
    /// groups what it can : a page that headed this `vos sujets` would be
    /// claiming a reading of every article, and the line under the title is
    /// what keeps it honest.
    @ViewBuilder
    private func subjects(_ report: Statistics) -> some View {
        if !report.subjects.isEmpty {
            card(Text("Subjects"), note: Text("Number of stories")) {
                RankedBars(entries: report.subjects, counted: .stories)
            }
        }
    }

    @ViewBuilder
    private func people(_ report: Statistics) -> some View {
        if !report.people.isEmpty {
            card(Text("Newsmakers")) {
                RankedBars(entries: report.people)
            }
        }
    }

    @ViewBuilder
    private func bylines(_ report: Statistics) -> some View {
        if !report.bylines.isEmpty {
            card(Text("Authors")) {
                RankedBars(entries: report.bylines)
            }
        }
    }

    /// What the stream is written in, as one bar and a line of names.
    @ViewBuilder
    private func languages(_ report: Statistics) -> some View {
        if report.languages.count > 1 {
            let named = report.languages.map { Tally(name: Self.language($0.name), count: $0.count) }

            card(Text("Languages")) {
                VStack(alignment: .leading, spacing: 12) {
                    ShareBar(shares: named)
                    legend(named)
                }
            }
        }
    }

    /// The names under the bar.
    ///
    /// **Only what rounds to a percent.** A corpus of four thousand articles
    /// carries a Catalan one and a Vietnamese one, and a legend reading
    /// `Catalan 0 %` is a line spent saying nothing. They keep their sliver of
    /// the bar, which is where a share of nothing belongs, and lose their name.
    private func legend(_ shares: [Tally]) -> some View {
        let total = max(shares.reduce(0) { $0 + $1.count }, 1)
        let named = shares.prefix(5).enumerated().filter { Double($1.count) / Double(total) >= 0.01 }

        return FlowLayout(spacing: 12) {
            ForEach(named, id: \.element.id) { index, tally in
                HStack(spacing: 5) {
                    Circle()
                        .fill(ShareBar.tint(index))
                        .frame(width: 7, height: 7)
                    Text(verbatim: tally.name)
                        .font(.caption)
                    Text(verbatim: share(tally.count, of: total))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// A language tag as its own name, in the reader's language.
    ///
    /// `en` is not a word. What a reader wants to see is `anglais`, which the
    /// system knows and no catalogue of mine should have to hold in every
    /// language there is.
    private static func language(_ tag: String) -> String {
        Locale.current.localizedString(forLanguageCode: tag)?.localizedCapitalized ?? tag.uppercased()
    }

    // MARK: - The shape every card takes

    /// One card : a heading, a line under it where the figures need one, and
    /// the drawing.
    private func card(
        _ title: Text,
        note: Text? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(theme.headline(.subheadline))
                if let note {
                    note
                        .font(theme.metadata)
                        .foregroundStyle(.tertiary)
                }
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Figures.padding)
        .background(theme.surface(in: scheme), in: .rect(cornerRadius: Figures.corner))
    }
}

/// One headline number, its name, and the line that makes it mean something.
struct Figure: View {
    let value: Text
    let caption: Text
    var footnote: Text?

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            value
                .font(theme.headline(.title))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())

            caption
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let footnote {
                footnote
                    .font(theme.metadata)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
                    .padding(.top, 2)
            }
        }
        // **The whole height it is offered, and the grid offers a row's
        // tallest.** One footnote wraps to two lines and the other does not,
        // and two tiles of different heights side by side read as two different
        // kinds of thing.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(theme.surface(in: scheme), in: .rect(cornerRadius: Figures.corner))
        .accessibilityElement(children: .combine)
    }
}

/// Lays a row of small things out and wraps them when the line runs out.
///
/// The legend under the languages, and nothing else so far. An `HStack` would
/// push five names off the edge on a narrow phone at a large type size, and a
/// `LazyVGrid` would column them, which is the wrong shape for a run of labels
/// of five different widths.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = self.lines(subviews, width: proposal.width ?? .infinity)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(lines.count - 1, 0))
        let width = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(_ subviews: Subviews, width available: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            if needed > available, !line.indices.isEmpty {
                lines.append(line)
                line = Line()
            }
            line.width = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.indices.append(index)
        }

        if !line.indices.isEmpty { lines.append(line) }
        return lines
    }
}
