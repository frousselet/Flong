//
//  WorkRingSymbolTests.swift
//  FlongTests
//
//  Created by François Rousselet on 05/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// The glyph both rings are drawn with.
@Suite("The symbol the rings are drawn with")
struct WorkRingSymbolTests {

    /// **The one thing a build cannot catch.** `Image(systemName:)` takes any
    /// string at all and draws nothing where the system has no such symbol, so
    /// a wrong name here is a corner of the bar with a hole in it while every
    /// pass runs, and the compiler is perfectly happy about it.
    @Test("Both rings are symbols the system has")
    func theSymbolsExist() {
        for symbol in WorkRing.symbols {
            #expect(exists(symbol), "\(symbol) is not a symbol the system knows")
        }
    }

    /// **The counted ring is a variable-value symbol, and nothing else would
    /// do.** A glyph that ignores the value renders identically at a tenth and
    /// at nine tenths, which is a dial that never moves : the pass would run
    /// from end to end under a ring that says the same thing throughout, and
    /// the page would look right in every screenshot anyone ever took of it.
    @Test("Both answer to a variable value")
    func theSymbolsAreVariable() {
        for symbol in WorkRing.symbols {
            let low = rendering(symbol, value: WorkRing.least)
            let middle = rendering(symbol, value: 0.5)
            let full = rendering(symbol, value: 1)

            #expect(low != nil, "\(symbol) draws nothing")
            #expect(low != middle, "\(symbol) draws the same at a twentieth as at a half")
            #expect(middle != full, "\(symbol) draws the same at a half as when it is finished")
        }
    }

    /// **The measured ring is a sweep and not a set of steps.** A dial that
    /// rounds to the nearest twelfth is a dial that stands still for most of a
    /// pass and then jumps, and the whole point of measuring is that the reader
    /// can see it move. Sixteen distinct drawings across sixteen values is what
    /// a continuous glyph gives ; a segmented one would repeat itself.
    @Test("The measured ring is drawn continuously")
    func theDialIsContinuous() {
        let drawings = Set((0..<16).compactMap { rendering(WorkRing.dial, value: Double($0) / 16) })
        #expect(drawings.count == 16, "the dial has only \(drawings.count) drawings across sixteen values")
    }

    /// The chase needs layers to light in turn : a glyph drawn as one unbroken
    /// stroke has one, and `variableColor` has nothing to run through.
    @Test("The turning ring is drawn in segments")
    func theChaseIsSegmented() {
        let drawings = Set((0...24).compactMap { rendering(WorkRing.chase, value: Double($0) / 24) })
        #expect(drawings.count > 4, "the chase has only \(drawings.count) drawings, so it has too few segments")
        #expect(drawings.count < 24, "the chase is continuous, so there are no segments to light in turn")
    }

    /// The still state is a ring caught partway rather than a ring that has
    /// finished : Reduce Motion must not turn the spinner into a tick.
    @Test("The resting arc is neither empty nor complete")
    func theRestingArcIsPartial() {
        #expect(WorkRing.resting > WorkRing.least)
        #expect(WorkRing.resting < 1)
        #expect(rendering(WorkRing.chase, value: WorkRing.resting) != rendering(WorkRing.chase, value: 1))
    }

    private func exists(_ symbol: String) -> Bool {
        #if os(iOS)
            UIImage(systemName: symbol) != nil
        #else
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
        #endif
    }

    /// One drawing of the symbol, at a stated value, as bytes that can be
    /// compared. The size is fixed so that two renderings differ only where the
    /// glyph itself does.
    private func rendering(_ symbol: String, value: Double) -> Data? {
        #if os(iOS)
            let configuration = UIImage.SymbolConfiguration(pointSize: 64)
            return UIImage(systemName: symbol, variableValue: value, configuration: configuration)?
                .pngData()
        #else
            guard
                let image = NSImage(systemSymbolName: symbol, variableValue: value, accessibilityDescription: nil),
                let sized = image.withSymbolConfiguration(.init(pointSize: 64, weight: .regular)),
                let tiff = sized.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiff)
            else { return nil }
            return bitmap.representation(using: .png, properties: [:])
        #endif
    }
}
