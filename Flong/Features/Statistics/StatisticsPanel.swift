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

    /// Carries a pill's glass from one window to the next.
    @Namespace private var pills

    var body: some View {
        ScrollView {
            // The window sits at the head of the page and stays there, the way
            // the subjects do on the front page. A pinned section header rather
            // than a bar in the safe area, for the reason the digest gives : a
            // bar lays out under the title and draws itself somewhere else.
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    page
                } header: {
                    ranges
                }
            }
            .editorialColumn()
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .safeAreaInset(edge: .top, spacing: 0) { head }
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

    // MARK: - The head

    /// What the page is, and the way out on the platform that needs one.
    private var head: some View {
        HStack(spacing: 14) {
            Text("Statistics")
                .font(theme.headline(.title3))

            Spacer(minLength: 8)

            PanelDismiss()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .background(alignment: .bottom) {
            // The paper under it rather than a material : the pills below are
            // the glass on this page, and a second surface directly above them
            // is the stacking the guidance forbids.
            Rectangle().fill(theme.paper(in: scheme)).ignoresSafeArea()
        }
    }

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
    private var ranges: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(StatisticsRange.allCases) { range in
                        pill(range)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
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
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
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
                VStack(alignment: .leading, spacing: 22) {
                    figures(report)
                    flow(report)
                    day(report)
                    sources(report)
                    subjects(report)
                    people(report)
                    bylines(report)
                    bodies(report)
                    languages(report)
                }
                .padding(.top, 6)
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
            Text("Nothing arrived over this stretch")
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
        let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

        return LazyVGrid(columns: columns, spacing: 16) {
            Figure(
                value: Text(report.arrived.formatted()),
                caption: Text("Articles"),
                footnote: change(from: report.previous?.arrived, to: report.arrived)
            )
            Figure(
                value: Text(report.read.formatted()),
                caption: Text("Read"),
                footnote: report.arrived > 0 && report.read > 0
                    ? Text("\(share(report.read, of: report.arrived)) of them") : nil
            )
            Figure(
                value: Text(report.publishers.formatted()),
                caption: Text("Sources"),
                footnote: Text("\(report.feeds) feeds")
            )
            Figure(
                value: Text(report.duplicates.formatted()),
                caption: Text("Said twice"),
                footnote: report.duplicates > 0
                    ? Text("\(share(report.duplicates, of: report.arrived + report.duplicates)) of arrivals") : nil
            )
        }
    }

    /// How much more or less than the window before, where there was one.
    private func change(from before: Int?, to now: Int) -> Text? {
        guard let before, let change = Statistics.change(from: before, to: now) else { return nil }
        let written = change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))
        return Text("\(written) on the stretch before")
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
        card(Text("The flow"), note: report.showsReading ? Text("Arrivals, and what you read") : nil) {
            FlowChart(flow: report.flow, grain: report.grain, showsReading: report.showsReading)
        }
    }

    private func day(_ report: Statistics) -> some View {
        card(Text("Through the day")) {
            HStack(spacing: 18) {
                DayDial(
                    arrivals: report.arrivalsByHour,
                    reading: report.readingByHour,
                    showsReading: report.showsReading
                )
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The publishers, loudest first, each with its own shape beside it.
    ///
    /// **Named by what the sources list calls them.** A publisher is one row
    /// there whatever number of feeds it is followed through, and the name is
    /// the reader's own where they have given it one : two places calling
    /// `lemonde.fr` two different things is two places to keep true.
    private func sources(_ report: Statistics) -> some View {
        card(Text("Who published")) {
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

            if !source.flow.isEmpty {
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
            card(Text("Subjects"), note: Text("As the digest filed the stories")) {
                RankedBars(entries: report.subjects, counted: .stories)
            }
        }
    }

    @ViewBuilder
    private func people(_ report: Statistics) -> some View {
        if !report.people.isEmpty {
            card(Text("In the news")) {
                RankedBars(entries: report.people)
            }
        }
    }

    @ViewBuilder
    private func bylines(_ report: Statistics) -> some View {
        if !report.bylines.isEmpty {
            card(Text("Bylines")) {
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

    /// What each source actually puts in its feed.
    ///
    /// **The one card here about the feeds rather than about the news.** A feed
    /// may carry the whole piece or a headline and a link, and nothing else in
    /// the application ever says which : a reader learns it by tapping through
    /// the same publisher for the tenth time and wondering why. Measured on a
    /// real corpus, more than half of every body stored is under two hundred
    /// characters and one paper's median is six.
    ///
    /// **Two short lists rather than a ranking of forty.** The question is not
    /// where a source places, it is which of the two kinds it is, and the
    /// middle of the list is where a reader would have to decide that for
    /// themselves. The ends say it.
    @ViewBuilder
    private func bodies(_ report: Statistics) -> some View {
        if report.bodies.count >= 4 {
            let generous = report.bodies.prefix(4)
            let terse = report.bodies.suffix(4).reversed()

            card(Text("What lands in the feed")) {
                VStack(alignment: .leading, spacing: 16) {
                    lengths(Text("They give you the article"), Array(generous))
                    lengths(Text("They give you a headline"), Array(terse))
                }
            }
        }
    }

    private func lengths(_ title: Text, _ sources: [BodyLength]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            title
                .font(theme.metadata)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            ForEach(sources) { source in
                let identity = source.domain.flatMap { publishers[$0] }

                HStack(spacing: 8) {
                    SourceIconView(identity: identity, side: 16)
                    Text(verbatim: identity?.name ?? source.name)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    // Characters and not words : a language is not a number of
                    // words per idea, and the two lists are read against each
                    // other rather than against a reading speed.
                    Text("\(source.median) signs")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
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
                    .lineLimit(2)
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
