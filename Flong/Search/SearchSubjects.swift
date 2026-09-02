//
//  SearchSubjects.swift
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

/// What is worth searching for right now, taken from what is happening.
///
/// **A suggestion is a subject, not a syntax.** A search field that offers
/// `is:unread` and `tag:` is teaching its own grammar to somebody who came to
/// look something up. What is worth offering is what the feeds are full of this
/// morning : `iPhone 18 Pro`, `Trump Iran`, `Budget 2027`. The digest already
/// knows what that is, since grouping the reprints of one story is the whole of
/// what it does, and a story's headline is a sentence written about one thing.
///
/// **No model.** Section 15 says the path without Apple Intelligence always
/// exists and is always tested, and a suggestion that appeared on one device
/// and not on another would be worse than none. `NLTagger` names the people,
/// the places and the newsrooms ; the rest is what capitals and digits say
/// about a word, which is language-independent and costs a pass over a
/// headline.
nonisolated enum SearchSubjects {
    /// How many subjects are offered at once.
    ///
    /// Three, which is what fits above a keyboard without the stack becoming a
    /// list, and what Photos offers in the same place.
    static let limit = 3

    /// How many are worked out, of which ``limit`` are shown.
    ///
    /// **More than are shown, because taking one takes it away.** A subject the
    /// reader searches for joins the searches above it and stops being offered,
    /// and a page that had worked out exactly three would answer that by
    /// showing two. What is kept is a queue : the fourth steps into the place
    /// the first left.
    static let pool = 12

    /// The longest a subject may be.
    ///
    /// Three words. Past that it stops being a subject and becomes the
    /// headline it came from, and a headline pasted into a search field
    /// matches the one article it was written about.
    static let maximumWords = 3

    /// The subjects worth offering, from the headlines of what is happening.
    ///
    /// - Parameter headlines: the stories on the page, what is moving first.
    /// - Parameter excluding: what not to offer, which is what the reader has
    ///   already searched for : a suggestion the page is showing two rows above
    ///   is a suggestion that wastes its line.
    static func subjects(in headlines: [String], excluding: [String] = [], limit: Int = pool) -> [String] {
        var taken: Set<String> = Set(excluding.map(key))
        var subjects: [String] = []

        for headline in headlines {
            guard subjects.count < limit else { break }
            guard let subject = subject(of: headline) else { continue }

            let key = key(subject)
            guard !taken.contains(key) else { continue }
            // A subject one already taken says in full is the same subject :
            // `Trump` under `Trump Iran` adds a row and no information.
            guard !taken.contains(where: { $0.contains(key) || key.contains($0) }) else { continue }

            taken.insert(key)
            subjects.append(subject)
        }

        return subjects
    }

    /// The three to show, of everything that was worked out.
    ///
    /// **Three, always three.** A subject the reader searches for joins the
    /// searches above it and stops being worth offering ; a page that showed
    /// whatever was left would answer a tap by having one fewer thing to say.
    /// The queue is what makes the fourth step into the place the first left.
    ///
    /// - Parameter typed: what is in the field, which narrows the offer to the
    ///   subjects the reader is heading towards. Empty offers the head of the
    ///   queue.
    static func offered(
        from queue: [String],
        excluding searched: [String] = [],
        matching typed: String = "",
        limit: Int = limit
    ) -> [String] {
        let searched = Set(searched.map { $0.localizedLowercase })
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)

        return
            queue
            .filter { subject in
                guard !searched.contains(subject.localizedLowercase) else { return false }
                guard !typed.isEmpty else { return true }
                return subject.localizedCaseInsensitiveContains(typed)
                    && subject.localizedCaseInsensitiveCompare(typed) != .orderedSame
            }
            .prefix(limit)
            .map { $0 }
    }

    /// What one headline is about, in at most ``maximumWords`` words.
    ///
    /// **The longest run of distinctive words wins**, and where that run is a
    /// single word the next one joins it. `Apple présente l'iPhone 18 Pro` is
    /// about the iPhone 18 Pro and not about Apple ; `Trump donne dix jours à
    /// l'Iran` is about neither of its two names on its own and about both
    /// together. Where the longest run already says several words, adding
    /// another is how `Budget 2027` becomes `Budget 2027 Assemblée`.
    static func subject(of headline: String) -> String? {
        let runs = self.runs(in: headline)
        guard var longest = runs.first else { return nil }
        // The earliest of the longest, which `max(by:)` does not promise : a
        // headline naming two things says the one it is about first.
        for run in runs.dropFirst() where run.words.count > longest.words.count { longest = run }

        var words = longest.words
        if words.count == 1, let next = runs.first(where: { $0.start != longest.start }) {
            // In the order the headline says them, whichever of the two came
            // first : a subject read back to front is a subject nobody typed.
            words = longest.start < next.start ? words + next.words : next.words + words
        }

        let subject = words.prefix(maximumWords).joined(separator: " ")
        return isWorthOffering(subject) ? presented(subject) : nil
    }

    /// A subject has to be worth the row it takes.
    ///
    /// One short word is a fragment rather than a subject : `Pro` says nothing
    /// anybody would have typed on purpose.
    private static func isWorthOffering(_ subject: String) -> Bool {
        let words = subject.split(separator: " ")
        return words.count > 1 ? true : (words.first?.count ?? 0) >= 4
    }

    /// The subject as the pill shows it.
    ///
    /// A first word that is entirely lowercase is raised, since `budget 2027`
    /// on a pill reads as a fragment of a sentence. A word carrying a capital
    /// of its own is left exactly as it was written : `iPhone` is not `IPhone`,
    /// and correcting somebody else's product name is not this function's job.
    private static func presented(_ subject: String) -> String {
        guard let first = subject.first, first.isLowercase,
            !subject.prefix(while: { $0 != " " }).contains(where: { $0.isUppercase })
        else { return subject }

        return first.uppercased() + subject.dropFirst()
    }

    // MARK: - Reading a headline

    /// A stretch of distinctive words with nothing but spaces between them.
    struct Run: Hashable, Sendable {
        let words: [String]
        /// Where it starts in the headline, so two runs can be put back in the
        /// order they were written.
        let start: Int
    }

    /// The distinctive stretches of a headline.
    ///
    /// A word is distinctive when the tagger calls it somebody or somewhere, or
    /// when the way it is written says it names something : a capital where the
    /// sentence did not ask for one, a capital inside the word, a digit beside
    /// letters, a year. Everything else is the sentence around the subject.
    static func runs(in headline: String) -> [Run] {
        let words = tokens(of: headline)
        guard !words.isEmpty else { return [] }

        let names = namedRanges(in: headline)
        var runs: [Run] = []
        var current: [String] = []
        var start = 0

        for (index, token) in words.enumerated() {
            let word = stripped(token.text)
            let isNamed = names.contains { $0.overlaps(token.range) }
            // A run is broken by anything but spaces : two names either side of
            // a comma are two subjects, however close together they sit.
            let follows =
                !current.isEmpty && index > 0
                && headline[words[index - 1].range.upperBound..<token.range.lowerBound]
                    .allSatisfy { $0 == " " }

            // **A bare number carries on a run and never opens one.** `18` in
            // `iPhone 18 Pro` is part of the name ; the same `18` on its own is
            // a count of something in a sentence.
            if isBareNumber(word), !isYear(word) {
                if follows { current.append(word) } else if !current.isEmpty { close(&runs, &current, start) }
                continue
            }

            let isSalient = isNamed || isDistinctive(word)

            if isSalient, follows {
                current.append(word)
            } else if isSalient {
                if !current.isEmpty { close(&runs, &current, start) }
                current = [word]
                start = index
            } else if !current.isEmpty {
                close(&runs, &current, start)
            }
        }
        if !current.isEmpty { runs.append(Run(words: current, start: start)) }

        return runs.map(absorbingBareNumbers(in: words))
    }

    private static func close(_ runs: inout [Run], _ current: inout [String], _ start: Int) {
        runs.append(Run(words: current, start: start))
        current = []
    }

    /// A run that is nothing but a number takes the word in front of it.
    ///
    /// `2027` on its own is a year and not a subject. What makes it one is
    /// whatever it was the year of, which is the word immediately before it :
    /// `budget 2027`.
    private static func absorbingBareNumbers(in words: [Token]) -> (Run) -> Run {
        { run in
            guard run.words.allSatisfy({ $0.allSatisfy(\.isNumber) }), run.start > 0 else { return run }

            let previous = stripped(words[run.start - 1].text)
            guard previous.count >= 3, !isCommon(previous), previous.contains(where: \.isLetter)
            else { return run }

            return Run(words: [previous] + run.words, start: run.start - 1)
        }
    }

    /// Whether the way a word is written says it names something.
    ///
    /// **The capital counts wherever it falls, including at the opening.** A
    /// headline that opens on a name is the commonest headline there is, and a
    /// rule that discounted the first word because sentences start with a
    /// capital would throw away `Trump donne dix jours à l'Iran` entirely. What
    /// keeps `Le` and `Deux` out is that they are on the list of words that
    /// name nothing, which is where that argument belongs.
    private static func isDistinctive(_ word: String) -> Bool {
        guard word.count >= 2, !isCommon(word) else { return false }

        if isYear(word) { return true }
        guard word.contains(where: \.isLetter) else { return false }
        // A capital inside a word is nobody's sentence : `iPhone`, `macOS`.
        if word.dropFirst().contains(where: \.isUppercase) { return true }
        if word.contains(where: \.isNumber) { return true }

        return word.first?.isUppercase ?? false
    }

    private static func isYear(_ word: String) -> Bool {
        guard word.count == 4, isBareNumber(word), let year = Int(word) else { return false }
        return (1900...2100).contains(year)
    }

    private static func isBareNumber(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy(\.isNumber)
    }

    /// Whether a word names nothing, whatever case it is written in.
    ///
    /// The signature's own stop words, which are the ones every article uses,
    /// and beside them the determiners, the counts and the question words a
    /// headline opens on. They are on a list of their own rather than added to
    /// that one : the signature is what groups the reprints of a story, and a
    /// word taken out of it changes which articles land together.
    private static func isCommon(_ word: String) -> Bool {
        let folded = folded(word)
        return TextSignatures.stopWords.contains(folded) || openingWords.contains(folded)
    }

    /// What a headline opens on when it does not open on a name.
    ///
    /// Kept short deliberately, and for the reason ``TextSignatures.stopWords``
    /// gives : a long list is a long list to be wrong about. What is here is
    /// the determiners, the small counts and the question words, in the two
    /// languages the corpus is actually in.
    private static let openingWords: Set<String> = [
        "le", "la", "un", "une", "du", "de", "au", "ce", "cet", "ma", "mon", "ta", "ton", "nos", "vos",
        "il", "elle", "on", "je", "tu", "quand", "comment", "pourquoi", "quel", "quelle", "quels",
        "quelles", "selon", "vers", "depuis", "pendant", "contre", "toute", "toutes", "deja", "encore",
        "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf", "dix", "cent", "mille",
        "premier", "premiere", "dernier", "derniere", "grand", "grande", "petit", "petite",
        "a", "an", "in", "at", "how", "why", "what", "when", "where", "all", "more", "less", "my",
        "his", "her", "one", "two", "three", "four", "five", "six", "ten", "first", "last", "new",
    ]

    /// A word without the article stuck to the front of it.
    ///
    /// French elides, and the tokenizer hands back `l'Iran` and `l'iPhone` as
    /// single words. The article is not part of the name and would be typed by
    /// nobody : `l'` and `d'` come off, `aujourd'hui` does not, since what is
    /// taken off has to be an article's length.
    private static func stripped(_ word: String) -> String {
        guard let apostrophe = word.firstIndex(where: { $0 == "'" || $0 == "\u{2019}" }) else { return word }

        let article = word[word.startIndex..<apostrophe]
        let rest = word[word.index(after: apostrophe)...]
        guard (1...2).contains(article.count), article.allSatisfy(\.isLetter),
            rest.first?.isLetter ?? false
        else { return word }

        return String(rest)
    }

    // MARK: - The words themselves

    struct Token {
        let text: String
        let range: Range<String.Index>
    }

    private static func tokens(of headline: String) -> [Token] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = headline

        return tokenizer.tokens(for: headline.startIndex..<headline.endIndex).map {
            Token(text: String(headline[$0]), range: $0)
        }
    }

    /// Where the tagger says somebody, somewhere or some newsroom is named.
    private static func namedRanges(in headline: String) -> [Range<String.Index>] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = headline

        var ranges: [Range<String.Index>] = []
        tagger.enumerateTags(
            in: headline.startIndex..<headline.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            if let tag, [.personalName, .placeName, .organizationName].contains(tag) { ranges.append(range) }
            return true
        }
        return ranges
    }

    private static func key(_ subject: String) -> String { folded(subject) }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
    }
}
