//
//  LocalizationTests.swift
//  FlongTests
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

/// The interface is authored in English and shipped in French too.
///
/// A key that drifts from what the catalog holds does not fail to build : it
/// falls back to the English key, silently, in the French interface. These
/// expectations are what notices.
@Suite("Localization")
struct LocalizationTests {
    private let french = Locale(identifier: "fr_FR")

    @Test("Plain strings reach their French translation")
    func plainStrings() {
        #expect(String(localized: "Unread", locale: french) == "Non lus")
        #expect(String(localized: "Import an OPML file", locale: french) == "Importer un fichier OPML")
        #expect(String(localized: "Mark all as read", locale: french) == "Tout marquer comme lu")
        #expect(String(localized: "Add to favourites", locale: french) == "Mettre en favori")
    }

    @Test("The import summary agrees with French plural rules")
    func plurals() {
        // French treats zero and one alike, which is the whole reason these are
        // plural entries rather than interpolated sentences.
        #expect(String(localized: "\(0) feeds added", locale: french) == "0 flux ajouté")
        #expect(String(localized: "\(1) feeds added", locale: french) == "1 flux ajouté")
        #expect(String(localized: "\(42) feeds added", locale: french) == "42 flux ajoutés")
        #expect(String(localized: "\(3) already followed", locale: french) == "3 déjà suivis")
        #expect(String(localized: "\(1) ignored", locale: french) == "1 ignoré")
    }
}
