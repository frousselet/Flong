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

/// A ring going round, for a wait nobody can count.
///
/// **The system's own spinner says the wrong thing here.** A dozen spokes
/// flickering in the middle of an empty page is the mark of a document being
/// fetched from somewhere, and an article the reader has already opened is not
/// being fetched from anywhere : it is being set. So the wait is drawn in the
/// same hand as ``WorkRing``, the one shape the application already uses for
/// work in progress, and out of the same glyph : see ``WorkRing/chase`` for why
/// it is a symbol rather than a pair of circles in a stack.
///
/// Still under Reduce Motion, exactly as ``WorkRing`` and ``LiveDot`` are : a
/// ring going round for ever is motion for its own sake, and a part-inked ring
/// says as much standing still as it does turning.
struct WaitingRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The ring follows the reader's type size, since what it stands in for is
    /// a page of type.
    @ScaledMetric private var side: CGFloat

    init(side: CGFloat = 30) {
        _side = ScaledMetric(wrappedValue: side, relativeTo: .body)
    }

    var body: some View {
        ring
            .font(.system(size: side))
            // Quieter than ``WorkRing``, which is tinted : that one is the
            // machinery reporting itself in the chrome, and this one stands in
            // the middle of a page where the words are about to be.
            .foregroundStyle(.secondary)
            .accessibilityElement()
            .accessibilityLabel(Text("Loading"))
            .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var ring: some View {
        if reduceMotion {
            Image(systemName: WorkRing.chase, variableValue: WorkRing.resting)
        } else {
            Image(systemName: WorkRing.chase)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        }
    }
}
