//
//  WaitingRing.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// A ring turning, for a wait nobody can count.
///
/// **The system's own spinner says the wrong thing here.** A dozen spokes
/// flickering in the middle of an empty page is the mark of a document being
/// fetched from somewhere, and an article the reader has already opened is not
/// being fetched from anywhere : it is being set. So the wait is drawn in the
/// same hand as ``WorkRing``, the one shape the application already uses for
/// work in progress : a hairline track with a short arc going round it.
///
/// Still under Reduce Motion, exactly as ``WorkRing`` and ``LiveDot`` are : a
/// ring turning for ever is motion for its own sake, and the arc says as much
/// standing still as it does going round. The track is what makes the still
/// state read as a ring rather than as a stray mark.
struct WaitingRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The ring follows the reader's type size, since what it stands in for is
    /// a page of type.
    @ScaledMetric private var side: CGFloat
    @State private var isTurning = false

    /// How much of the ring is inked. The same arc ``WorkRing`` turns : enough
    /// to read as an arc going round rather than as a ring with a nick out of
    /// it, and short enough that nobody takes it for a measure nearly done.
    private static let arc = 0.28

    init(side: CGFloat = 30) {
        _side = ScaledMetric(wrappedValue: side, relativeTo: .body)
    }

    var body: some View {
        let ink = side / 11

        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: ink)
            Circle()
                .trim(from: 0, to: Self.arc)
                // From the top, which is where a reader starts reading a dial.
                .rotation(.degrees(-90))
                .stroke(.secondary, style: StrokeStyle(lineWidth: ink, lineCap: .round))
                .rotationEffect(.degrees(isTurning ? 360 : 0))
                .animation(
                    reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false),
                    value: isTurning
                )
                .onAppear { isTurning = !reduceMotion }
        }
        .frame(width: side, height: side)
        .accessibilityElement()
        .accessibilityLabel(Text("Loading"))
        .accessibilityAddTraits(.updatesFrequently)
    }
}
