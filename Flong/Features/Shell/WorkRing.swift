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
/// counted the ring goes round instead, and the words that used to sit over the
/// rule are what it says to VoiceOver and to a pointer resting on it.
///
/// **And the ring says what is being brought in, not only how much of it.** The
/// stage's own mark stands inside the circle the measure is drawn on : the
/// arrow while the feeds come down, the paper while what arrived is grouped,
/// the cloud while iCloud is caught up with. It is one symbol rather than a
/// glyph beside a ring, since every mark is of the `.circle` family and that
/// family's enclosure is what answers to the variable value. The mark changes
/// under Magic Replace, which is what that transition is for : the circle is
/// common to both symbols, so it stays put and the thing inside it is the only
/// part that moves, and a measure that jumped a frame at every stage would be a
/// measure the reader stops believing.
struct WorkRing: View {
    let work: WorkPlan

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The ring follows the type size, since it stands beside a control that
    /// does.
    ///
    /// One measurement and not two. It was a side and an ink, two
    /// `@ScaledMetric` values that grew independently of one another, so the
    /// weight of the ring against its own diameter was a different ratio at
    /// every type size. A symbol carries its own weight and takes one number.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 18

    var body: some View {
        ring
            .font(.system(size: side))
            // The tint rather than the foreground, and stated rather than
            // inherited : the ring is the label of a button that is disabled on
            // purpose, and a disabled label is drawn in the secondary colour.
            // What this says is not unavailable, it is happening.
            .foregroundStyle(.tint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(work.phase.title))
            .accessibilityValue(value)
            // So VoiceOver does not read every batch out as it lands.
            .accessibilityAddTraits(.updatesFrequently)
    }

    /// The ring itself : how far along where there is a count, and going round
    /// where there is none.
    @ViewBuilder
    private var ring: some View {
        if let fraction = work.fraction {
            // The dial the application always drew, drawn by the system : a
            // hairline track with the ink running round it from the top, and
            // the stage's own mark standing in the middle of it.
            Image(systemName: work.phase.mark, variableValue: max(fraction, Self.least))
                // **Magic Replace, and the fallback it asks for.** Every mark
                // shares the circle the measure is drawn on, which is exactly
                // the case that transition exists for : the enclosure holds and
                // the thing inside it is replaced. Where two marks share
                // nothing the system falls back to one going down and the next
                // coming up, which is the plainest replacement there is.
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp)))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: fraction)
                .animation(reduceMotion ? nil : .default, value: work.phase)
        } else if reduceMotion {
            // Still, the way ``LiveDot`` stops its pulse : a ring going round
            // for ever is motion for its own sake, and a part-inked ring says
            // as much standing still as it does turning.
            Image(systemName: Self.chase, variableValue: Self.resting)
        } else {
            // **The segments light in turn rather than a shape being spun.**
            // `iterative` runs the ink round the ring one segment at a time and
            // leaves the rest as the track, which is the reading the trimmed
            // arc over a hairline circle used to give. `cumulative` was the
            // other way and says the wrong thing : a ring that fills is a ring
            // that is measuring something, and this is the branch where there
            // is nothing to measure.
            Image(systemName: Self.chase)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        }
    }

    private var value: Text {
        guard let fraction = work.fraction else { return Text("In progress") }
        return Text(fraction.formatted(.percent.precision(.fractionLength(0))))
    }
}

extension WorkRing {
    /// The rings where the pass can be counted, one per stage.
    ///
    /// **The system's own glyph, rather than two circles in a stack.** It was a
    /// `Circle` for the track with a trimmed, round-capped `Circle` over it for
    /// the ink : two shapes laid out independently inside one frame, each
    /// stroked so that half the line falls outside the bounds it is measured
    /// in, and the upper one spun by a `rotationEffect` anchored on those same
    /// bounds. Every one of those is a chance for the ink to sit off the centre
    /// of its own track, and between them they took it.
    ///
    /// A symbol cannot : it is one glyph, there is no second shape to disagree
    /// with, and nothing to centre against anything. Given a variable value the
    /// system draws these as exactly what was being drawn by hand, a pale track
    /// with the ink running round it from the top, and it draws it
    /// **continuously** rather than in steps, which is what a measure owes the
    /// thing it measures. What the plain circle did for every stage alike,
    /// ``WorkPhase/mark`` now does for each of them in turn, the circle being
    /// the part of the mark the value reaches.
    static let dials = WorkPhase.allCases.map(\.mark)

    /// The ring where it cannot.
    ///
    /// A ring of twelve segments, because a chase needs something to chase
    /// through : an effect lights the layers of a symbol in turn, and a glyph
    /// drawn as one unbroken stroke has one layer and cannot move. Twelve
    /// segments going round say what the turning arc said.
    ///
    /// **Two glyphs and not one**, which is a difference worth stating. The
    /// spoked indicator the system offers does both in one, and the whole of
    /// ``WaitingRing`` is an argument against spokes : a dozen of them
    /// flickering is the mark of a document being fetched from somewhere. A
    /// dashed ring measured in twelfths would be the other compromise, and it
    /// would round a measure to the nearest twelfth for the sake of using one
    /// name in two places. The two states of this ring already looked
    /// different, since one is a quantity and the other is not.
    static let chase = "ring.dashed"

    /// Every one of them is checked against the system by
    /// `WorkRingSymbolTests`, for the reason every other symbol in the
    /// application is : `Image(systemName:)` takes any string at all and draws
    /// nothing where the system has no such glyph, and the compiler is
    /// perfectly happy about it.
    static let symbols = dials + [chase]

    /// The least a measured ring ever shows.
    ///
    /// A pass at nought is a pass that has begun, and a ring with nothing in it
    /// says the opposite : a segment's worth of ink is the difference between
    /// starting and absent. The symbol lights its first segment a little above
    /// nought, so this is what reaches it.
    static let least = 0.05

    /// How much of the ring is inked where it is not allowed to move.
    ///
    /// Under a third, which is what the arc that turned used to show. Enough to
    /// read as a ring caught partway rather than as a ring with a nick out of
    /// it, and short enough that nobody mistakes it for a measure nearly done.
    static let resting = 0.3
}
