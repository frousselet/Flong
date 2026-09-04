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
    /// One section : what it is called, and the mark it wears.
    ///
    /// **The two together and never two lists.** A name in one array and a
    /// glyph at the same index in another is two places to forget one, and the
    /// day somebody inserts a section into the middle of the first the whole of
    /// the second is one out and nobody notices : every page is still drawn,
    /// with `Cinéma` wearing a tractor.
    nonisolated struct Section: Sendable {
        let name: LocalizedStringResource
        let symbol: String

        init(_ name: LocalizedStringResource, _ symbol: String) {
            self.name = name
            self.symbol = symbol
        }
    }

    /// The list, in the order a page would print them.
    ///
    /// **The mark is the thing and never the word.** `Justice` wears a closed
    /// book and not a pair of scales, `Immigration` somebody walking and not a
    /// border : a glyph that illustrates the word rather than the subject is a
    /// rebus, and a reader scanning a row of pills is reading shapes rather
    /// than solving them. Where the subject has no thing, the section it
    /// belongs to lends one.
    ///
    /// Every one of them is checked against the system at test time, since a
    /// symbol that does not exist draws nothing at all and a pill with a hole
    /// in it is not something a build catches.
    static let all: [Section] = [
        // Public life
        Section("Politics", "building.columns"),
        Section("International", "globe"),
        Section("European Union", "flag"),
        Section("Elections", "list.bullet.rectangle"),
        Section("Defence", "shield"),
        Section("Justice", "book.closed"),
        Section("Immigration", "figure.walk"),
        Section("Human rights", "hand.raised"),
        Section("Local news", "mappin.and.ellipse"),

        // Money and work
        Section("Economy", "chart.line.uptrend.xyaxis"),
        Section("Business", "briefcase"),
        Section("Employment", "hammer"),
        Section("Finance", "banknote"),
        Section("Consumer", "cart"),
        Section("Housing", "house"),
        Section("Agriculture", "leaf"),
        Section("Industry", "gearshape.2"),
        Section("Energy", "bolt"),
        Section("Transport", "tram"),

        // Living
        Section("Education", "graduationcap"),
        Section("Health", "heart"),
        Section("Food", "fork.knife"),
        Section("Religion", "hands.sparkles"),
        Section("Crime", "exclamationmark.triangle"),
        Section("Environment", "tree"),
        Section("Climate", "thermometer"),
        Section("Weather", "cloud.sun"),

        // Science and technology
        Section("Science", "atom"),
        Section("Technology", "cpu"),
        Section("Artificial intelligence", "brain"),
        Section("Software", "chevron.left.forwardslash.chevron.right"),
        Section("Cybersecurity", "lock.shield"),
        Section("Privacy", "eye.slash"),
        Section("Social media", "bubble.left.and.bubble.right"),
        Section("Telecoms", "antenna.radiowaves.left.and.right"),
        Section("Space", "moon.stars"),
        Section("Travel", "airplane"),

        // Culture
        Section("Media", "newspaper"),
        Section("Cinema", "film"),
        Section("TV series", "tv"),
        Section("Music", "music.note"),
        Section("Books", "books.vertical"),
        Section("Art", "paintpalette"),
        Section("Architecture", "building.2"),
        Section("Fashion", "tshirt"),
        Section("Video games", "gamecontroller"),
        Section("History", "hourglass"),

        // Sport, and the two that sort nothing
        Section("Sport", "figure.run"),
        Section("Society", "person.3"),
        Section("Culture", "theatermasks"),
    ]

    /// The marks a reader may pick from for a subject of their own.
    ///
    /// **The catalogue's own, and nothing else.** A picker of every symbol the
    /// system has is a thousand glyphs and a search field, which is a great deal
    /// of interface for a decision that takes a second ; and a subject wearing
    /// a mark from a different family would be the one pill on the row that
    /// does not belong to the page. What the sections wear is what a reader may
    /// wear, plus the tag everything falls back to.
    ///
    /// In the catalogue's order, so the picker reads as the page does : public
    /// life, money, living, science, culture, sport.
    static let palette: [String] = {
        var seen = Set<String>()
        return ([Topic.defaultSymbol] + all.map(\.symbol)).filter { seen.insert($0).inserted }
    }()

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
        resolve(all.map(\.name), in: locale)
    }

    /// The mark each section wears, by the name this reader reads it under.
    static func symbols(for locale: Locale = .current) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: zip(resolve(all.map(\.name), in: locale), all.map(\.symbol))
        )
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
