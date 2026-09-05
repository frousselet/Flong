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
