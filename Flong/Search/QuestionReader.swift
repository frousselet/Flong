//
//  QuestionReader.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import FoundationModels
import OSLog

/// Whether the reader asked about articles they have or have not read.
@Generable
nonisolated enum QuestionState: Hashable, Sendable {
    /// The sentence says nothing about it, which is the usual answer.
    case any
    case unread
    case read
    case starred
    /// Filed in a collection.
    case kept
    /// Written on.
    case annotated
    /// Carrying a picture, a sound or a film.
    case withMedia
}

/// How far back the reader asked to look.
@Generable
nonisolated enum QuestionPeriod: Hashable, Sendable {
    /// The sentence names no moment, which is the usual answer.
    case any
    case today
    case thisWeek
    case thisMonth
    case thisYear
}

/// What a sentence typed into the search field turns out to be asking for.
///
/// **Five fields and no syntax.** The model is never asked to write a query :
/// it says what the sentence names, in pieces, and ``QuestionReader`` is what
/// turns those into a ``QueryNode``. A model that emitted `site:lemonde.fr` would
/// be a model writing the thing that compiles to SQL, and the whole point of
/// section 12 is that nothing but the parser and the compiler ever does that.
@Generable
nonisolated struct ReadQuestion: Hashable, Sendable {
    @Guide(
        description: """
            What to look for in the articles themselves : the subject, in the reader's own words. \
            Take out the name of any publication, any writer, any moment in time, and any word about \
            whether an article has been read. Empty when the sentence names no subject.
            """
    )
    var words: String

    @Guide(
        description: """
            The publication or website the sentence names, exactly as the reader wrote it and with no \
            article in front of it. Empty when the sentence names none. Never a subject, never a person.
            """
    )
    var source: String

    @Guide(
        description: """
            The writer the sentence names as the author of what is being looked for. Empty when the \
            sentence names none. Never somebody an article is merely about.
            """
    )
    var author: String

    @Guide(
        description: "Whether the sentence asks about read, unread, starred, kept, annotated articles, or says nothing."
    )
    var state: QuestionState

    @Guide(description: "The moment the sentence names, or nothing when it names none.")
    var period: QuestionPeriod
}

/// What the sentence was understood to mean, and what to say it meant.
///
/// Named for the reading rather than for the reader : ``Reading`` is already
/// the article somebody is in the middle of.
nonisolated struct QuestionReading: Hashable, Sendable {
    let query: QueryNode
    /// What was understood, said back to the reader in their own language.
    ///
    /// **A search that narrows itself has to say so.** A reader who typed a
    /// sentence and got half the articles they expected is a reader who thinks
    /// the search is broken ; one who is told the sentence was read as
    /// `Le Monde` and `this week` knows exactly what happened and can take a
    /// word out. It is empty when nothing but words was understood, which is
    /// when there is nothing to say.
    let understood: [String]
}

/// Reads a sentence in the search field, on the device.
///
/// **The grammar is not the interface.** `tag:`, `is:unread` and `after:` are
/// what a dynamic collection is described with, what the FreshRSS import
/// understands and what the compiler is given. A reader looking something up
/// types a sentence, and this is what turns one into the other.
///
/// Section 15 treats the model as a feature flag : the path without it is always
/// present and always tested. Without it a sentence is searched for as the words
/// it is made of, which is what every search field has always done and which is
/// a perfectly good answer.
///
/// **The model can only name things the reader has.** It answers with a
/// publication and a writer as the sentence spelled them, and those are matched
/// against the sources actually followed and the bylines actually held. A name
/// that matches nothing is put back into the words rather than narrowing
/// anything, so a model that invents a newspaper costs the reader nothing.
nonisolated struct QuestionReader: Sendable {
    /// What the reader follows, so a name they wrote can be matched to
    /// something that exists.
    nonisolated struct Vocabulary: Hashable, Sendable {
        /// The publishers, by the name they are shown under and the host they
        /// group.
        var sources: [Source] = []
        /// The feeds, by their titles.
        var feeds: [String] = []
        /// Every byline the feeds have carried.
        var authors: [String] = []

        nonisolated struct Source: Hashable, Sendable {
            let name: String
            let host: String
        }
    }

    /// The fewest words that are worth asking a model about.
    ///
    /// One or two words are a subject, not a sentence : `iran` means look for
    /// `iran`, and a round trip to a language model to be told so is a second
    /// of waiting bought for nothing.
    static let fewestWords = 3

    /// What is left for the answer.
    static let reservedTokens = 200

    let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    private var instructions: String {
        """
        You read one sentence somebody typed into the search field of their feed reader, and you say what it asks for.
        You never answer the question itself and you never add anything the sentence does not say.

        Split the sentence into what it is about, who published it, who wrote it, whether it was read, and when.
        Leave a field empty when the sentence does not say it. An empty field is the right answer far more often than a full one.
        Never invent a publication or a writer the sentence does not name.
        Never put a publication, a writer or a moment in time into the words.
        """
    }

    /// What one sentence asks for, or nothing when the model has nothing to add.
    func read(_ sentence: String, in vocabulary: Vocabulary, now: Date = Date()) async -> QuestionReading? {
        let sentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard OnDeviceModel.isAvailable else { return nil }
        guard sentence.split(separator: " ").count >= Self.fewestWords else { return nil }

        do {
            let session = LanguageModelSession(model: OnDeviceModel.model(), instructions: instructions)
            session.prewarm()

            let response = try await session.respond(
                to: "The sentence : \(sentence)",
                generating: ReadQuestion.self,
                options: OnDeviceModel.options(maximumTokens: Self.reservedTokens)
            )
            OnDeviceModel.succeeded()

            return Self.reading(of: response.content, said: sentence, in: vocabulary, now: now)
        } catch {
            OnDeviceModel.refused(error)
            Log.enrich.notice("A sentence could not be read : \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }

    // MARK: - A sentence, with no model to read it

    /// What a sentence asks for when nothing read it.
    ///
    /// **A sentence is mostly words that say nothing.** Words beside each other
    /// are joined by an implicit `AND`, which is right for `vision pro` and
    /// brittle for `les articles du Monde sur la rentrée scolaire` : it makes
    /// `les`, `du` and `sur` conditions an article has to satisfy, and it makes
    /// `articles` one too, which is the reader talking about their feed reader
    /// rather than about the news. So the words that say nothing go, and what
    /// is left is joined by `AND` : somebody who typed two subjects meant both.
    ///
    /// **And a paper is looked up rather than searched for.** `Monde` in that
    /// sentence is a publication the reader follows, and matching it against
    /// the sources they actually have is a lookup and not a model : it needs no
    /// Apple Intelligence, it is right or it matches nothing, and it turns a
    /// word that would have been demanded of the body into the source it names.
    /// That is most of what reading the sentence was for, and section 15 gets
    /// it whether or not there is a model on the device.
    ///
    /// Nothing is done to anything that is not a plain sentence. Two words are
    /// already right ; something carrying an operator, a bracket or a quotation
    /// is a query somebody wrote on purpose, and rewriting it would be
    /// answering a question they did not ask.
    static func plainly(_ sentence: String, in vocabulary: Vocabulary = Vocabulary()) -> QuestionReading? {
        let said = sentence.split(separator: " ").count
        guard said >= fewestWords, isPlain(sentence) else { return nil }

        let terms = Array(NSOrderedSet(array: TextSignatures.terms(of: sentence)).compactMap { $0 as? String })
            .filter { !scaffolding.contains($0) }
        guard !terms.isEmpty, terms.count < said else { return nil }

        var parts: [QueryNode] = []
        var understood: [String] = []

        for term in terms {
            guard term.count >= 4, let source = source(named: term, in: vocabulary) else {
                parts.append(.term(QueryTerm(field: .any, value: term)))
                continue
            }
            parts.append(source.term)
            understood.append(source.name)
        }

        guard !parts.isEmpty else { return nil }
        return QuestionReading(query: parts.count == 1 ? parts[0] : .and(parts), understood: understood)
    }

    /// The reader talking about their feed reader rather than about the news.
    ///
    /// `les articles du Monde` is four words and one subject. What is here is
    /// the handful of nouns somebody reaches for to say *the things I read*,
    /// and demanding any of them of an article's text is how a sentence with a
    /// perfectly good subject in it answers with one result.
    static let scaffolding: Set<String> = [
        "article", "articles", "papier", "papiers", "actu", "actus", "actualite", "actualites",
        "info", "infos", "sujet", "sujets", "truc", "trucs", "chose", "choses",
        "story", "stories", "news", "post", "posts", "piece", "pieces", "thing", "things", "stuff",
    ]

    /// Whether a sentence is words and nothing else.
    private static func isPlain(_ sentence: String) -> Bool {
        guard !sentence.contains(where: { ":()\"".contains($0) || $0 == "\u{201C}" || $0 == "\u{201D}" }) else {
            return false
        }

        return !sentence.split(separator: " ").contains { word in
            word.hasPrefix("-") || word.hasPrefix("!") || ["AND", "OR", "NOT"].contains(String(word))
        }
    }

    // MARK: - From what was said to what is searched for

    /// Turns what the model heard into a query, and into the line that says so.
    ///
    /// - Parameter said: the sentence as it was actually typed. Every word the
    ///   model hands back has to be in it : that is the whole guard against a
    ///   model helpfully adding a word nobody asked for, and it costs a set.
    static func reading(
        of question: ReadQuestion,
        said sentence: String,
        in vocabulary: Vocabulary,
        now: Date = Date()
    ) -> QuestionReading? {
        var parts: [QueryNode] = []
        var understood: [String] = []
        var words = typed(question.words, in: sentence)

        // A name that matches nothing the reader follows narrows nothing. It
        // goes back into the words, where it is at worst a word they typed.
        if let source = typed(question.source, in: sentence).isEmpty
            ? nil : source(named: question.source, in: vocabulary)
        {
            parts.append(source.term)
            understood.append(source.name)
        } else {
            words += " " + typed(question.source, in: sentence)
        }

        if let author = author(named: question.author, in: vocabulary, said: sentence) {
            parts.append(.term(QueryTerm(field: .author, value: author)))
            understood.append(author)
        } else {
            words += " " + typed(question.author, in: sentence)
        }

        if let state = state(of: question.state) {
            parts.append(.state(state))
            understood.append(name(of: question.state))
        }

        if let seconds = seconds(of: question.period) {
            parts.append(.date(.youngerThan(seconds)))
            understood.append(name(of: question.period))
        }

        // Nothing was understood beyond the words, so there is nothing the
        // model can do that the parser has not already done.
        guard !parts.isEmpty else { return nil }

        let subject = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = plainly(subject, in: vocabulary)?.query ?? QueryParser.parse(subject, now: now)
        if text != QueryNode.all { parts.insert(text, at: 0) }

        return QuestionReading(query: parts.count == 1 ? parts[0] : .and(parts), understood: understood)
    }

    /// The words of an answer that the reader actually typed.
    ///
    /// **A model is entitled to be helpful and must not be here.** A sentence
    /// about Iran comes back with `Iran conflict` about as often as not, and
    /// the added word narrows a search the reader never narrowed. Word by word,
    /// folded, so that `l'Iran` still yields `Iran`.
    static func typed(_ answer: String, in sentence: String) -> String {
        let said = Set(TextSignatures.terms(of: sentence))

        return
            answer
            .split(separator: " ")
            .filter { word in
                let terms = TextSignatures.terms(of: String(word))
                return !terms.isEmpty && terms.allSatisfy(said.contains)
            }
            .joined(separator: " ")
    }

    /// The publication a name stands for, when the reader follows one.
    static func source(named name: String, in vocabulary: Vocabulary) -> (term: QueryNode, name: String)? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        if let source = vocabulary.sources.first(where: { matches(name, $0.name) || matches(name, $0.host) }) {
            return (.term(QueryTerm(field: .site, value: source.host)), source.name)
        }
        if let feed = vocabulary.feeds.first(where: { matches(name, $0) }) {
            return (.term(QueryTerm(field: .feed, value: feed)), feed)
        }
        return nil
    }

    private static func author(named name: String, in vocabulary: Vocabulary, said sentence: String) -> String? {
        guard !typed(name, in: sentence).isEmpty else { return nil }
        return vocabulary.authors.first { matches(name, $0) }
    }

    /// Whether a name the reader wrote and a name the store holds are the same
    /// one.
    ///
    /// Either way round, since a reader writes `Monde` for `Le Monde` and
    /// `lemonde.fr` for the same thing. Three characters at least : shorter
    /// than that a containment match is an accident.
    static func matches(_ written: String, _ held: String) -> Bool {
        let written = folded(written)
        let held = folded(held)
        guard written.count >= 3, held.count >= 3 else { return written == held }

        return written == held || held.contains(written) || written.contains(held)
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - The pieces, in the reader's own terms

    private static func state(of state: QuestionState) -> QueryState? {
        switch state {
        case .any: nil
        case .unread: .unread
        case .read: .read
        case .starred: .starred
        case .kept: .collected
        case .annotated: .annotated
        case .withMedia: .media
        }
    }

    /// How far back a period reaches.
    ///
    /// **Counted back from now rather than from the top of the calendar.** A
    /// reader who says `this week` on a Monday morning means the last few days
    /// and not the eight hours since midnight on Sunday, and a search that
    /// answered the calendar would answer almost nothing.
    private static func seconds(of period: QuestionPeriod) -> TimeInterval? {
        switch period {
        case .any: nil
        case .today: 24 * 3600
        case .thisWeek: 7 * 24 * 3600
        case .thisMonth: 31 * 24 * 3600
        case .thisYear: 365 * 24 * 3600
        }
    }

    private static func name(of state: QuestionState) -> String {
        switch state {
        case .any: ""
        case .unread: String(localized: "Unread", comment: "One thing a typed sentence was understood to ask for.")
        case .read: String(localized: "Read", comment: "One thing a typed sentence was understood to ask for.")
        case .starred: String(localized: "Starred", comment: "One thing a typed sentence was understood to ask for.")
        case .kept: String(localized: "Kept", comment: "One thing a typed sentence was understood to ask for.")
        case .annotated:
            String(localized: "Written on", comment: "One thing a typed sentence was understood to ask for.")
        case .withMedia:
            String(localized: "With a picture", comment: "One thing a typed sentence was understood to ask for.")
        }
    }

    private static func name(of period: QuestionPeriod) -> String {
        switch period {
        case .any: ""
        case .today: String(localized: "Today", comment: "A moment a typed sentence was understood to name.")
        case .thisWeek: String(localized: "This week", comment: "A moment a typed sentence was understood to name.")
        case .thisMonth: String(localized: "This month", comment: "A moment a typed sentence was understood to name.")
        case .thisYear: String(localized: "This year", comment: "A moment a typed sentence was understood to name.")
        }
    }
}
