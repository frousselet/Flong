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
/// **One month at a time, and exactly the days it has.** A rolling stretch of
/// thirty is a stretch nobody keeps and cannot be compared with the one beside
/// it ; a month can. February draws twenty-eight bars and August thirty-one,
/// each a little wider or narrower for it, which is a fact about February
/// rather than a gap in the drawing.
///
/// **The rest of the month is drawn and greyed.** A day that has not happened
/// yet is not a quiet day, and a chart that stops at today would have the
/// current month change width as it goes. The days ahead keep their places and
/// say they are ahead.
///
/// **It follows the reading rather than leading it.** The strip scrolls itself
/// to whichever month the reader has scrolled the list into, so the bars are
/// always about what is on screen, and the day at the top of the list is the
/// coloured one. It can be pushed by hand too.
///
/// **The tallest bar is the busiest day of every month shown, not of the month
/// being shown.** Scaling each month on its own would draw a dead fortnight in
/// August exactly as tall as a general election, and a chart whose scale moves
/// under the reader is a chart that lies for free.
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

    /// How many articles arrived in each hour, keyed by the local hour.
    let counts: [Date: Int]
    /// The days worth offering, newest first, each named by its first moment.
    let days: [Date]
    /// The day the reader has the list scrolled to.
    let current: Date?

    /// Whether anything has scrolled under the chart yet.
    ///
    /// At rest the chart sits on the page, and glass over nothing is glass
    /// doing nothing : a material's whole job is to say that something passes
    /// behind it. The bars are legible on the page's own ground, so at the top
    /// the strip is simply bars, the full width of the column the page is set
    /// in, and it narrows into its glass as the first row goes under it.
    var isCovered = false

    /// How tall the busiest hour of the chart stands.
    private static let height: CGFloat = 26

    /// How much each hour is drawn in from the edges of its column.
    private static let inset: CGFloat = 1.5

    /// The space between one hour and the next.
    private static let gap: CGFloat = 2

    /// How far the first and last bars stand from the ends of the glass.
    ///
    /// Only once there is glass. Uncovered the chart runs the full width of
    /// the column the page is set in, and a bar standing in from an edge that
    /// is not there would be standing in from nothing.
    ///
    /// Enough that neither is cut by the curve of the capsule, which turns
    /// through half the height of the strip at either end.
    private static let margin: CGFloat = 20

    @State private var shown = ScrollPosition(idType: Date.self)
    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let peak = peak
        let day = current.map { Hours.containing($0, calendar: calendar) }
        let thisHour = Hours.hour(of: .now, calendar: calendar)

        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    HStack(alignment: .bottom, spacing: Self.gap) {
                        ForEach(Hours.of(day, calendar: calendar), id: \.self) { hour in
                            bar(hour, peak: peak, now: thisHour)
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        // A day at a time : half of one and half of the next is a comparison
        // nobody asked for.
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition($shown, anchor: .center)
        .scrollIndicators(.hidden)
        // Not a thing to drag. The month it shows is the month the reader is
        // in, and it follows their scroll down the list : a second scroll, of
        // its own, on the same screen and at right angles to the first, is two
        // ways of moving through one page and a way of putting the two out of
        // step with each other. It moves by being followed, never by being
        // pushed.
        .scrollDisabled(true)
        // No edge effect of its own. A strip of thirty bars is not a page
        // being read into, and the softening a scroll view puts at its edges
        // belongs to the list underneath rather than to this.
        .scrollEdgeEffectHidden()
        // A scroll view takes everything it is offered on both axes, and
        // offered a whole screen it takes a whole screen. There are no labels
        // under the bars, so the height of the strip is the height of a bar and
        // can simply be said.
        .frame(height: Self.height)
        .padding(.horizontal, isCovered ? Self.margin : 0)
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
            // The shape is always there and the material is not, so the strip
            // does not change size when the glass arrives : a chart that
            // resized on the first scroll would move the very rows that were
            // passing under it.
            Color.clear
                .glassEffect(isCovered ? .regular : .identity, in: .capsule)
        }
        // The month narrows into its glass rather than appearing already
        // narrowed : the width and the material are one movement, and the
        // reader's own scroll is what drives it.
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: isCovered)
        .onChange(of: day, initial: true) { _, day in
            guard let day else { return }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                shown.scrollTo(id: day, anchor: .center)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Articles per hour"))
    }

    /// One hour.
    private func bar(_ hour: Date, peak: Int, now: Date) -> some View {
        let count = counts[hour] ?? 0
        // The hour being read, which is the hour of the article at the top of
        // the list rather than the hour it happens to be.
        let isCurrent = current.map { Hours.hour(of: $0, calendar: calendar) == hour } ?? false
        let isAhead = hour > now

        return VStack {
            if !isAhead, count > 0 {
                Capsule()
                    // The page's own ink, which inverts with the page and so
                    // with the glass under it : dark bars on the light
                    // material, light ones on the dark. Held back from the
                    // full ink : a row of thirty bars at the weight of a
                    // headline is a row that reads as loudly as the headlines
                    // under it, and this is a picture of the page rather than
                    // part of it.
                    .fill(isCurrent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Self.ink))
                    .frame(height: height(of: count, peak: peak))
                    .opacity(Self.barOpacity)
            } else {
                // An hour nothing came in on keeps its place, in grey, at the
                // height of the shortest bar there is. Whether it has been and
                // gone or has not happened yet, it is an hour with nothing in
                // it and it is drawn the same way : the row stays a row, with a
                // level floor a reader's eye can run along, and the ink is
                // reserved for the hours something did arrive in.
                Capsule()
                    .fill(.quaternary)
                    .frame(height: Self.floor)
            }
        }
        // Outside the branches, so that every bar is the same width whichever
        // one drew it. Held inside one of them, the grey of a day still to come
        // came out three points wider than the ink beside it.
        //
        // The day being read is the coloured one, and nothing else about it
        // changes : no bar moves and none of them changes shape as the reader
        // scrolls from one hour into the next.
        .padding(.horizontal, Self.inset)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .frame(height: Self.height, alignment: .bottom)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: isCurrent)
        // A bar holds no text of its own, so it is not an element anybody can
        // reach until it is told to be one. A reader listening to the page gets
        // the same day as a reader looking at it.
        .accessibilityElement()
        .accessibilityLabel(Text(hour, format: .dateTime.weekday(.wide).day().month(.wide).hour()))
        .accessibilityValue(isAhead ? Text("Still to come") : Text("\(count) articles"))
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        .help(isAhead ? Text("Still to come") : Text("\(count) articles"))
    }

    /// How dark an hour that had something is drawn.
    ///
    /// The page's own ink, at full strength.
    ///
    /// A bar wants the weight of the ink or it stops being something to count
    /// by. Held back to half, it measured a mid grey too faint to read a day
    /// by ; held back a tenth, a shade off black and still not quite the thing.
    /// So it is the ink, and the softening is the transparency below rather
    /// than a paler colour.
    static let ink = Color.primary

    /// How much of what is behind a bar comes through it.
    ///
    /// Barely any, and that is the point. It keeps a bar from being the hardest
    /// edge on the page, and it lets the glass under the strip, and whatever
    /// headline is passing beneath that, show through by a hair.
    static let barOpacity: Double = 0.95

    /// The shortest a bar is ever drawn.
    ///
    /// An hour that had one article is an hour something happened in, and a bar
    /// too short to see says it did not. It is also the height of every hour
    /// with nothing in it, so those read as a level grey run along the foot of
    /// the day rather than as gaps in it.
    private static let floor: CGFloat = 4

    private func height(of count: Int, peak: Int) -> CGFloat {
        max(Self.height * CGFloat(count) / CGFloat(peak), Self.floor)
    }

    /// The busiest hour of every day on offer.
    private var peak: Int {
        let busiest =
            days
            .flatMap { Hours.of($0, calendar: calendar) }
            .compactMap { counts[$0] }
            .max()
        return max(busiest ?? 1, 1)
    }
}
