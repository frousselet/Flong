//
//  SearchSubjectTests.swift
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

@Suite("What is worth searching for")
struct SearchSubjectTests {
    @Test("A headline gives up the thing it is about")
    func theSubjectOfAHeadline() {
        // The longest run of distinctive words wins : the story is about the
        // telephone and not about the company that makes it.
        #expect(SearchSubjects.subject(of: "Apple présente l'iPhone 18 Pro et l'iPhone Air 2") == "iPhone 18 Pro")

        // A bare year takes the word in front of it, and a first word written
        // entirely in lower case is raised for the pill.
        #expect(SearchSubjects.subject(of: "Le budget 2027 arrive devant l'Assemblée") == "Budget 2027")
    }

    @Test("Two names in one headline are one subject")
    func twoNames() {
        // Neither name says what the story is on its own, and a run of one word
        // is the one case where the next run joins it.
        let subject = SearchSubjects.subject(of: "Trump donne dix jours à l'Iran")
        #expect(subject == "Trump Iran")

        // In the order the headline says them, never the other way round.
        #expect(SearchSubjects.subject(of: "L'Iran répond à Trump") == "Iran Trump")
    }

    @Test("A headline that names nothing offers nothing")
    func nothingToOffer() {
        #expect(SearchSubjects.subject(of: "les prix continuent de monter") == nil)
        #expect(SearchSubjects.subject(of: "") == nil)
    }

    @Test("A fragment is not a subject")
    func fragments() {
        // One short word is not something anybody would have typed on purpose.
        #expect(SearchSubjects.subject(of: "un point sur le Pro") == nil)
        // Four characters is enough for a name to stand on its own.
        #expect(SearchSubjects.subject(of: "une journée à Lannion") == "Lannion")
    }

    @Test("A subject never runs past three words")
    func length() {
        let subject = SearchSubjects.subject(of: "Le Conseil Constitutionnel Français Rend Sa Décision")
        #expect((subject?.split(separator: " ").count ?? 0) <= SearchSubjects.maximumWords)
    }

    @Test("A run stops at anything that is not a space")
    func punctuationBreaksARun() {
        // Two names either side of a comma are two subjects, however close
        // together they sit : joining them would invent a name nobody wrote.
        let runs = SearchSubjects.runs(in: "à Caen, Rennes suit")
        #expect(runs.map(\.words) == [["Caen"], ["Rennes"]])
    }

    @Test("The page offers a few subjects, each said once")
    func theOffer() {
        let subjects = SearchSubjects.subjects(in: [
            "Apple présente l'iPhone 18 Pro",
            "Trump donne dix jours à l'Iran",
            "Le budget 2027 arrive devant l'Assemblée",
            "Les ventes de l'iPhone 18 Pro dépassent les prévisions",
            "une matinée sans rien de particulier",
        ])

        #expect(subjects == ["iPhone 18 Pro", "Trump Iran", "Budget 2027"])
        #expect(subjects.count <= SearchSubjects.limit)
    }

    @Test("What the reader already searched for is not offered again")
    func excluded() {
        let subjects = SearchSubjects.subjects(
            in: ["Apple présente l'iPhone 18 Pro", "Le budget 2027 arrive devant l'Assemblée"],
            excluding: ["iphone 18 pro"]
        )

        #expect(subjects == ["Budget 2027"])
    }

    @Test("A subject another one already says in full is not offered twice")
    func containment() {
        let subjects = SearchSubjects.subjects(in: [
            "Trump donne dix jours à l'Iran",
            "une journée avec Trump",
        ])

        #expect(subjects == ["Trump Iran"])
    }
}
