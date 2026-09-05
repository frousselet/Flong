//
//  RingLookTests.swift
//  FlongTests
//
//  Created by François Rousselet on 05/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import Testing

@testable import Flong

/// What the ring draws, as the page draws it.
///
/// **The symbol tests were not enough, and the way they were not is the whole
/// reason this file exists.** They ask UIKit for an image of a symbol at a
/// value and compare the bytes, and by that measure the ring was perfect :
/// sixteen different drawings across sixteen values. The page meanwhile drew a
/// full circle at a twentieth and a full circle at nine tenths.
///
/// A variable value means two things to a symbol, and which of them is meant is
/// settled by a modifier the image API never sees : `color` lights layers in
/// turn, `draw` draws the glyph part of the way round. UIKit chose `draw` for
/// these symbols on its own ; SwiftUI chose `color`, and an enclosure of the
/// `.circle` family has no layers to light, so the value reached nothing at
/// all. Rendering the view is the only place that difference shows.
@Suite("What the ring draws")
@MainActor
struct RingLookTests {

    /// The measure has to move, which is the whole of what a measure is for.
    @Test("The ring is drawn differently at every point of a pass")
    func theRingMoves() throws {
        let drawings = try [0.05, 0.35, 0.7, 1].map { try #require(Self.drawing(at: $0)) }

        for (index, drawing) in drawings.enumerated() {
            for other in drawings[(index + 1)...] {
                #expect(drawing != other, "the ring draws the same thing at two different points of a pass")
            }
        }
    }

    /// A pass that has begun is not a pass that is over, and the ring must not
    /// say it is : see ``WorkRing/least``.
    @Test("A pass that has just begun is not drawn as a pass that is over")
    func theStartIsNotTheEnd() throws {
        let begun = try #require(Self.drawing(at: 0))
        let over = try #require(Self.drawing(at: 1))
        #expect(begun != over)
    }

    /// One drawing of the ring, at a stated fraction of a pass, as bytes that
    /// can be compared.
    private static func drawing(at fraction: Double) -> Data? {
        var plan = WorkPlan([.fetching])
        plan.advance(done: Int(fraction * 100), total: 100)

        let renderer = ImageRenderer(
            content: WorkRing(work: plan)
                .frame(width: 120, height: 120)
                .background(Color.white)
        )
        renderer.scale = 3

        #if os(iOS)
            return renderer.uiImage?.pngData()
        #else
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiff)
            else { return nil }
            return bitmap.representation(using: .png, properties: [:])
        #endif
    }
}
