//
//  StatisticsCharts.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Charts
import SwiftUI

/// The few decisions every drawing on the page of figures shares.
///
/// **The ink is the page's own, and the colour is the accent.** A page of nine
/// charts in nine palettes is a dashboard ; a page where everything is drawn in
/// the type's own colour, and the one thing worth pointing at is drawn in the
/// one colour that means "this", is a page. It inverts with the paper and it
/// follows the theme, because both of those are what the ink and the accent
/// already do.
nonisolated enum Figures {
    /// What a count is drawn in : the page's own ink, held back so a chart is
    /// a picture of the page rather than the loudest thing on it.
    static let inkOpacity: Double = 0.72

    /// What the quiet half of a pair is drawn in.
    static let quietOpacity: Double = 0.34

    /// The corner every card on the page is cut to.
    static let corner: CGFloat = 18

    /// The air inside one.
    static let padding: CGFloat = 16

    /// The air between one block and the next, everywhere on the page.
    ///
    /// **One number and not five.** The figures were sixteen apart in their
    /// grid, fourteen apart across it and twenty-two apart from the cards
    /// below, which reads as three different kinds of relationship between
    /// things that have one : they are all blocks on one page. Said once, the
    /// column has a rhythm ; said at each call site, it has a history.
    static let gap: CGFloat = 18

    /// The air above and below the row of windows.
    ///
    /// The row floats over the page and the page runs under it, so what it is
    /// standing in is the only thing separating it from the cards passing
    /// behind : too little and a pill reads as stuck to the card under it, and
    /// to the edge of the sheet above it. It was eight, then thirteen, and both
    /// were still a row wedged between two things.
    static let brim: CGFloat = 22

    /// How far a chart stands in from the edges of its card.
    ///
    /// Half of the widest date the axis ever writes, which is what the first
    /// and last labels hang into. Measured against `27 août` and `4 sept.` at
    /// the body size, which are about forty points wide.
    static let axisRoom: CGFloat = 26

    /// The shortest a bar is ever drawn.
    ///
    /// Something that happened once is something that happened, and a bar too
    /// short to see says it did not.
    static let floor: CGFloat = 3
}

// MARK: - The flow

/// How much arrived over the window, mark by mark, with the reading over it.
///
/// **Two series and one axis.** What a publisher sent and what the reader got
/// through are the same question asked twice, and drawing them apart would make
/// the reader compare two charts by eye. The arrivals are the bars, in the
/// page's own ink ; the reading is a line in the accent over them, and it is
/// drawn only where there is any : a flat line along the floor is a chart
/// saying nothing at the cost of half its ink.
///
/// **The scale is one, not two.** A reading of nine articles against an arrival
/// of nine hundred draws as nothing, and that is the honest picture : the line
/// is where it is because that is where it is. A second axis fitted to the
/// smaller series would draw the two as equals, which is the oldest lie a chart
/// tells.
///
/// The axis names a few dates and no counts. The tallest bar is written above
/// the chart instead, since one number said in words beats a ladder of five
/// nobody reads.
struct FlowChart: View {
    let flow: [Arrivals]
    let grain: StatisticsGrain
    /// Whether *when* the reader read is known well enough to be drawn : see
    /// ``Statistics/showsReading``.
    var showsReading = true

    @Environment(\.theme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var chosen: Date?

    /// Whether the reader has read anything at all in the window, which is
    /// what decides if the second series is drawn.
    private var hasReading: Bool { showsReading && flow.contains { $0.read > 0 } }

    private var peak: Int { max(flow.map(\.count).max() ?? 0, 1) }

    /// The mark the reader is pointing at, or the busiest one when they are
    /// pointing at nothing.
    private var current: Arrivals? {
        if let chosen, let mark = flow.min(by: { distance(of: $0) < distance(of: $1) }), distance(of: mark) < span {
            return mark
        }
        return flow.max { $0.count < $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            caption
            chart
        }
    }

    /// What the chart says in words, which is the one mark worth naming.
    ///
    /// The busiest, until the reader touches the chart, and then whichever they
    /// are touching. A line of type rather than a floating callout : a callout
    /// covers the bars it is about, and the page has room for a line.
    @ViewBuilder
    private var caption: some View {
        if let current {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(current.start, format: format)
                    .font(.subheadline.weight(.medium))
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                Text("\(current.count) articles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if hasReading, current.read > 0 {
                    Text(verbatim: "·")
                        .foregroundStyle(.tertiary)
                    Text("\(current.read) read")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.2), value: current)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(flow) { mark in
                BarMark(
                    x: .value(Text("Date"), mark.start, unit: grain.component),
                    y: .value(Text("Articles"), mark.count)
                )
                .foregroundStyle(bar(mark))
                .cornerRadius(3)
            }

            if hasReading {
                ForEach(flow) { mark in
                    LineMark(
                        x: .value(Text("Date"), mark.start, unit: grain.component),
                        y: .value(Text("Read"), mark.read),
                        series: .value(Text("Read"), 1)
                    )
                    .foregroundStyle(.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
            }
        }
        .chartYAxis(.hidden)
        // **The dates go when the type outgrows the chart.** Four of them
        // across a phone at an accessibility size is two of them hanging off
        // the ends, and the line above the chart already names the mark the
        // reader is on and how much fell in it. The shape survives ; the
        // labels are what there is no room for.
        .chartXAxis(typeSize.isAccessibilitySize ? .hidden : .automatic)
        .chartXAxis {
            // Three or four dates along the bottom and nothing else. A tick per
            // mark is a row of hairlines under a row of bars, and neither can
            // be read once they are that close.
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { _ in
                // `Color.secondary` and not the hierarchical `.secondary` : a
                // chart resolves a hierarchical style against its own
                // foreground, and the dates came out in the accent.
                AxisValueLabel(format: axisFormat, centered: false)
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartXSelection(value: $chosen)
        .frame(height: 148)
        // **The chart stands in from the card, and the dates bleed into that.**
        // A date is centred under the mark it names, so half of the first one
        // and half of the last hang off the ends of the plot : with the chart
        // running the full width of the card they were painted outside it, over
        // the rounded corner and onto the page.
        //
        // The room is taken here rather than through `chartPlotStyle`, which
        // insets the bars and leaves the labels centred on ticks at the frame's
        // own edges : the halves then hang off the frame instead of off the
        // plot, which is the same overflow one step further in. Padding the
        // chart moves the frame in, so what the labels hang into is the card's
        // own margin.
        .padding(.horizontal, Figures.axisRoom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Articles received"))
        .accessibilityValue(Text("\(flow.reduce(0) { $0 + $1.count }) articles"))
    }

    /// What one bar is drawn in.
    ///
    /// The ink, and the accent for the one the reader is pointing at, which is
    /// the only thing that changes as they move along the chart : a bar that
    /// also grew or brightened would be a chart that moves under the finger
    /// reading it.
    private func bar(_ mark: Arrivals) -> AnyShapeStyle {
        guard current?.start == mark.start, chosen != nil else {
            return AnyShapeStyle(Color.primary.opacity(Figures.inkOpacity))
        }
        return AnyShapeStyle(Color.accentColor)
    }

    /// How wide one mark is, which is how near the reader has to be for it to
    /// be the one they mean.
    private var span: TimeInterval {
        switch grain {
        case .hour: 3600
        case .day: 24 * 3600
        case .week: 7 * 24 * 3600
        case .month: 31 * 24 * 3600
        }
    }

    private func distance(of mark: Arrivals) -> TimeInterval {
        guard let chosen else { return .greatestFiniteMagnitude }
        return abs(mark.start.timeIntervalSince(chosen))
    }

    /// How the mark under the caption is named : an hour says the hour, a
    /// month says the month.
    private var format: Date.FormatStyle {
        switch grain {
        case .hour: .dateTime.weekday(.abbreviated).hour()
        case .day: .dateTime.weekday(.abbreviated).day().month(.abbreviated)
        case .week: .dateTime.day().month(.abbreviated)
        case .month: .dateTime.month(.wide).year()
        }
    }

    /// How a date along the bottom is written, which is shorter still.
    private var axisFormat: Date.FormatStyle {
        switch grain {
        case .hour: .dateTime.hour()
        case .day, .week: .dateTime.day().month(.abbreviated)
        case .month: .dateTime.month(.abbreviated)
        }
    }
}

// MARK: - The shape of a day, a week and a month

/// When articles arrive, around a dial of however many places the unit has.
///
/// **A dial and not a row of bars, because every unit here is round.** A day
/// wraps at midnight, a week at Sunday and a month at its last day, and a row of
/// bars says the opposite : it says the thing has a beginning and an end and
/// that the two are as far apart as they look. Midnight at the top and noon at
/// the bottom is the shape everybody already reads a clock in, and it is the
/// one arrangement in which the quiet small hours are a gap you can see rather
/// than a stretch at one end of a line.
///
/// **The busiest place is the one thing in colour.** Everything else is the
/// page's own ink, so the dial reads as one object with a mark on it rather
/// than as twenty-four things competing.
///
/// **The reader's own hours are the inner ring**, drawn only when they have
/// read something at a known place. It is a small ring inside a large one on
/// purpose : what arrives is a torrent and what anybody reads is a handful, and
/// two rings scaled to look alike would say the reader keeps up.
///
/// **One view for the three cards.** The hours of a day, the days of a week and
/// the days of a month differ in how many places they have, what is written
/// round the edge and what the hole in the middle says. Three views would be
/// three drawings to keep in step, and they would drift the first time one of
/// them was adjusted.
struct Dial: View {
    /// How many arrived in each place, in order.
    let counts: [Int]
    /// How many the reader read in each.
    let reading: [Int]
    /// What is written round the edge, by place.
    let marks: [Int: String]
    /// What the hole in the middle says about the busiest place.
    let middle: (Int) -> Text
    /// The word under the dial for what the middle is.
    let caption: LocalizedStringResource
    /// What a reader listening to the page is told the dial is about.
    let spoken: LocalizedStringResource
    /// Whether the reader's own places are known well enough to be drawn : see
    /// ``Statistics/showsReading``.
    var showsReading = true

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 168

    /// How far the spokes start from the middle, as a share of the dial.
    private static let hub: CGFloat = 0.38

    /// How far they may reach.
    ///
    /// **Short of what is written round the edge.** At ninety-six hundredths a
    /// spoke ends where the label sits, so the busiest one was drawn straight
    /// through the `L` of a Monday and through the `1` of a first of the month.
    /// What is left between is the air a word needs.
    private static let reach: CGFloat = 0.84

    private var peak: Int { max(counts.max() ?? 0, 1) }
    private var readPeak: Int { max(reading.max() ?? 0, 1) }
    private var hasReading: Bool { showsReading && reading.contains { $0 > 0 } }
    private var busiest: Int? {
        guard let most = counts.max(), most > 0 else { return nil }
        return counts.firstIndex(of: most)
    }

    /// How wide one spoke is drawn.
    ///
    /// **Thinner as there are more of them.** Five points is right for the
    /// twenty-four hours of a day and would have the seven days of a week
    /// drawn as seven fat wedges with the paper showing between them ; the
    /// share of its own slice that a spoke takes is what stays the same.
    ///
    /// Held under ten points however few there are. A week has seven places and
    /// a slice seventy points wide, and a third of that is a wedge rather than
    /// a spoke : a quiet Sunday beside a loud Monday came out as a lozenge
    /// lying on its side, which reads as a fault in the drawing.
    private var width: CGFloat {
        let slice = .pi * side * Self.reach / CGFloat(max(counts.count, 1))
        return min(max(slice * 0.34, 3), 10)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ring
                edge
                hole
            }
            .frame(width: side, height: side)

            // **Under the dial and not in the hole in it.** The hub is the
            // width of the hole minus the spokes around it, which is about
            // eighty points : `Heure de pointe` set in it ran under the ring
            // and came out with its last word behind a bar. What has to be in
            // the middle is the place itself, being the thing the shape cannot
            // say ; the word for it has the whole width of the card underneath.
            if busiest != nil {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
        .accessibilityValue(busiest.map { Text("\(counts[$0]) articles") } ?? Text("Nothing yet"))
    }

    /// The spokes, and the reader's own inside them.
    private var ring: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2

            ZStack {
                ForEach(Array(counts.enumerated()), id: \.offset) { place, count in
                    spoke(
                        place,
                        count: count,
                        peak: peak,
                        radius: radius,
                        from: Self.hub,
                        to: Self.reach,
                        colour: place == busiest
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(Color.primary.opacity(Figures.inkOpacity)),
                        width: width
                    )
                }

                if hasReading {
                    ForEach(Array(reading.enumerated()), id: \.offset) { place, count in
                        spoke(
                            place,
                            count: count,
                            peak: readPeak,
                            radius: radius,
                            from: 0.16,
                            to: Self.hub - 0.05,
                            colour: AnyShapeStyle(Color.accentColor.opacity(0.55)),
                            width: max(width * 0.6, 2.5)
                        )
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// One place, laid along its own radius and turned to where it belongs.
    ///
    /// Drawn from the middle outwards and then rotated, rather than placed at a
    /// computed point : a capsule that is rotated about the centre of the dial
    /// keeps its width square to the ring at every place, and one positioned by
    /// its coordinates does not.
    @ViewBuilder
    private func spoke(
        _ place: Int,
        count: Int,
        peak: Int,
        radius: CGFloat,
        from inner: CGFloat,
        to outer: CGFloat,
        colour: AnyShapeStyle,
        width: CGFloat
    ) -> some View {
        let available = radius * (outer - inner)
        let length = count > 0 ? max(available * CGFloat(count) / CGFloat(peak), Figures.floor) : 0
        let start = radius * inner
        // **A mark never gets wider than it is long.** Held at the full width,
        // one article against a busiest of twelve hundred was drawn as a
        // lozenge lying across the ring : a seventh of the height of the tallest
        // spoke for a fourteen-hundredth of its value, and thirty-one of them
        // round a month read as a dotted circle rather than as a quiet month.
        // Narrowing the smallest marks costs the dial nothing and gives a
        // single article the weight of a single article.
        let stroke = min(width, length)

        if length > 0 {
            Capsule()
                .fill(colour)
                .frame(width: stroke, height: length)
                // Half its own length out from the middle, plus the hub, which
                // puts its inner end on the hub and its outer end at the count.
                .offset(y: -(start + length / 2))
                .rotationEffect(.degrees(turn(of: place)))
                .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: count)
        }
    }

    /// What is written round the edge, where anything is.
    ///
    /// **Turned into place and then turned back.** A label carried round the
    /// dial by one rotation arrives lying on its side a quarter of the way
    /// round and upside down at the bottom, which is a dial nobody can read :
    /// the second rotation, equal and opposite, puts the glyph back on its feet
    /// while leaving it where the first one took it.
    private var edge: some View {
        ForEach(marks.keys.sorted(), id: \.self) { place in
            let turn = turn(of: place)

            Text(verbatim: marks[place] ?? "")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(-turn))
                .offset(y: -side * 0.5 + 4)
                .rotationEffect(.degrees(turn))
        }
    }

    /// Where a place sits round the dial, from the top and clockwise.
    private func turn(of place: Int) -> Double {
        Double(place) / Double(max(counts.count, 1)) * 360
    }

    /// What the dial is about, in the hole in the middle.
    ///
    /// The place, not the count : the spokes already say how much, and the one
    /// thing a shape cannot say is which of them the tall one is. What the
    /// place means is written under the dial, where there is room for it.
    @ViewBuilder
    private var hole: some View {
        if let busiest {
            middle(busiest)
                .font(theme.headline(.subheadline))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: side * Self.hub * 1.3)
        }
    }
}

// MARK: - Rankings

/// A ranked list, each row standing on a bar as long as its share.
///
/// **The bar is behind the row rather than beside it.** A name, a count and a
/// bar in three columns is three things to read per row ; a name and a count on
/// a bar is one. The bar carries the comparison, which is the only reason a
/// ranking is a picture at all, and it takes no width away from the name, which
/// is the one thing in the row that can be too long.
struct RankedBars: View {
    let entries: [Tally]
    /// What the numbers are counting, which only a reader listening to the page
    /// ever hears : the bars say how much, and the word says of what.
    var counted = Counted.articles
    /// Whether the largest is drawn in the accent.
    var highlightsLeader = true

    /// What one row of a ranking is a count of.
    ///
    /// The subjects are counted in stories and everything else in articles, for
    /// the reason ``StatisticsStore`` gives : a subject is filed onto a story,
    /// so counting the articles under it lets one runaway cluster carry a whole
    /// rubric.
    enum Counted {
        case articles
        case stories

        func spoken(_ count: Int) -> Text {
            switch self {
            case .articles: Text("\(count) articles")
            case .stories: Text("\(count) stories")
            }
        }
    }

    @Environment(\.theme) private var theme

    private var peak: Int { max(entries.map(\.count).max() ?? 0, 1) }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(entries) { entry in
                row(entry)
            }
        }
    }

    private func row(_ entry: Tally) -> some View {
        let share = Double(entry.count) / Double(peak)
        let isLeader = highlightsLeader && entry.count == peak

        return HStack(spacing: 10) {
            Text(verbatim: entry.name)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(entry.count.formatted())
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(isLeader ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(alignment: .leading) {
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        isLeader
                            ? AnyShapeStyle(Color.accentColor.opacity(0.16))
                            : AnyShapeStyle(Color.primary.opacity(0.07))
                    )
                    .frame(width: max(geometry.size.width * share, 10))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: entry.name))
        .accessibilityValue(counted.spoken(entry.count))
    }
}

/// One bar cut into the shares that make it up.
///
/// For the handful of questions whose whole answer is a proportion : which
/// languages the stream is written in, how much of it arrived twice. A ring
/// would say the same thing and would say it in a shape nobody can compare two
/// of ; a bar can be read against the one under it.
struct ShareBar: View {
    let shares: [Tally]
    var height: CGFloat = 12

    private var total: Int { max(shares.reduce(0) { $0 + $1.count }, 1) }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1.5) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                    Rectangle()
                        .fill(Self.tint(index))
                        .frame(width: max(geometry.size.width * Double(share.count) / Double(total) - 1.5, 2))
                }
            }
        }
        .frame(height: height)
        .clipShape(.capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Languages"))
    }

    /// How much of the accent one share is drawn in.
    ///
    /// A ramp of the one colour rather than a palette : the shares of a whole
    /// are the same kind of thing, and giving each its own hue would say they
    /// are not. Past the fifth it is the ink, since by then a share is a sliver
    /// and the only question about it is whether it is there.
    static func tint(_ index: Int) -> AnyShapeStyle {
        let steps: [Double] = [1, 0.72, 0.52, 0.38, 0.28]
        guard index < steps.count else { return AnyShapeStyle(Color.primary.opacity(0.18)) }
        return AnyShapeStyle(Color.accentColor.opacity(steps[index]))
    }
}
