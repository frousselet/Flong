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

    /// A resource in French, which is asked for by stating the locale on the
    /// resource rather than beside it : `String(localized:)` takes one or the
    /// other and not both.
    private func inFrench(_ resource: LocalizedStringResource) -> String {
        var asked = resource
        asked.locale = french
        return String(localized: asked)
    }

    @Test("Plain strings reach their French translation")
    func plainStrings() {
        #expect(String(localized: "Unread", locale: french) == "Non lus")
        #expect(String(localized: "Import an OPML file", locale: french) == "Importer un fichier OPML")
        #expect(String(localized: "Mark all as read", locale: french) == "Tout marquer comme lu")
        #expect(String(localized: "Add to favourites", locale: french) == "Mettre en favori")
        #expect(String(localized: "Choose a picture", locale: french) == "Choisir une photo")
        #expect(String(localized: "Subscribed sites", locale: french) == "Sites abonnés")
    }

    @Test("The two kinds of favourite are told apart in French too")
    func favourites() {
        // `Favoris` was enough while the star was the only one of them. Beside
        // a favourite source it is not, and neither square may be called it.
        #expect(String(localized: "Starred articles", locale: french) == "Articles favoris")
        #expect(String(localized: "Favourite sources", locale: french) == "Sources favorites")
        #expect(String(localized: "Add to favourite sources", locale: french) == "Ajouter aux sources favorites")
        #expect(String(localized: "Remove from favourite sources", locale: french) == "Retirer des sources favorites")
        #expect(String(localized: "Favourite source", locale: french) == "Source favorite")

        // The third of them. `Auteurs favoris` is the square ; the two commands
        // are the way in and the way out, and neither may be called `Favoris`
        // either.
        #expect(String(localized: "Favourite authors", locale: french) == "Auteurs favoris")
        #expect(String(localized: "Add to favourite authors", locale: french) == "Ajouter aux auteurs favoris")
        #expect(String(localized: "Remove from favourite authors", locale: french) == "Retirer des auteurs favoris")
        #expect(String(localized: "Authors", locale: french) == "Auteurs")
    }

    @Test("The one command that cannot be undone says so in French")
    func dangerZone() {
        #expect(String(localized: "Danger zone", locale: french) == "Zone de danger")
        #expect(String(localized: "Delete everything", locale: french) == "Tout supprimer")
        #expect(String(localized: "Delete everything?", locale: french) == "Tout supprimer ?")

        // The sentence a reader reads before they confirm. A key that drifted
        // would leave the English one standing in the French alert, which is
        // the worst place in the application to be reading a language you may
        // not have.
        let warning = String(
            localized: """
                Your subscriptions, every article, everything you kept and every site you are signed in to, \
                on this device and in your iCloud. This cannot be undone. Another device that still has them \
                will put its own copy back.
                """,
            locale: french
        )
        #expect(warning.hasPrefix("Vos abonnements"))
        #expect(warning.contains("irréversible"))
    }

    @Test("The other command that cannot be undone says so in French too")
    func removingASource() {
        let asked = String(localized: "Delete \("Le Monde")?", locale: french)
        #expect(asked == "Supprimer Le Monde ?")

        // The two sentences a reader reads before they confirm, and the half of
        // each that matters : what goes beyond the source itself, and that it
        // does not come back.
        let source = String(
            localized: """
                Its articles go with it, including the ones you starred, wrote on or filed. This cannot be undone.
                """,
            locale: french
        )
        #expect(source.hasPrefix("Ses articles partent avec elle"))
        #expect(source.hasSuffix("C'est sans retour."))

        let publisher = String(
            localized: """
                Every source under it goes, and their articles with them, including the ones you starred, \
                wrote on or filed. This cannot be undone.
                """,
            locale: french
        )
        #expect(publisher.hasPrefix("Toutes ses sources partent"))
        #expect(publisher.hasSuffix("C'est sans retour."))
    }

    @Test("Naming a publisher says which one it is putting back")
    func namingAPublisher() {
        let french = String(
            localized: "The sources stay where they are. Leave it empty to call it \("lemonde.fr") again.",
            locale: self.french
        )

        #expect(french.hasPrefix("Les sources ne bougent pas."))
        #expect(french.hasSuffix("lemonde.fr."))
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
        let written = moment.formatted(ArticleMoment.stamp(moment, now: moment))

        // Three different things wear the same shape, and the word is what
        // tells them apart : a publisher's own date, a publisher's own change
        // to it, and the moment an undated article reached this device.
        //
        // **The moment is written out and no longer counted back from now**,
        // and French wants the article the relative form did not : `Reçu le 1
        // sept.`, where `Reçu il y a deux heures` took none. A key that kept
        // the old shape would read `Reçu 1 sept.`, which is not French.
        #expect(String(localized: "Received on \(written)", locale: french).hasPrefix("Reçu le"))
        #expect(String(localized: "Published on \(written)", locale: french).hasPrefix("Publié le"))
        #expect(String(localized: "updated on \(written)", locale: french).hasPrefix("modifié le"))
        #expect(String(localized: "updated", locale: french) == "modifié")

        // What a story's moment says to anyone listening, which is the one
        // place its glyph can be read out.
        let ago = moment.formatted(.relative(presentation: .named))
        #expect(String(localized: "Updated \(ago)", locale: french).hasPrefix("Mis à jour"))
    }

    @Test("An article's moment carries the year only where it is not this one")
    func articleYears() {
        let now = Date(timeIntervalSince1970: 1_787_646_600)
        let lastYear = now.addingTimeInterval(-400 * 24 * 60 * 60)

        // A stamp carrying `2026` on every line of today's news is a column of
        // noise ; one that drops the year on an article from another year is a
        // date that lies about which day it was.
        #expect(!now.formatted(ArticleMoment.stamp(now, now: now)).contains("2026"))
        #expect(lastYear.formatted(ArticleMoment.stamp(lastYear, now: now)).contains("2025"))
    }

    @Test("Every theme is named and explained in French")
    func themes() {
        // A theme is chosen from three words, so the three words have to be the
        // right ones : `Défaut` and `Papier` are translated, and `Solarized` is
        // a name and stays as its author wrote it.
        #expect(inFrench(Theme.standard.name) == "Défaut")
        #expect(inFrench(Theme.paper.name) == "Papier")
        #expect(inFrench(Theme.solarized.name) == "Solarized")

        #expect(String(localized: "Appearance", locale: french) == "Apparence")
        #expect(String(localized: "Theme", locale: french) == "Thème")

        // The line under each name, which is what says what the colours do. A
        // key that drifted would leave the English standing under a French
        // name, which is the one place a reader is comparing three lines.
        #expect(inFrench(Theme.standard.explanation).hasPrefix("Titres à empattements, dans"))
        #expect(inFrench(Theme.paper.explanation).hasPrefix("Titres à empattements"))
        #expect(inFrench(Theme.solarized.explanation).hasPrefix("Titres en chasse fixe"))
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
