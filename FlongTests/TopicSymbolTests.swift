//
//  TopicSymbolTests.swift
//  FlongTests
//
//  Created by François Rousselet on 04/09/2026.
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

/// The mark every subject wears.
@Suite("The marks the subjects wear")
struct TopicSymbolTests {

    /// **The one thing a build cannot catch.** `Image(systemName:)` takes any
    /// string at all and draws nothing where the system has no such symbol, so
    /// a typo in the catalogue is a pill with a hole in it on every page, in
    /// every language, and the compiler is perfectly happy about it.
    @Test("Every mark in the catalogue is a symbol the system has")
    func everySymbolExists() {
        for section in StandardTopics.all {
            #expect(Self.exists(section.symbol), "\(section.symbol) is not a symbol the system knows")
        }
        #expect(Self.exists(Topic.defaultSymbol))
    }

    @Test("Every mark a reader may pick is one too")
    func everyPaletteSymbolExists() {
        for symbol in StandardTopics.palette {
            #expect(Self.exists(symbol), "\(symbol) is not a symbol the system knows")
        }
    }

    /// **One section, one mark, and the two travel together.** A name in one
    /// array and a glyph at the same index in another is two places to forget
    /// one : insert a section into the middle of the first and the whole of the
    /// second is one out, every page still draws, and `Cinéma` wears a tractor.
    @Test("Every section has a mark, and the two are one value")
    func everySectionIsMarked() {
        #expect(StandardTopics.all.count == 52)
        #expect(StandardTopics.all.allSatisfy { !$0.symbol.isEmpty })

        let names = StandardTopics.names(for: Locale(identifier: "en"))
        let marks = StandardTopics.symbols(for: Locale(identifier: "en"))
        #expect(names.count == StandardTopics.all.count)
        #expect(names.allSatisfy { marks[$0] != nil })
    }

    /// What the sections wear is what a reader may wear : a picker of every
    /// symbol the system has is a thousand glyphs and a search field, and a
    /// subject wearing a mark from another family would be the one pill on the
    /// row that does not belong to the page.
    @Test("The palette is the catalogue's own marks, each once")
    func paletteIsTheCatalogue() {
        #expect(StandardTopics.palette.first == Topic.defaultSymbol)
        #expect(Set(StandardTopics.palette).count == StandardTopics.palette.count)
        #expect(Set(StandardTopics.all.map(\.symbol)).isSubset(of: Set(StandardTopics.palette)))
    }

    private static func exists(_ symbol: String) -> Bool {
        #if os(iOS)
            UIImage(systemName: symbol) != nil
        #else
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
        #endif
    }
}
