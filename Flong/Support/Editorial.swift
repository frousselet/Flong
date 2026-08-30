//
//  Editorial.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The few decisions that make the interface look like one thing.
///
/// Everything here is a token rather than a value typed at a call site : one
/// place to change a measure, a rhythm or a face, which is how a design stays
/// consistent while it is still being argued about.
nonisolated enum Editorial {
    /// The width a column of text may reach.
    ///
    /// Around seventy characters at the body size. Wider is measurably harder to
    /// read, and a window three times this wide should hold one column of text
    /// and a great deal of quiet, not three columns of text.
    static let measure: CGFloat = 680

    /// The vertical rhythm between stories.
    /// The shape every picture is shown in, lead and thumbnail alike.
    ///
    /// Three by two, which is what a camera takes and therefore what a
    /// publisher's picture already is : any other ratio is a crop, and a crop
    /// is a decision about somebody else's photograph.
    ///
    /// One ratio for the whole page rather than a band above and squares
    /// beside : a column whose pictures are all the same shape has a rhythm,
    /// and one whose pictures each have their own does not.
    static let pictureAspect: CGFloat = 3.0 / 2.0

    static let rhythm: CGFloat = 28
    static let tightRhythm: CGFloat = 10

    /// Headlines are serif, everything else is not.
    ///
    /// It is the cheapest way to say that this is a place where things are read
    /// rather than a place where things are managed, and it separates what an
    /// article says from what the application says about it.
    static func headline(_ style: Font.TextStyle) -> Font {
        .system(style, design: .serif, weight: .semibold)
    }

    /// The line under a headline : what happened, in one sentence.
    static var standfirst: Font { .system(.subheadline, design: .serif) }

    /// Everything the application says about an article rather than in it :
    /// rooms, counts, times.
    static var metadata: Font { .system(.caption, design: .default) }
}

nonisolated extension View {
    /// Holds a view to the measure, centred, whatever the window does.
    func editorialColumn() -> some View {
        frame(maxWidth: Editorial.measure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// A dot that says something is still arriving.
///
/// The motion is the information : a story nobody is adding to has a still dot,
/// and one that is moving has a moving dot. It stops entirely when the reader
/// has asked for less motion.
struct LiveDot: View {
    /// The colour of the dot, and of anything that names it.
    ///
    /// Named rather than written twice : a heading beside the dot has to be the
    /// dot's own colour, and two literals that happen to agree today are two
    /// literals that stop agreeing the first time one of them is changed.
    static let tint = Color.red

    /// How faint the dot goes at the bottom of its pulse.
    ///
    /// A heading beside it takes this rather than the full colour : the dot is
    /// the loud thing and the word is what it means, so the word sits at the
    /// quiet end of the same breath and the pair reads as one mark rather than
    /// as two red things competing.
    static let faded = 0.55

    /// The colour a heading beside the dot is set in.
    static var quietTint: Color { tint.opacity(faded) }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Self.tint)
            .frame(width: 7, height: 7)
            .scaleEffect(isPulsing ? 1.35 : 1)
            .opacity(isPulsing ? Self.faded : 1)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = !reduceMotion }
            .accessibilityHidden(true)
    }
}

/// The shape of a story's arrival.
///
/// It tells a burst from a trickle at a glance, which is the one thing a number
/// cannot say.
struct Sparkline: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geometry in
            let peak = max(values.max() ?? 1, 1)
            let width = geometry.size.width / CGFloat(max(values.count, 1))

            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Capsule()
                        .frame(
                            width: max(width - 1.5, 1),
                            height: max(geometry.size.height * CGFloat(value) / CGFloat(peak), 1.5)
                        )
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
}
