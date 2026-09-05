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
/// **Fifty-two, because the model cannot invent past the end of the list.**
/// Thirteen was a set of desks and everything finer landed on the nearest one ;
/// a gap in a list nothing may go outside of is a story misfiled for ever.
/// Fifty-two is enough that most stories meet something exact, and few enough
/// that a reader can hold an opinion about each name.
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
/// **Eight colours across the fifty-two, and never one apiece.** A section
/// belongs to a family and the family is what is printed : blue for the news of
/// the state, teal for money, green for the land, red for the body, orange for
/// ordinary life, violet for science, magenta for culture, and nothing at all
/// for the two that sort nothing. Fifty-two hues cannot be told apart, and the
/// colour is there to be recognized at a glance or ignored. See
/// ``TopicFamily``.
///
/// **They are seeded and then ordinary.** Nothing keeps them apart afterwards
/// except that the reader may not delete them : a story is filed under one the
/// same way it is filed under any other, and a preference attached to one works
/// the same.
///
/// **A subject the reader wrote first is taken over, never doubled.** The
/// catalogue reaching a name they had already written is one subject under two
/// spellings, which is what folding exists to prevent : the section wins, under
/// the catalogue's own spelling and mark, and it keeps the stories filed under
/// it and what the reader said about it.
///
/// **Stored in the reader's language, like everything else the model writes.**
/// A subject is a string in the store, and the model is shown strings and
/// answers with them ; a key resolved at each draw would have to be resolved
/// for the model too, which would mean translating what it answers back. The
/// cost is that a reader who changes language keeps the names they had.
nonisolated enum StandardTopics {
    /// One section : what it is called, the mark it wears, and what kind of
    /// news it is.
    ///
    /// **The three together and never three lists.** A name in one array and a
    /// glyph at the same index in another is two places to forget one, and the
    /// day somebody inserts a section into the middle of the first the whole of
    /// the second is one out and nobody notices : every page is still drawn,
    /// with `Cinéma` wearing a tractor and printed in the green of the fields.
    nonisolated struct Section: Sendable {
        let name: LocalizedStringResource
        let symbol: String
        /// What kind of news it is, which is what decides its colour. See
        /// ``TopicFamily``.
        let family: TopicFamily

        init(_ name: LocalizedStringResource, _ symbol: String, _ family: TopicFamily) {
            self.name = name
            self.symbol = symbol
            self.family = family
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
        Section("Politics", "building.columns", .publicLife),
        Section("International", "globe", .publicLife),
        Section("European Union", "flag", .publicLife),
        Section("Elections", "list.bullet.rectangle", .publicLife),
        Section("Defence", "shield", .publicLife),
        Section("Justice", "book.closed", .publicLife),
        Section("Immigration", "figure.walk", .publicLife),
        Section("Human rights", "hand.raised", .publicLife),
        Section("Local news", "mappin.and.ellipse", .publicLife),

        // Money and work
        Section("Economy", "chart.line.uptrend.xyaxis", .money),
        Section("Business", "briefcase", .money),
        Section("Employment", "hammer", .money),
        Section("Finance", "banknote", .money),
        Section("Consumer", "cart", .money),
        Section("Housing", "house", .money),
        Section("Agriculture", "leaf", .land),
        Section("Industry", "gearshape.2", .money),
        Section("Energy", "bolt", .money),
        Section("Transport", "tram", .money),

        // Living
        Section("Education", "graduationcap", .everyday),
        Section("Health", "heart", .body),
        Section("Food", "fork.knife", .everyday),
        Section("Religion", "hands.sparkles", .everyday),
        Section("Crime", "exclamationmark.triangle", .body),
        Section("Environment", "tree", .land),
        Section("Ecology", "arrow.3.trianglepath", .land),
        Section("Climate", "thermometer", .land),
        Section("Weather", "cloud.sun", .land),

        // Science and technology
        Section("Science", "atom", .science),
        Section("Technology", "cpu", .science),
        Section("Artificial intelligence", "brain", .science),
        Section("Software", "chevron.left.forwardslash.chevron.right", .science),
        Section("Cybersecurity", "lock.shield", .science),
        Section("Privacy", "eye.slash", .science),
        Section("Social media", "bubble.left.and.bubble.right", .science),
        Section("Telecoms", "antenna.radiowaves.left.and.right", .science),
        Section("Space", "moon.stars", .science),
        Section("Travel", "airplane", .everyday),

        // Culture
        Section("Media", "newspaper", .culture),
        Section("Cinema", "film", .culture),
        Section("TV series", "tv", .culture),
        Section("Music", "music.note", .culture),
        Section("Books", "books.vertical", .culture),
        Section("Art", "paintpalette", .culture),
        Section("Photography", "camera", .culture),
        Section("Architecture", "building.2", .culture),
        Section("Fashion", "tshirt", .culture),
        Section("Video games", "gamecontroller", .culture),
        Section("History", "hourglass", .culture),

        // Sport, and the two that sort nothing
        Section("Sport", "figure.run", .everyday),
        Section("Society", "person.3", .plain),
        Section("Culture", "theatermasks", .plain),
    ]

    /// What kind of news each mark stands for, and therefore what colour it
    /// is printed in.
    ///
    /// **Keyed by the mark and not by the name.** A subject is stored as a
    /// string in the reader's own language, so one store carries
    /// `Environnement` where another carries `Environment` ; the mark is the
    /// same string in every store and in every language. It also answers for a
    /// subject the reader wrote themselves, since what they pick from is this
    /// catalogue's own marks : a subject wearing a leaf is green without
    /// anybody having decided it.
    static let families: [String: TopicFamily] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.symbol, $0.family) }
    )

    /// The family a subject wearing this mark belongs to.
    ///
    /// The tag everything falls back to belongs to none, and neither does a
    /// mark from no catalogue at all : both are printed in the plain colour,
    /// which is what the two sections that sort nothing wear.
    static func family(of symbol: String) -> TopicFamily {
        families[symbol] ?? .plain
    }

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
    /// Empty, and the mechanism kept for the next one.
    ///
    /// `Écologie` is what filled it and what emptied it again. It was moved
    /// onto `Environment`, on the grounds that in French it names the political
    /// movement first ; it is a section of its own now, beside `Environnement`
    /// and `Climat`, so a renaming would take a reader's ecology backlog off
    /// the section that holds it a moment before the catalogue puts that
    /// section back.
    static let renamed: [(was: LocalizedStringResource, now: LocalizedStringResource)] = []

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
