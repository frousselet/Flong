//
//  Shimmer.swift
//  Flong
//
//  Created by François Rousselet on 04/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// A band of light travelling across a skeleton.
///
/// **What tells a page that is filling in from a page that is broken.** Bars
/// standing still are indistinguishable from a layout that failed to draw ; the
/// same bars with something moving over them say the application is at work and
/// that these will become words. It is the one animation on the front page and
/// it exists for that sentence alone.
///
/// **Light and slow.** A sweep that is bright or quick is a page flashing at
/// somebody who is trying to read it, and what is underneath is a placeholder
/// nobody is meant to look at. A second and a half end to end, and a band that
/// barely lifts the grey it crosses.
///
/// **A band that moves, and not a gradient whose ends do.** Animating the
/// `startPoint` and `endPoint` of a `LinearGradient` needs no geometry and is
/// the tidier thing to write ; it also does not animate. A gradient is a
/// `ShapeStyle` and SwiftUI resolves it rather than interpolating between two
/// of them, so the band snapped from one end to the other and two screenshots
/// three seconds apart were the same picture. What moves is a layer, by an
/// offset, which is a value SwiftUI has always animated.
///
/// **And it stops for a reader who asked for less motion.** Something moving
/// for ever at the top of the page is precisely what that setting is about.
/// What is left is the bars, which is what they were before this.
private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTravelling = false

    /// How long the band takes to cross, end to end.
    private static let travel: TimeInterval = 1.6

    /// How wide the band is, as a share of what it crosses. Narrow enough to
    /// read as a sweep rather than as the whole thing brightening.
    private static let band: CGFloat = 0.55

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .overlay {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        let band = max(width * Self.band, 1)

                        LinearGradient(
                            colors: [.clear, .white.opacity(0.4), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: band)
                        .offset(x: isTravelling ? width : -band)
                    }
                    // Masked by what it is lighting, so the band crosses the
                    // bars and never the paper between them.
                    .mask(content)
                    .allowsHitTesting(false)
                }
                .onAppear {
                    withAnimation(.linear(duration: Self.travel).repeatForever(autoreverses: false)) {
                        isTravelling = true
                    }
                }
        }
    }
}

extension View {
    /// Sends a band of light across this view, for as long as it is on screen.
    ///
    /// For skeletons and nothing else : what it says is `these will become
    /// words`, and saying that over anything a reader can act on would be a lie.
    func shimmering() -> some View {
        modifier(Shimmer())
    }
}
