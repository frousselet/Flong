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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 7, height: 7)
            .scaleEffect(isPulsing ? 1.35 : 1)
            .opacity(isPulsing ? 0.55 : 1)
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
