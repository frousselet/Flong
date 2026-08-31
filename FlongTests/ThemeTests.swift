//
//  ThemeTests.swift
//  FlongTests
//
//  Created by François Rousselet on 31/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import SwiftUI
import Testing

@testable import Flong

/// The three ways the application can be set.
///
/// A theme is mostly looked at rather than asserted about, and what is checked
/// here is the half that can be : that each of the three answers differently,
/// that no appearance is left half stated, and that a page rendered in one
/// carries it.
@Suite("Themes")
struct ThemeTests {
    @Test("Each theme sets headlines in a face of its own")
    func faces() {
        // The whole point of there being three : a reader tells them apart in
        // the first second, and they tell them apart by this.
        let headlines = Theme.allCases.map { $0.headline(.title) }
        #expect(Set(headlines).count == Theme.allCases.count)

        #expect(Theme.standard.headline(.title) == .system(.title, design: .default, weight: .semibold))
        #expect(Theme.paper.headline(.title) == .system(.title, design: .serif, weight: .semibold))
        #expect(Theme.solarized.headline(.title) == .system(.title, design: .monospaced, weight: .semibold))
    }

    @Test("What the application says about an article is sans in all three")
    func voice() {
        // The metadata is the application's own voice. A theme that set it in
        // the headline's face would have lost the distinction the typography
        // exists to make, and a monospace caption under every story would be
        // the loudest quiet thing on the page.
        for theme in Theme.allCases {
            #expect(theme.metadata == .system(.caption, design: .default))
        }
        #expect(Theme.solarized.standfirst() == .system(.subheadline, design: .default))
        #expect(Theme.paper.standfirst() == .system(.subheadline, design: .serif))
    }

    @Test("The standard theme is the system's own and paints nothing")
    func standardPaintsNothing() {
        #expect(!Theme.standard.paints)
        #expect(Theme.paper.paints)
        #expect(Theme.solarized.paints)
    }

    @Test("No theme leaves an appearance half stated")
    func bothAppearances() {
        for theme in Theme.allCases {
            let light = theme.palette(in: .light)
            let dark = theme.palette(in: .dark)

            // A dark page that kept the light one's paper is a theme that was
            // only ever tried with the lights on.
            #expect(light.paper != dark.paper)
            #expect(light.ink != dark.ink)

            // And ink on paper, in both, rather than ink on ink.
            #expect(light.ink != light.paper)
            #expect(dark.ink != dark.paper)
        }
    }

    @Test("A colour is written once and read as a colour and as a rule")
    func ink() {
        #expect(Ink(0xFD_F6_E3).css == "rgb(253, 246, 227)")
        #expect(Ink(0x00_00_00).css == "rgb(0, 0, 0)")
        // A hairline lets the paper through, and hexadecimal has nowhere to
        // put that.
        #expect(Ink(0x58_6E_75, alpha: 0.2).css == "rgba(88, 110, 117, 0.2)")
    }

    // MARK: - What the reader chose, and where it is kept

    private func preferences() -> Preferences {
        let defaults = UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        return Preferences(cloud: nil, local: defaults)
    }

    @Test("A theme is remembered, and the system's own is what is answered first")
    func remembered() {
        let store = preferences()

        #expect(store.theme == .standard)

        store.theme = .solarized
        #expect(store.theme == .solarized)
    }

    @Test("A theme nobody recognizes falls back rather than failing")
    func unknown() {
        let defaults = UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        // What a newer version writing a fourth theme leaves behind on an older
        // one. An application that refused to draw itself over a preference
        // would be worse than one drawn plainly.
        defaults.set("midnight", forKey: "interface.theme")

        #expect(Preferences(cloud: nil, local: defaults).theme == .standard)
    }

    @Test("The window keeps the theme where the reader's other devices will find it")
    @MainActor
    func carried() throws {
        let defaults = UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        let preferences = Preferences(cloud: nil, local: defaults)
        let model = AppModel(database: try AppDatabase.inMemory(), preferences: preferences)

        #expect(model.theme == .standard)

        model.theme = .paper
        #expect(preferences.theme == .paper)

        // And a window opened afterwards is in the theme the last one was left
        // in, which is the whole of what carrying it means.
        #expect(AppModel(database: try AppDatabase.inMemory(), preferences: preferences).theme == .paper)
    }
}

/// The rendered article is a page of Flong, not a page of the web.
@Suite("A themed article")
struct ThemedDocumentTests {
    private func article() -> Article {
        Article(
            id: UUID(),
            title: "Un match",
            feedTitle: "Le Monde",
            url: URL(string: "https://www.lemonde.fr/un-match"),
            publishedAt: Date(timeIntervalSince1970: 1_772_000_000),
            bodyHTML: "<p>Quelque chose est arrivé.</p>"
        )
    }

    @Test("The page is set in the theme's own faces")
    func faces() {
        let plain = ArticleDocument.html(for: article(), theme: .standard)
        #expect(plain.contains("--headline: \(Theme.sansStack);"))
        #expect(plain.contains("--body: \(Theme.sansStack);"))

        let printed = ArticleDocument.html(for: article(), theme: .paper)
        #expect(printed.contains("--headline: \(Theme.serifStack);"))
        #expect(printed.contains("--body: \(Theme.serifStack);"))

        // Monospace headlines over a sans body : the one theme whose two faces
        // are different from each other.
        let solarized = ArticleDocument.html(for: article(), theme: .solarized)
        #expect(solarized.contains("--headline: \(Theme.monoStack);"))
        #expect(solarized.contains("--body: \(Theme.sansStack);"))

        // And the application's own voice stays sans in all three, so a byline
        // never wears the headline's face.
        for page in [plain, printed, solarized] {
            #expect(page.contains("--voice: \(Theme.sansStack);"))
        }
    }

    @Test("The page is printed on the theme's own paper, in both appearances")
    func paper() {
        let page = ArticleDocument.html(for: article(), theme: .solarized)

        #expect(page.contains("--paper: \(Theme.solarized.palette(in: .light).paper.css);"))
        #expect(page.contains("--paper: \(Theme.solarized.palette(in: .dark).paper.css);"))

        // Both are always stated : a web view is handed a document and cannot
        // be handed another one when the reader turns the lights off, so
        // `prefers-color-scheme` is what has to answer.
        #expect(page.contains("@media (prefers-color-scheme: dark)"))
        #expect(page.contains("color-scheme: light dark;"))
    }

    @Test("A page asked for nothing in particular is the system's own")
    func standardByDefault() {
        #expect(ArticleDocument.html(for: article()) == ArticleDocument.html(for: article(), theme: .standard))
    }
}
