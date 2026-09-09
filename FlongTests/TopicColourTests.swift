//
//  TopicColourTests.swift
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

/// The colour a subject is printed in.
@Suite("The colours the subjects are printed in")
struct TopicColourTests {

    /// **One set of hues for three themes, so they are checked against all
    /// three papers.** A colour picked against white and never tried on warm
    /// paper or on base3 is a colour that reads on one page in three, and the
    /// rubric it prints is a caption : four and a half to one is the floor for
    /// type at that size, not a target.
    @Test("Every colour reads on every paper, in both appearances")
    func everyColourHolds() {
        for family in TopicFamily.allCases {
            for theme in Theme.allCases {
                for scheme in [ColorScheme.light, .dark] {
                    let paper = theme.palette(in: scheme).paper
                    let ratio = Self.contrast(family.ink(in: scheme), on: paper)
                    #expect(
                        ratio >= 4.5,
                        "\(family) on \(theme) \(scheme == .dark ? "dark" : "light") is \(ratio) to one"
                    )
                }
            }
        }
    }

    /// **Blue is what can be pressed, and no subject wears it.** The standard
    /// theme takes the accent the system hands it, which is Apple's blue, and
    /// Solarized states a violet-blue of its own in the same band ; a rubric
    /// printed in either is a line the reader tries to tap. So the band from
    /// cyan to indigo belongs to the controls, and the eight are picked around
    /// it.
    @Test("No subject is printed in a blue")
    func nothingIsBlue() {
        // What the band is for, stated where it is enforced : the two themes
        // that name an accent rather than a warmth both name one in it.
        for theme in [Theme.standard, .solarized] {
            for scheme in [ColorScheme.light, .dark] {
                let hue = Self.hue(theme.palette(in: scheme).accent)
                #expect(hue > Self.blue.lowerBound && hue < Self.blue.upperBound)
            }
        }

        for family in TopicFamily.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let ink = family.ink(in: scheme)

                // A grey has no hue worth the name. The plain colour is four
                // parts in a hundred off neutral, and reading the last bit of
                // its blue channel as a colour would fail it for nothing.
                guard Self.saturation(ink) > 0.15 else { continue }

                let hue = Self.hue(ink)
                #expect(
                    !Self.blue.contains(hue),
                    "\(family) in \(scheme == .dark ? "dark" : "light") is at \(Int(hue)) degrees, which is a blue"
                )
            }
        }
    }

    /// **The colour is reached through the mark, so every mark has to answer.**
    /// A section whose glyph is in no family would be printed in the plain
    /// colour, which is what the two sections that sort nothing wear : the page
    /// would still draw, and `Cinéma` would be grey among the magenta.
    @Test("Every section's mark names a family, and no two sections share a mark")
    func everyMarkAnswers() {
        #expect(StandardTopics.families.count == StandardTopics.all.count)

        for section in StandardTopics.all {
            #expect(StandardTopics.family(of: section.symbol) == section.family)
        }
    }

    /// Every colour is worn by something, and nothing is coloured by accident.
    @Test("Every family is worn, and the catalogue is grouped as the page says")
    func everyFamilyIsWorn() {
        let worn = Set(StandardTopics.all.map(\.family))
        #expect(worn == Set(TopicFamily.allCases))

        // The four the reader is likeliest to name : the example the colour was
        // asked for, the section beside it, and the two the catalogue took up
        // last.
        #expect(StandardTopics.family(of: "arrow.3.trianglepath") == .land)
        #expect(StandardTopics.family(of: "tree") == .land)
        #expect(StandardTopics.family(of: "camera") == .culture)
        #expect(StandardTopics.family(of: "building.columns") == .publicLife)
    }

    /// A subject the reader wrote wears a mark from the catalogue's own
    /// palette, so it is coloured by the family whose glyph they picked ; the
    /// tag everything falls back to belongs to no family and is printed plain.
    @Test("A mark from no catalogue is printed plain")
    func theTagIsPlain() {
        #expect(StandardTopics.family(of: Topic.defaultSymbol) == .plain)
        #expect(StandardTopics.family(of: "not.a.symbol.anybody.has") == .plain)
    }

    /// Where a colour stops being a green or a violet and starts being
    /// something to press, in degrees around the wheel : cyan at one end,
    /// indigo at the other.
    private static let blue: ClosedRange<Double> = 190...265

    /// The hue, in degrees, as a colour wheel states it.
    private static func hue(_ ink: Ink) -> Double {
        let high = max(ink.red, ink.green, ink.blue)
        let span = high - min(ink.red, ink.green, ink.blue)
        guard span > 0 else { return 0 }

        let degrees =
            switch high {
            case ink.red: ((ink.green - ink.blue) / span).truncatingRemainder(dividingBy: 6)
            case ink.green: (ink.blue - ink.red) / span + 2
            default: (ink.red - ink.green) / span + 4
            }
        return (degrees * 60 + 360).truncatingRemainder(dividingBy: 360)
    }

    /// How much colour there is in it at all, which is what tells a hue from a
    /// grey that happens to lean.
    private static func saturation(_ ink: Ink) -> Double {
        let high = max(ink.red, ink.green, ink.blue)
        guard high > 0 else { return 0 }
        return (high - min(ink.red, ink.green, ink.blue)) / high
    }

    /// The ratio between two colours, as the accessibility guidelines state it.
    private static func contrast(_ ink: Ink, on paper: Ink) -> Double {
        let (first, second) = (luminance(ink), luminance(paper))
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private static func luminance(_ ink: Ink) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(ink.red) + 0.7152 * channel(ink.green) + 0.0722 * channel(ink.blue)
    }
}
