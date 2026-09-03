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

    @Test("The third way to find a source speaks French")
    func popularFeeds() {
        #expect(String(localized: "Popular feeds", locale: french) == "Flux populaires")
        #expect(String(localized: "Share my sources", locale: french) == "Partager mes sources")
        #expect(String(localized: "Share the sources I follow", locale: french) == "Partager les sources que je suis")
        #expect(String(localized: "Your contributor code", locale: french) == "Votre code de contributeur")
        #expect(String(localized: "Include in popular feeds", locale: french) == "Inclure dans les flux populaires")
        #expect(String(localized: "Vouched for", locale: french) == "Recommandé")
    }

    @Test("The repair for a source removed elsewhere speaks French")
    func tidyingTheSources() {
        #expect(String(localized: "Tidy the sources", locale: french) == "Nettoyer les sources")
        #expect(String(localized: "Sources removed elsewhere", locale: french) == "Sources retirées ailleurs")
        #expect(String(localized: "Nothing to tidy", locale: french) == "Rien à nettoyer")
        #expect(
            String(localized: "Every source here is one your iCloud still has.", locale: french)
                == "Chaque source d'ici est une source que votre iCloud détient toujours."
        )
        // The one that says nothing was changed, which is what a reader whose
        // device could not reach iCloud has to be able to read.
        #expect(
            String(localized: "Your iCloud could not be asked", locale: french)
                == "Votre iCloud n'a pas pu être interrogé"
        )
    }

    @Test("A count of readers is said in the singular and in the plural")
    func readerCounts() {
        // The empty page states how many readers the pool has heard from, and
        // one reader is not `1 lecteurs`. French counts zero in the singular
        // too, which is the whole reason the variation exists rather than an
        // `s` appended to a number.
        #expect(inFrench("\(0) readers have shared their sources.") == "0 lecteur a partagé ses sources.")
        #expect(inFrench("\(1) readers have shared their sources.") == "1 lecteur a partagé ses sources.")
        #expect(inFrench("\(12) readers have shared their sources.") == "12 lecteurs ont partagé leurs sources.")
        #expect(inFrench("Followed by \(12) readers") == "Suivi par 12 lecteurs")
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

        // The fourth, about who the article is about rather than who signed it.
        // `Personnalités favorites` and `Auteurs favoris` have to stay two
        // different words in French as they are in English : the whole of the
        // distinction is that they are different judgements.
        #expect(String(localized: "Favourite newsmakers", locale: french) == "Personnalités favorites")
        #expect(
            String(localized: "Add to favourite newsmakers", locale: french) == "Ajouter aux personnalités favorites"
        )
        #expect(
            String(localized: "Remove from favourite newsmakers", locale: french)
                == "Retirer des personnalités favorites"
        )
        #expect(String(localized: "Authors", locale: french) == "Auteurs")
    }

    @Test("What Flong says about a source it was asked about is in French too")
    func tellingAboutASource() {
        #expect(String(localized: "Notify every new article", locale: french) == "Notifier chaque nouvel article")
        #expect(
            String(localized: "Stop notifying new articles", locale: french)
                == "Ne plus notifier les nouveaux articles"
        )
        #expect(String(localized: "New articles", locale: french) == "Nouveaux articles")

        // The notice itself, which is the part a reader reads outside the
        // application and the one nobody would notice was English.
        #expect(String(localized: "\(3) new articles", locale: french) == "3 nouveaux articles")
        #expect(
            String(localized: "\("Le Monde") : \(3) new articles", locale: french)
                == "Le Monde : 3 nouveaux articles"
        )
    }

    @Test("The editor of a source is in French too")
    func editingASource() {
        #expect(String(localized: "Edit the source", locale: french) == "Modifier la source")
        #expect(String(localized: "Address of the feed", locale: french) == "Adresse du flux")
        #expect(String(localized: "Address of the site", locale: french) == "Adresse du site")
        #expect(String(localized: "Show the address", locale: french) == "Afficher l’adresse")
        #expect(
            String(localized: "What identifies you in these addresses", locale: french)
                == "Ce qui vous identifie dans ces adresses"
        )
        #expect(String(localized: "How often", locale: french) == "Fréquence")
        #expect(String(localized: "Automatic", locale: french) == "Automatique")
        #expect(String(localized: "Failures in a row", locale: french) == "Échecs consécutifs")
        #expect(String(localized: "This address is a secret", locale: french) == "Cette adresse est un secret")

        // The one refusal this screen has of its own, read by somebody who has
        // just typed an address a second source is already served at.
        #expect(
            String(localized: "Another source is already followed at this address.", locale: french)
                == "Une autre source est déjà suivie à cette adresse."
        )
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

    @Test("The reader's own panel names its pages in French")
    func readerPages() {
        // The panel shows and its pages set, so the six rows are the whole of
        // how anybody finds a setting : a name that fell back to English would
        // be a subject a French reader cannot look for.
        #expect(inFrench(ReaderPage.profile.title) == "Profil")
        #expect(inFrench(ReaderPage.appearance.title) == "Apparence")
        #expect(inFrench(ReaderPage.popular.title) == "Flux populaires")
        #expect(inFrench(ReaderPage.sites.title) == "Sites abonnés")
        #expect(inFrench(ReaderPage.data.title) == "Vos données")
        #expect(inFrench(ReaderPage.about.title) == "À propos")
    }

    @Test("What the application says about itself is in French too")
    func about() {
        #expect(String(localized: "Source code", locale: french) == "Code source")
        #expect(String(localized: "License", locale: french) == "Licence")

        // The two sentences that say what Flong does without, which are the
        // only claim the page makes.
        let claim = String(
            localized: """
                A feed reader with no server, no account and nothing to sign in to. Every device collects \
                the feeds itself and keeps them in a database of its own.
                """,
            locale: french
        )
        #expect(claim.hasPrefix("Un lecteur de flux sans serveur"))
    }

    @Test("The two directories of people are named apart in French too")
    func directories() {
        // One is who signed a piece, the other who it is about, and a reader
        // looking at two squares side by side has to be able to tell them
        // apart at a glance.
        #expect(String(localized: "Authors", locale: french) == "Auteurs")
        #expect(String(localized: "Newsmakers", locale: french) == "Personnalités")
        #expect(String(localized: "Search newsmakers", locale: french) == "Rechercher une personnalité")
        #expect(String(localized: "All newsmakers", locale: french) == "Toutes les personnalités")
        #expect(String(localized: "Nobody named yet", locale: french) == "Personne n'est encore cité")

        // The bell says what it interrupts for, and for a person the articles
        // are about that is not `a new article` but `an article about them`.
        #expect(
            String(localized: "Notify every article about them", locale: french)
                == "Notifier chaque article à leur sujet"
        )
        #expect(
            String(localized: "Stop notifying articles about them", locale: french)
                == "Ne plus notifier les articles à leur sujet"
        )
    }

    @Test("The people in a shared collection are named in French")
    func shareMembers() {
        #expect(String(localized: "In this collection", locale: french) == "Dans cette collection")
        #expect(String(localized: "You", locale: french) == "Vous")
        #expect(String(localized: "Someone", locale: french) == "Quelqu'un")
        #expect(String(localized: "Invited", locale: french) == "Invitation envoyée")
        #expect(String(localized: "Shared this", locale: french) == "A partagé")
        // It reads on from the name above it, so it agrees with it : `Vous`
        // takes `Avez partagé` where a third person takes `A partagé`.
        #expect(String(localized: "You shared this", locale: french) == "Avez partagé")
        #expect(String(localized: "Reading only", locale: french) == "Lecture seule")
        #expect(String(localized: "Remove from the collection", locale: french) == "Retirer de la collection")
        #expect(String(localized: "\("Ada")", locale: french) == "Ada")
        #expect(String(localized: "Remove \("Ada")?", locale: french) == "Retirer Ada ?")
        #expect(String(localized: "this person", locale: french) == "cette personne")

        // What is not said in the question is said under it : a reader who
        // takes somebody out has to know what happens to what they filed.
        #expect(
            String(localized: "They lose the collection. What they already filed stays in it.", locale: french)
                == "La personne perd la collection. Ce qu'elle y a déjà ajouté y reste."
        )

        // Read out where the faces themselves say nothing.
        #expect(String(localized: "\(1) people", locale: french) == "1 personne")
        #expect(String(localized: "\(4) people", locale: french) == "4 personnes")
    }
}
