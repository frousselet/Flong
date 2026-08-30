//
//  ArrivalsChart.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// How much arrived, day by day, over the head of the stream that holds it.
///
/// The same bars as the sparkline beside a story on the front page, given room
/// to be read. **No axis and no legend**, deliberately : thirty numbers down
/// the side and thirty dates along the bottom would take more room than the
/// chart and say less than its shape does, and the dateline of whatever the
/// reader is looking at is a line below anyway. What is left is the one thing
/// a count cannot say, which is whether a month was steady or had a Thursday
/// in it.
///
/// **It follows the reading rather than leading it.** The strip scrolls itself
/// to whichever thirty days the reader has scrolled the list into, so the bars
/// are always about what is on screen, and the day at the top of the list is
/// the coloured one. It can be pushed by hand too.
///
/// **The tallest bar is the busiest day of every window shown, not of the
/// window being shown.** Scaling each stretch on its own would draw a dead
/// fortnight in August exactly as tall as a general election, and a chart whose
/// scale moves under the reader is a chart that lies for free.
///
/// **The glass is the ground, not the bars.** They were tried as thirty pieces
/// of glass and it does not work at this size, all of it measured on the
/// simulator rather than reasoned about : glass shows what is behind it, and at
/// the head of a page that is white paper, so an untinted bar and a white bar
/// alike read as nothing at all, counted at not one pixel differing from pure
/// white. Tinting them solved that and brought its own trouble, `.regular`
/// glass carrying a shadow apiece that pooled into a grey wash across the strip
/// : forty thousand grey pixels, taking the paper down to two hundred and
/// thirty-six.
///
/// So the strip sits on one piece of glass instead, shaped like the pills the
/// front page pins its subjects on, and the bars are drawn on it as plain
/// shapes. One surface between the reader and the page rather than thirty, and
/// the bars can then be the page's own ink, which inverts with it.
///
/// The glass goes *behind* them rather than around them. It lends its vibrancy
/// to whatever it holds, which is right for the label on a pill and wrong here
/// : held, the ink came back a light grey. As a background it is a surface the
/// bars stand on rather than a material they are mixed into.
///
struct ArrivalsChart: View {
    /// How many articles arrived on each day, keyed by the local day.
    let counts: [Date: Int]
    /// The windows worth offering, newest first, each named by its last day.
    let windows: [Date]
    /// The day the reader has the list scrolled to.
    let current: Date?

    /// How tall the busiest day of the chart stands.
    private static let height: CGFloat = 26

    /// How much each day is drawn in from the edges of its column.
    private static let inset: CGFloat = 1.5

    /// The space between one day and the next.
    private static let gap: CGFloat = 2

    /// How far the first and last bars stand from the ends of the glass.
    ///
    /// Enough that neither is cut by the curve of the capsule, which turns
    /// through half the height of the strip at either end.
    private static let margin: CGFloat = 20

    @State private var shown = ScrollPosition(idType: Date.self)
    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let peak = peak
        let window = current.flatMap { day in
            windows.first.map { DayWindow.containing(day, newest: $0, calendar: calendar) }
        }

        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(windows, id: \.self) { window in
                    HStack(alignment: .bottom, spacing: Self.gap) {
                        ForEach(DayWindow.days(endingAt: window, calendar: calendar), id: \.self) { day in
                            bar(day, peak: peak)
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        // A stretch at a time : half of one month and half of the next is a
        // comparison nobody asked for.
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition($shown, anchor: .center)
        .scrollIndicators(.hidden)
        // No edge effect of its own. A strip of thirty bars is not a page
        // being read into, and the softening a scroll view puts at its edges
        // belongs to the list underneath rather than to this.
        .scrollEdgeEffectHidden()
        // A scroll view takes everything it is offered on both axes, and
        // offered a whole screen it takes a whole screen. There are no labels
        // under the bars, so the height of the strip is the height of a bar and
        // can simply be said.
        .frame(height: Self.height)
        .padding(.horizontal, Self.margin)
        .padding(.vertical, 7)
        // One piece of glass, in the shape the front page gives its subjects.
        // Not `interactive` : a pill is a control and this is a picture.
        //
        // Behind the bars rather than around them. Glass lends its vibrancy to
        // whatever it holds, which is right for the label on a pill and wrong
        // here : it took the page's ink and returned it at a light grey. As a
        // background it is a surface the bars are drawn on rather than a
        // material they are drawn into.
        .background {
            Color.clear.glassEffect(.regular, in: .capsule)
        }
        .onChange(of: window, initial: true) { _, window in
            guard let window else { return }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                shown.scrollTo(id: window, anchor: .center)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Articles per day"))
    }

    /// One day.
    private func bar(_ day: Date, peak: Int) -> some View {
        let count = counts[day] ?? 0
        let isCurrent = current.map { calendar.isDate($0, inSameDayAs: day) } ?? false

        return VStack {
            // A day nothing came in on draws nothing at all. With no axis to
            // stand on there is no line for it to hide in, and a gap in the row
            // is the honest picture of a gap in the month.
            if count > 0 {
                Capsule()
                    // The page's own ink, which inverts with the page and so
                    // with the glass under it : dark bars on the light
                    // material, light ones on the dark.
                    .fill(isCurrent ? Color.accentColor : Color.primary)
                    .frame(height: height(of: count, peak: peak))
                    // The day being read is the coloured one, and every bar is
                    // the same width : the mark is colour and nothing else, so
                    // that no bar moves and none of them changes shape as the
                    // reader scrolls from one day into the next.
                    .padding(.horizontal, Self.inset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .frame(height: Self.height, alignment: .bottom)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: isCurrent)
        // A bar holds no text of its own, so it is not an element anybody can
        // reach until it is told to be one. A reader listening to the page gets
        // the same thirty days as a reader looking at them.
        .accessibilityElement()
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(Text("\(count) articles"))
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        .help(Text("\(count) articles"))
    }

    /// A bar never falls below four points : a day that had one article is a
    /// day something happened on, and a bar too short to see says it did not.
    private func height(of count: Int, peak: Int) -> CGFloat {
        max(Self.height * CGFloat(count) / CGFloat(peak), 4)
    }

    /// The busiest day of every window on offer.
    private var peak: Int {
        let busiest =
            windows
            .flatMap { DayWindow.days(endingAt: $0, calendar: calendar) }
            .compactMap { counts[$0] }
            .max()
        return max(busiest ?? 1, 1)
    }
}
