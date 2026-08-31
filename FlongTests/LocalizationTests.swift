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
        #expect(String(localized: "Choose a picture", locale: french) == "Choisir une photo")
        #expect(String(localized: "Your profile", locale: french) == "Votre profil")
    }

    @Test("Every phase the front page can be showing has its French")
    func workPhases() {
        let phases = WorkPhase.allCases

        // A phase whose key drifts from the catalog does not fail to build : it
        // falls back to the English key, in the French interface, at the head
        // of the front page.
        for phase in phases {
            var french = phase.title
            french.locale = self.french
            var english = phase.title
            english.locale = Locale(identifier: "en")

            #expect(String(localized: french) != String(localized: english))
        }

        #expect(String(localized: "Fetching the feeds", locale: french) == "Récupération des flux")
        #expect(String(localized: "Filing the subjects", locale: french) == "Classement par thématique")
        #expect(String(localized: "In progress", locale: french) == "En cours")
    }

    @Test("What is known about an article's moment reaches its French")
    func articleMoments() {
        let moment = Date(timeIntervalSince1970: 1_787_646_600)
        let relative = moment.formatted(.relative(presentation: .numeric))

        // Three different things wear the same shape, and the word is what
        // tells them apart : a publisher's own date, a publisher's own change
        // to it, and the moment an undated article reached this device.
        #expect(String(localized: "Received \(relative)", locale: french).hasPrefix("Reçu"))
        #expect(String(localized: "Published \(relative)", locale: french).hasPrefix("Publié"))
        #expect(String(localized: "updated \(relative)", locale: french).hasPrefix("modifié"))
        #expect(String(localized: "updated", locale: french) == "modifié")
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
