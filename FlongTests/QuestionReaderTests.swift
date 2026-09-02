//
//  QuestionReaderTests.swift
//  FlongTests
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

/// Reading a sentence, without the model that reads it.
///
/// The model's own answer is not what is worth testing : it is entitled to hear
/// whatever it hears. What is worth testing is everything done to that answer
/// afterwards, which is where a search either narrows correctly or quietly
/// stops finding things.
@Suite("A sentence in the search field")
struct QuestionReaderTests {
    private let vocabulary = QuestionReader.Vocabulary(
        sources: [
            .init(name: "Le Monde", host: "lemonde.fr"),
            .init(name: "Le Fil sécurité", host: "fil.example.com"),
        ],
        feeds: ["Le Monde - International", "Journal du code"],
        authors: ["Camille Ferrand", "Ana Silva"]
    )

    // MARK: - With no model at all

    @Test("A sentence keeps the words that say something")
    func aSentenceWithNoModel() throws {
        let reading = try #require(
            QuestionReader.plainly("les articles du Fil sur l'Iran cette semaine", in: vocabulary)
        )

        guard case .and(let terms) = reading.query else {
            Issue.record("A sentence means all of what it says, not any of it")
            return
        }
        #expect(terms.contains(.term(QueryTerm(field: .any, value: "iran"))))
        #expect(terms.contains(.term(QueryTerm(field: .any, value: "semaine"))))
        // `les`, `du`, `sur` and `cette` are in every article ever written, and
        // an article that happens not to say one of them is not a miss.
        #expect(!terms.contains(.term(QueryTerm(field: .any, value: "les"))))
        #expect(!terms.contains(.term(QueryTerm(field: .any, value: "sur"))))
        // `articles` is the reader talking about their feed reader.
        #expect(!terms.contains(.term(QueryTerm(field: .any, value: "articles"))))
        // `Fil` is three letters, which is too short to be taken for a
        // publication : the index answers the whole of what is left, so the
        // results are ranked.
        #expect(reading.query.isIndexed)
        #expect(reading.understood.isEmpty)
    }

    @Test("A paper the reader follows is looked up, with no model at all")
    func aSourceWithNoModel() throws {
        let reading = try #require(QuestionReader.plainly("les articles du Monde sur l'Iran", in: vocabulary))

        guard case .and(let terms) = reading.query else {
            Issue.record("The paper and the subject have to hold at once")
            return
        }
        // The word became the publication it names rather than a word every
        // article about the world happens to contain.
        #expect(terms.contains(.term(QueryTerm(field: .site, value: "lemonde.fr"))))
        #expect(terms.contains(.term(QueryTerm(field: .any, value: "iran"))))
        #expect(!terms.contains(.term(QueryTerm(field: .any, value: "monde"))))
        // And the reader is told, since a search that narrows itself has to say so.
        #expect(reading.understood == ["Le Monde"])
    }

    @Test("A sentence with nothing to drop is left to the grammar")
    func nothingToDrop() {
        // Three words that all say something are already the query the implicit
        // AND would have built, and rebuilding it here would be a second answer
        // to one question.
        #expect(QuestionReader.plainly("vision pro apple") == nil)
    }

    @Test("Two words are already right and are left alone")
    func twoWords() {
        #expect(QuestionReader.plainly("vision pro") == nil)
        #expect(QuestionReader.plainly("iran") == nil)
    }

    @Test("A query somebody wrote on purpose is never rewritten")
    func writtenOnPurpose() {
        #expect(QuestionReader.plainly("title:iran is:unread after:2026-01") == nil)
        #expect(QuestionReader.plainly("\"vision pro\" et le reste") == nil)
        #expect(QuestionReader.plainly("iran -sport quelque chose") == nil)
        #expect(QuestionReader.plainly("iran OR irak ou autre") == nil)
    }

    // MARK: - What the model heard

    @Test("A sentence naming a paper and a week narrows to both, and says so")
    func aFullReading() throws {
        let question = ReadQuestion(
            words: "Iran",
            source: "Monde",
            author: "",
            state: .unread,
            period: .thisWeek
        )
        let reading = try #require(
            QuestionReader.reading(
                of: question,
                said: "les articles non lus du Monde sur l'Iran cette semaine",
                in: vocabulary
            )
        )

        guard case .and(let parts) = reading.query else {
            Issue.record("Everything the sentence named has to hold at once")
            return
        }
        // The publisher, by the host it groups, and never by the name the
        // reader happened to spell.
        #expect(parts.contains(.term(QueryTerm(field: .site, value: "lemonde.fr"))))
        #expect(parts.contains(.state(.unread)))
        #expect(parts.contains(.date(.youngerThan(7 * 24 * 3600))))
        // And the reader is told, in their own language, what it was read as :
        // the publisher under the name they see it under, and the rest through
        // the catalog, so the line is French for a French reader.
        #expect(reading.understood == ["Le Monde", String(localized: "Unread"), String(localized: "This week")])
    }

    @Test("A sentence the model found nothing in is left to the words")
    func nothingUnderstood() {
        let question = ReadQuestion(words: "Iran", source: "", author: "", state: .any, period: .any)

        // Nothing but words, which is what the parser and the plain reading
        // already do : a reading here would be a second answer to one question.
        #expect(QuestionReader.reading(of: question, said: "des nouvelles de l'Iran", in: vocabulary) == nil)
    }

    // MARK: - What the model made up

    @Test("A publication the reader does not follow narrows nothing")
    func anInventedPublication() {
        let question = ReadQuestion(words: "Iran", source: "Le Figaro", author: "", state: .unread, period: .any)
        let reading = QuestionReader.reading(of: question, said: "les articles non lus sur l'Iran", in: vocabulary)

        // The name was never typed, so it goes nowhere near the query.
        #expect(reading?.understood == [String(localized: "Unread")])
        #expect(reading?.query == .and([.term(QueryTerm(field: .any, value: "Iran")), .state(.unread)]))
    }

    @Test("A writer nobody has ever published narrows nothing")
    func anInventedWriter() {
        let question = ReadQuestion(words: "Iran", source: "", author: "Jean Dupont", state: .starred, period: .any)
        let reading = QuestionReader.reading(
            of: question, said: "les favoris sur l'Iran de Jean Dupont", in: vocabulary)

        // Typed, but signed nothing this device holds : it is a word, not a
        // byline, and it is searched for as one.
        #expect(reading?.understood == [String(localized: "Starred")])
    }

    @Test("A writer the feeds have carried is matched to their byline")
    func aKnownWriter() throws {
        let question = ReadQuestion(words: "", source: "", author: "Camille Ferrand", state: .any, period: .today)
        let reading = try #require(
            QuestionReader.reading(of: question, said: "ce que Camille Ferrand a écrit aujourd'hui", in: vocabulary)
        )

        #expect(reading.understood == ["Camille Ferrand", String(localized: "Today")])
    }

    @Test("A word the reader never typed is not searched for")
    func addedWords() {
        // A model is entitled to be helpful, and a word it adds narrows a
        // search the reader never narrowed.
        #expect(QuestionReader.typed("Iran conflict", in: "des nouvelles de l'Iran") == "Iran")
        #expect(QuestionReader.typed("Iran", in: "des nouvelles de l'Iran") == "Iran")
        #expect(QuestionReader.typed("", in: "des nouvelles") == "")
    }

    @Test("A name is matched however the reader spelled it")
    func names() {
        #expect(QuestionReader.matches("Monde", "Le Monde"))
        #expect(QuestionReader.matches("lemonde.fr", "Le Monde") == false)
        #expect(QuestionReader.matches("MONDE", "le monde"))
        #expect(QuestionReader.matches("sécurité", "Le Fil securite"))
        // Two characters match nothing but themselves : shorter than that a
        // containment match is an accident.
        #expect(QuestionReader.matches("le", "Le Monde") == false)
    }
}
