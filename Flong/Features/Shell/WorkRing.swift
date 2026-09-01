//
//  WorkRing.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What the machinery is doing, as one ring in the reader's own corner.
///
/// **It was a band across the head of the front page.** A line of words over a
/// rule that filled, in the pinned header with the subjects. Everything it said
/// was true and it said it in the reader's way : it opened a slot in the page
/// every time a pass began, closed it again a few seconds later, and did so on
/// the one page the reader is reading. A measure that moves the text under the
/// thumb costs more than it tells.
///
/// So the measure moved to where the chrome already is. It is a ring, because a
/// ring is round like the button beside it and takes a corner rather than a
/// line ; it is small, because what is happening is the machinery's business
/// and not the reader's ; and it is in the bar, which is the one part of the
/// page that does not move when it appears.
///
/// It carries the whole pass, exactly as the rule did : ``WorkPlan`` weighs the
/// stages against each other so the ring is inked once across the lot rather
/// than filling and emptying at every stage. Where nothing in the pass can be
/// counted the ring turns instead, and the words that used to sit over the rule
/// are what it says to VoiceOver and to a pointer resting on it.
struct WorkRing: View {
    let work: WorkPlan

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much of an unmeasured ring is inked.
    ///
    /// Under a third. Enough to read as an arc turning rather than as a ring
    /// with a nick out of it, and short enough that nobody mistakes it for a
    /// measure four fifths of the way along.
    private static let arc = 0.3

    /// The least a measured ring ever shows.
    ///
    /// A pass at nought is a pass that has begun, and a ring with nothing in it
    /// says the opposite : a cap's worth of ink is the difference between
    /// starting and absent.
    private static let least = 0.05

    /// The ring follows the type size, since it stands beside a control that
    /// does.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var ink: CGFloat = 2.5

    @State private var isTurning = false

    var body: some View {
        ZStack {
            // The track, so a ring at a tenth is a ring and not a stray mark.
            Circle()
                .stroke(.tint.opacity(0.22), lineWidth: ink)
            measure
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(work.phase.title))
        .accessibilityValue(value)
        // So VoiceOver does not read every batch out as it lands.
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// The inked part : how far along where there is a count, and an arc going
    /// round where there is none.
    @ViewBuilder
    private var measure: some View {
        if let fraction = work.fraction {
            Circle()
                .trim(from: 0, to: max(fraction, Self.least))
                // From the top, which is where a reader starts reading a dial.
                .rotation(.degrees(-90))
                .stroke(.tint, style: StrokeStyle(lineWidth: ink, lineCap: .round))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: fraction)
        } else {
            Circle()
                .trim(from: 0, to: Self.arc)
                .rotation(.degrees(-90))
                .stroke(.tint, style: StrokeStyle(lineWidth: ink, lineCap: .round))
                .rotationEffect(.degrees(isTurning ? 360 : 0))
                .animation(
                    reduceMotion ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false),
                    value: isTurning
                )
                // Still under Reduce Motion, the way ``LiveDot`` stops its
                // pulse : a ring turning for ever is motion for its own sake,
                // and the arc says as much standing still as it does going
                // round.
                .onAppear { isTurning = !reduceMotion }
        }
    }

    private var value: Text {
        guard let fraction = work.fraction else { return Text("In progress") }
        return Text(fraction.formatted(.percent.precision(.fractionLength(0))))
    }
}
