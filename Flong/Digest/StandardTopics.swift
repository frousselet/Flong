//
//  StandardTopics.swift
//  Flong
//
//  Created by François Rousselet on 31/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The sections a newspaper has always had.
///
/// **A vocabulary the reader does not have to build.** The model used to start
/// with nothing and name every subject itself, so the first weeks of a library
/// were a drift of near-synonyms and the reader had nothing to hold an opinion
/// about until the drift settled. These are there from the first launch : the
/// names any reader already knows, because every paper and every news
/// application has used them for a century.
///
/// **They are seeded and then ordinary.** Nothing keeps them apart afterwards
/// except that the reader may not delete them : a story is filed under one the
/// same way it is filed under any other, and a preference attached to one works
/// the same. What they buy is a page that reads sensibly on its first day.
///
/// **Stored in the reader's language, like everything else the model writes.**
/// A subject is a string in the store, and the model is shown strings and
/// answers with them ; a key resolved at each draw would have to be resolved
/// for the model too, which would mean translating what it answers back. The
/// cost is the one the model's own subjects already carry : a reader who
/// changes language keeps the names they had.
nonisolated enum StandardTopics {
    /// The list, in the order a page would print them.
    static let all: [LocalizedStringResource] = [
        "Politique",
        "International",
        "Économie",
        "Société",
        "Écologie",
        "Sciences",
        "Technologie",
        "Santé",
        "Culture",
        "Sport",
        "Éducation",
        "Justice",
        "Médias",
    ]

    /// The names as this reader reads them.
    static func names(for locale: Locale = .current) -> [String] {
        resolve(all, in: locale)
    }

    /// The words that name the news itself rather than a field of it.
    ///
    /// **`Actualité` is the failure this exists for.** It is true of every
    /// story on the page, so filing under it sorts nothing and a pill wearing
    /// it is a pill that says `everything`. A subject earns its place by
    /// telling one story apart from the rest, and a word that would fit every
    /// article ever published cannot do that whatever else is true of it.
    ///
    /// The same argument as the one that rules a headline : every word has to
    /// carry information, and `Le numérique en question` carries none. This is
    /// that rule applied to a single word, where it is at its sharpest.
    ///
    /// Whole names only, folded. `Actualité internationale` is narrower than
    /// the page and is left alone ; it is `Actualité` on its own that says
    /// nothing.
    static let namesForNewsItself: [LocalizedStringResource] = [
        "Actualité",
        "Actualités",
        "Informations",
        "Divers",
        "Général",
        "Résumé",
        "Titres",
        "Sujets",
    ]

    /// The words for news in general, as this reader reads them and as the
    /// catalogue's own language spells them.
    ///
    /// Both, because a model asked for French answers in English often enough
    /// to be worth the second list, and a subject that says nothing says
    /// nothing in either language.
    static func generalNames(for locale: Locale = .current) -> [String] {
        resolve(namesForNewsItself, in: locale) + resolve(namesForNewsItself, in: Locale(identifier: "en"))
    }

    private static func resolve(_ names: [LocalizedStringResource], in locale: Locale) -> [String] {
        names.map {
            var resource = $0
            resource.locale = locale
            return String(localized: resource)
        }
    }
}
