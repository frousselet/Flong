//
//  Newsmaker.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import NaturalLanguage

/// Somebody an article is about.
///
/// **The other kind of person in a feed reader.** An ``Author`` is who wrote
/// the piece, and a feed hands that over in a field. A newsmaker is who the
/// piece is about, and no feed hands that over at all : it is in the prose,
/// and it has to be read out of it. `Trump donne dix jours à l'Iran` names
/// somebody the reader may well follow across every paper that writes about
/// him, and until now nothing in the store could answer a question about him.
///
/// **A newsmaker is a name, exactly as an author is.** There is no row for a
/// person and there could not be one : what comes out of an article is a piece
/// of text, and `E. Macron`, `Emmanuel Macron` and `le président français` are
/// three of them that only a human eye can tell are one. So the name is the
/// identity, matched exactly, and Flong never guesses that two spellings are
/// one person. `docs/technical/authors.md` sets out why, and every word of it
/// applies here.
///
/// **The reading is deterministic and asks no model.** Section 15 of the
/// specification says the path without Apple Intelligence always exists and is
/// always tested, and this is that path and the only one : `NLTagger` names the
/// people, the rest is mechanical, and nothing here depends on what the device
/// can do. It has to be : the stored name is what a favourite is named after
/// between devices, and a rule that answered differently on two of them would
/// give one person two rows and a favourite that only half travels.
nonisolated struct Newsmaker: Identifiable, Hashable, Sendable {
    /// The name, as the article spells it, cleaned.
    var name: String

    /// How many of the articles this device holds name them.
    ///
    /// Articles and not mentions : a piece that says `Macron` eleven times is
    /// one article about him. Zero is a real answer, for the same reason it is
    /// one for a writer : a favourite that reached this device from another one
    /// names somebody no article here has mentioned yet.
    var count: Int

    /// Whether the reader singled them out.
    var isFavourite: Bool

    /// Whether the reader asked to be told when an article names them.
    ///
    /// Not the favourite above under another name. A favourite is somebody the
    /// reader wants gathered on a page of their own ; this is somebody worth
    /// being interrupted for, whoever writes about them.
    var notifies: Bool = false

    /// Where they are written about, by publisher, most often first.
    ///
    /// The domains and not the marks, exactly as ``Author/publishers`` holds
    /// them : a publisher's mark is drawn from what the reader is subscribed to
    /// now, through the one map the whole application looks it up in, so a page
    /// renaming a publisher renames it here too. See `SourceIdentity`.
    var publishers: [String] = []

    var id: String { name }

    /// One person an article names, and how often it names them.
    nonisolated struct Mention: Hashable, Sendable {
        var name: String
        /// How many times the article named them, which is what orders the
        /// people of one piece : the person a story is about is named
        /// throughout it, and the expert quoted in the eleventh paragraph is
        /// named once.
        var times: Int
    }

    // MARK: - Reading a person out of an article

    /// How much of an article is read.
    ///
    /// Forty thousand characters, which is a very long feature and several
    /// times the length of ordinary news. Past that a piece has said who it is
    /// about many times over, and the tagger is a model that costs time per
    /// character on a corpus of a hundred thousand articles.
    static let lengthRead = 40_000

    /// How many people one article may put in the directory.
    ///
    /// **A bound and not a judgement.** Almost nothing reaches it : an ordinary
    /// piece names a handful. What it stops is the one article a year that is a
    /// list of two hundred names, which would otherwise be two hundred rows in
    /// a directory nobody can then read.
    static let mostPerArticle = 40

    /// The longest a name may be, in words.
    ///
    /// Five. Past that the tagger has joined a run of names into one, which is
    /// a thing it does at the end of a sentence listing people, and no
    /// six-word span is somebody the reader is going to look up.
    static let longestName = 5

    /// Everybody one article names, most often named first.
    ///
    /// - Parameter title: the headline, which is where the person a piece is
    ///   about is named if they are named anywhere.
    /// - Parameter excerpt: the standfirst, when the feed served one.
    /// - Parameter text: the body with its markup stripped, which is what
    ///   `EntryBody` already holds for the full-text index.
    /// - Parameter language: what the article is written in, as ingestion
    ///   settled it. The tagger reads a headline far better when it is not
    ///   guessing the language from eight words.
    /// - Parameter signedBy: the byline. Whoever signed the piece is its
    ///   author and not somebody it is about, and plenty of publishers print
    ///   the byline again at the foot of the prose : left in, the two
    ///   directories would say the same thing about the same person, and the
    ///   writers would drown the people.
    static func people(
        inTitle title: String,
        excerpt: String? = nil,
        text: String? = nil,
        language: String? = nil,
        signedBy byline: String? = nil
    ) -> [Mention] {
        // The three pieces stand apart rather than running together : a
        // headline has no full stop, and a standfirst joined straight onto it
        // would give the tagger one sentence that is really two.
        let read =
            [title, excerpt, text]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !read.isEmpty else { return [] }

        let tallied = tally(of: named(in: String(read.prefix(lengthRead)), language: language))
        let writers = Set(Author.people(in: byline).map(key))

        return
            folded(tallied)
            .filter { !writers.contains(key($0.name)) }
            .prefix(mostPerArticle)
            .map { $0 }
    }

    /// The order a reader expects names in.
    ///
    /// Not the order SQLite puts them in : `ORDER BY` is byte order, where
    /// `Zola` comes before `Éluard` because a capital E with an acute accent
    /// starts with a higher byte than a Z.
    static func before(_ first: Newsmaker, _ second: Newsmaker) -> Bool {
        first.name.localizedStandardCompare(second.name) == .orderedAscending
    }

    // MARK: - What the tagger says, and what is kept of it

    /// Every span the tagger calls a person, in the order they are written.
    ///
    /// **People and nobody else.** `NLTagger` names places and organizations
    /// too, and `SearchSubjects` wants all three because a subject to search
    /// for is as often a country as a person. This is a directory of people, so
    /// a country in it would be a row nobody can follow.
    private static func named(in text: String, language: String?) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        // What ingestion settled, believed. `LanguageDetection` has already
        // reduced `fr-FR` to `fr`, which is what `NLLanguage` is spelled in.
        if let language, !language.isEmpty {
            tagger.setLanguage(NLLanguage(language), range: text.startIndex..<text.endIndex)
        }

        var found: [String] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            // `joinNames` is what makes `Donald Trump` one span rather than two
            // words the tagger happened to tag in a row.
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            guard tag == .personalName else { return true }
            found += names(inSpan: String(text[range]))
            return true
        }
        return found
    }

    /// The names inside one span, which is very often more than the span says.
    ///
    /// **`joinNames` joins too much, and it does it in a way a rule can see.**
    /// Asked for one span per name it hands back `Eric Zemmour déborde Sarah
    /// Knafo` and `Céline Dion chante`, which are two people with a verb
    /// between them and one person with a verb after her. Kept whole, the first
    /// is a third person who exists nowhere and neither of the two real ones is
    /// findable : exactly what an unsplit byline does to a newsroom, and cured
    /// the same way.
    ///
    /// **A lower-case word is the cut, and it is never anything else.** In a
    /// script that has capitals, every word of a name has one. The exceptions
    /// are the particles, which are a closed list a language changes about once
    /// a century : `de`, `van`, `von`, `der`, `bin`. So the span is cut at every
    /// other lower-case word, and `Dominique de Villepin` and `Mathieu van der
    /// Poel` come through whole while the verbs are cut out.
    ///
    /// A script with no capitals at all has no lower-case words either, by this
    /// test, so a name in Chinese, Japanese or Arabic is one run and comes
    /// through as it was written.
    ///
    /// Not private, so that the rules can be tested on the spans that actually
    /// come out of the tagger rather than through prose contrived to make it
    /// produce one : which sentence it over-joins is its answer and changes
    /// with the operating system, and a test resting on that would fail on an
    /// update for a reason that has nothing to do with these rules.
    static func names(inSpan span: String) -> [String] {
        let words = collapsed(HTMLEntities.decode(span)).split(separator: " ").map(String.init)

        var runs: [[String]] = [[]]
        for word in withoutAcronym(words) {
            if isACut(word) {
                runs.append([])
            } else {
                runs[runs.count - 1].append(word)
            }
        }

        return runs.compactMap { run in
            // A particle left hanging at the end of a run is the start of a
            // name the cut took away, and not part of the one before it.
            var run = run
            while let last = run.last, particles.contains(folded(last)) { run.removeLast() }
            return cleaned(run.joined(separator: " "))
        }
    }

    /// Whether a word cuts the span it is in rather than belonging to it.
    private static func isACut(_ word: String) -> Bool {
        guard word.contains(where: \.isLowercase), !word.contains(where: \.isUppercase) else { return false }
        return !particles.contains(folded(word))
    }

    /// The words that are lower case and are part of a name all the same.
    ///
    /// A closed list, which is why it can be one : these are the particles the
    /// European naming traditions carry, and no new one has appeared in a very
    /// long time.
    private static let particles: Set<String> = [
        "de", "du", "des", "da", "das", "do", "dos", "di", "del", "della", "degli", "den", "der", "ter",
        "van", "von", "af", "av", "zu", "la", "le", "les", "el", "al", "bin", "ben", "ibn", "y", "e", "of",
    ]

    /// The span without the acronym a newsroom staples to a name.
    ///
    /// `PDG Patrick Pouyanné`, `LFI Sébastien Delogu`, `NBA Patrick Beverley` :
    /// a party, a job or a league written in capitals in front of somebody, and
    /// the tagger takes the lot for a name. A word in capitals is never a first
    /// name, so it goes.
    ///
    /// **Only where two words are left after it**, which is what keeps a real
    /// name out of it : `JR Smith` leaves one word and is not touched, while
    /// `NBA Patrick Beverley` leaves two and is.
    private static func withoutAcronym(_ words: [String]) -> [String] {
        guard words.count >= 3, let first = words.first, first.count >= 2,
            first.contains(where: \.isLetter), !first.contains(where: \.isLowercase)
        else { return words }

        return Array(words.dropFirst())
    }

    /// The spelling to keep of one run of words, or nothing where it names
    /// nobody.
    ///
    /// **What is cleaned is the spelling, never the person**, which is the rule
    /// the bylines already follow. Every one of these is mechanical, and none
    /// of them decides that two names are one.
    private static func cleaned(_ span: String) -> String? {
        var name = withoutElision(span)
        name = name.trimmingCharacters(in: Self.edges)

        // A name has a letter in it. What this refuses is the stray span the
        // tagger occasionally hands back with nothing but punctuation in it.
        guard name.contains(where: \.isLetter) else { return nil }
        // One letter is an initial, and an initial on its own is nobody.
        guard name.count > 1 else { return nil }
        // A digit is never part of a person's name, and a span holding one is
        // the tagger having taken a law or a squad number for somebody.
        guard !name.contains(where: \.isNumber) else { return nil }
        guard name.split(whereSeparator: \.isWhitespace).count <= longestName else { return nil }

        // **A capital where the script has them.** A common noun the tagger
        // mistook for a name is written in lower case, and dropping it costs
        // nothing. The test is for the absence of a capital rather than for the
        // presence of one, so a name in a script that has no case at all -
        // Chinese, Japanese, Arabic - is kept rather than refused for lacking
        // something its writing system does not have.
        if name.contains(where: \.isLowercase) && !name.contains(where: \.isUppercase) { return nil }

        // **One word in capitals is an acronym.** `AI`, `CEO`, `COO`, `PIR`,
        // `SREN` : a technology, two jobs, a party and a French statute, every
        // one of them handed over by the tagger as somebody's name. A word set
        // entirely in capitals is a name nobody writes.
        //
        // It costs the person known only by their initials, and a surname a
        // publisher set in capitals on its own. Measured over a real stream,
        // every single one of these was noise and none of them was a person,
        // which is the trade taken.
        if !name.contains(" ") && !name.contains(where: \.isLowercase) { return nil }

        return name
    }

    /// The punctuation a span may be left wearing.
    private static let edges = CharacterSet(charactersIn: " .,;:!?·-–«»\"'’“”()[]")

    /// One line, whatever the prose's line breaks made of it.
    private static func collapsed(_ line: String) -> String {
        line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The name without the article French elides onto it.
    ///
    /// The same rule `SearchSubjects` applies, and for the same reason : `d'` in
    /// `d'Emmanuel Macron` is not part of the name and would be typed by
    /// nobody. What comes off has to be an article's length, so `aujourd'hui`
    /// keeps its own.
    private static func withoutElision(_ name: String) -> String {
        guard let apostrophe = name.firstIndex(where: { $0 == "'" || $0 == "\u{2019}" }) else { return name }

        let article = name[name.startIndex..<apostrophe]
        let rest = name[name.index(after: apostrophe)...]
        guard (1...2).contains(article.count), article.allSatisfy(\.isLetter), rest.first?.isLetter ?? false
        else { return name }

        return String(rest)
    }

    // MARK: - One person, however many times the article named them

    /// The spans counted, in the order they were first written.
    ///
    /// Matched exactly, since the identity is the name : `Macron` and `MACRON`
    /// are two spellings, and deciding they are one is a merge rather than a
    /// cleaning. The publisher who writes a name two ways in one piece is rare,
    /// and the reader has the search field.
    private static func tally(of names: [String]) -> [Mention] {
        var order: [String] = []
        var times: [String: Int] = [:]

        for name in names {
            if times[name] == nil { order.append(name) }
            times[name, default: 0] += 1
        }
        return order.map { Mention(name: $0, times: times[$0] ?? 0) }
    }

    /// A surname folded into the full name the same article gives it.
    ///
    /// **A paper names somebody in full once and by their surname after that.**
    /// Kept apart, `Donald Trump` and `Trump` are two rows in the directory, one
    /// of them holding the first paragraph of every article and the other
    /// holding the rest, and neither is the person. So a name whose words are
    /// all inside a longer name **in the same article** is that person, and its
    /// mentions are theirs.
    ///
    /// **Only where there is one candidate.** An article about `Marine Le Pen`
    /// and `Jean-Marie Le Pen` says `Le Pen` too, and there is no telling which
    /// of them it meant. Two candidates fold nothing : the short name keeps its
    /// own row, which is the honest answer and the one the rule for bylines
    /// already gives.
    ///
    /// **Within the article and never across the store.** A rule that looked at
    /// what other articles had named would answer differently on two devices,
    /// and differently on the same device a week later, which is the one thing
    /// a name a favourite is stored under may not do.
    private static func folded(_ found: [Mention]) -> [Mention] {
        let words = found.reduce(into: [String: Set<String>]()) { words, person in
            words[person.name] = Set(person.name.split(whereSeparator: \.isWhitespace).map { key(String($0)) })
        }

        // Who each name folds into, before anything is added up : a name may
        // fold into one that folds again, and adding the mentions as they were
        // found would leave the first person's on a row that is about to go.
        var into: [String: String] = [:]
        for person in found {
            guard let short = words[person.name] else { continue }

            let longer = found.filter { other in
                guard other.name != person.name, let full = words[other.name], full.count > short.count
                else { return false }
                return short.isSubset(of: full)
            }
            // Nobody to fold into, or more than one and no way to tell which.
            guard longer.count == 1, let full = longer.first else { continue }
            into[person.name] = full.name
        }

        var times: [String: Int] = [:]
        for person in found {
            times[fullest(of: person.name, following: into), default: 0] += person.times
        }

        return
            found
            .filter { into[$0.name] == nil }
            .map { Mention(name: $0.name, times: times[$0.name] ?? $0.times) }
            // Most named first, and the order they were written where two are
            // named as often : the person a piece is about is named throughout
            // it, and a directory row shows the first of them.
            .enumerated()
            .sorted { first, second in
                first.element.times == second.element.times
                    ? first.offset < second.offset : first.element.times > second.element.times
            }
            .map(\.element)
    }

    /// The end of a chain of folds : the fullest name this one turned out to be.
    ///
    /// Bounded by the number of names there are, so a pair that somehow pointed
    /// at each other stops rather than spinning. It cannot happen - a fold only
    /// ever goes from fewer words to more - and a walk over untrusted prose is
    /// not the place to rely on that.
    private static func fullest(of name: String, following into: [String: String]) -> String {
        var name = name
        var steps = 0

        while let next = into[name], steps < longestName {
            name = next
            steps += 1
        }
        return name
    }

    /// One spelling reduced to what two spellings have in common, for the fold
    /// above, for matching a byline and for the particles. Never stored : what
    /// is stored is what the article wrote.
    private static func key(_ text: String) -> String { folded(text) }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
    }
}
