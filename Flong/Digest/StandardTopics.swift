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
/// **A vocabulary the reader does not have to build, and the only one the model
/// may use.** The model used to name subjects of its own when nothing it was
/// shown fitted, and the first weeks of a library were a drift of near
/// synonyms : `Science` beside `Sciences`, `Sports` beside `Sport`, the English
/// word for a section the reader already had. It names nothing now. What exists
/// is this catalogue and whatever the reader writes themselves, and a story is
/// filed under one or two of those or under nothing.
///
/// **Fifty, because the model cannot invent past the end of the list.** Thirteen
/// was a set of desks and everything finer landed on the nearest one ; a gap in
/// a list nothing may go outside of is a story misfiled for ever. Fifty is
/// enough that most stories meet something exact, and few enough that a reader
/// can hold an opinion about each name.
///
/// **`Société` and `Culture` are last on purpose.** They are the two that sort
/// nothing, and they are kept because they are the fallbacks and because
/// thirteen years of stores already carry them. The model reads the list in
/// order and is told to prefer the most exact subject that fits, so it should
/// meet them after everything that says something.
///
/// **The names are English here and French in the catalogue.** The catalogue's
/// source language is English, so an English key with a French translation is
/// the way round it is meant to be ; it was the other way about, which made
/// every section a French word hard-coded in Swift.
///
/// **They are seeded and then ordinary.** Nothing keeps them apart afterwards
/// except that the reader may not delete them : a story is filed under one the
/// same way it is filed under any other, and a preference attached to one works
/// the same.
///
/// **Stored in the reader's language, like everything else the model writes.**
/// A subject is a string in the store, and the model is shown strings and
/// answers with them ; a key resolved at each draw would have to be resolved
/// for the model too, which would mean translating what it answers back. The
/// cost is that a reader who changes language keeps the names they had.
nonisolated enum StandardTopics {
    /// The list, in the order a page would print them.
    static let all: [LocalizedStringResource] = [
        // Public life
        "Politics",
        "International",
        "European Union",
        "Elections",
        "Defence",
        "Justice",
        "Immigration",
        "Human rights",
        "Local news",

        // Money and work
        "Economy",
        "Business",
        "Employment",
        "Finance",
        "Consumer",
        "Housing",
        "Agriculture",
        "Industry",
        "Energy",
        "Transport",

        // Living
        "Education",
        "Health",
        "Food",
        "Religion",
        "Crime",
        "Environment",
        "Climate",
        "Weather",

        // Science and technology
        "Science",
        "Technology",
        "Artificial intelligence",
        "Software",
        "Cybersecurity",
        "Privacy",
        "Social media",
        "Telecoms",
        "Space",
        "Travel",

        // Culture
        "Media",
        "Cinema",
        "TV series",
        "Music",
        "Books",
        "Art",
        "Architecture",
        "Fashion",
        "Video games",
        "History",

        // Sport, and the two that sort nothing
        "Sport",
        "Society",
        "Culture",
    ]

    /// Sections that have been renamed, as the name they had and the name they
    /// have.
    ///
    /// **A section is known by its name and by nothing else.** `Topic.name`,
    /// `story_topic.name` and `topic_preference.name` are all the resolved
    /// string, so renaming one without moving the other two leaves the stories
    /// filed under a name that no longer exists and the reader's opinion
    /// attached to it.
    ///
    /// It is done at seeding rather than in a migration because the stored name
    /// is in the reader's language, and a migration runs before anything has
    /// asked what that language is.
    ///
    /// `Écologie` is the one that forced this. In French it names the political
    /// movement first, so a story about the party filed under it rather than
    /// under `Politique` ; and in English the same key was translated `Climate`,
    /// which would have folded a whole ecology backlog into the narrower
    /// `Climat` this catalogue adds beside it.
    static let renamed: [(was: LocalizedStringResource, now: LocalizedStringResource)] = [
        (was: "Écologie", now: "Environment")
    ]

    /// The names as this reader reads them.
    static func names(for locale: Locale = .current) -> [String] {
        resolve(all, in: locale)
    }

    /// The renamings as this reader reads them, old name and new.
    static func renamings(for locale: Locale = .current) -> [(String, String)] {
        renamed.map { (resolve([$0.was], in: locale)[0], resolve([$0.now], in: locale)[0]) }
            .filter { $0.0 != $0.1 }
    }

    private static func resolve(_ names: [LocalizedStringResource], in locale: Locale) -> [String] {
        names.map {
            var resource = $0
            resource.locale = locale
            return String(localized: resource)
        }
    }
}
