//
//  QueryParserTests.swift
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

@Suite("Query parser")
struct QueryParserTests {
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    private func parse(_ query: String) -> QueryNode {
        QueryParser.parse(query, now: now)
    }

    private func term(_ value: String, _ field: QueryField = .any, phrase: Bool = false, prefix: Bool = false)
        -> QueryNode
    {
        .term(QueryTerm(field: field, value: value, isPhrase: phrase, isPrefix: prefix))
    }

    // MARK: - The grammar

    @Test("Words next to each other are joined")
    func implicitConjunction() {
        #expect(parse("vision pro") == .and([term("vision"), term("pro")]))
    }

    @Test("A phrase is one term, in that order")
    func phrases() {
        #expect(parse("\"vision pro\"") == term("vision pro", phrase: true))
        #expect(parse("title:\"vision pro\"") == term("vision pro", .title, phrase: true))
    }

    @Test("Fields are read, and unknown ones are not")
    func fields() {
        #expect(parse("title:swift") == term("swift", .title))
        #expect(parse("author:dupuis") == term("dupuis", .author))
        #expect(parse("lang:fr") == term("fr", .lang))
        #expect(parse("tag:veille/ios") == term("veille/ios", .tag))
        // An unknown name is two words, not an operator.
        #expect(parse("colour:red") == .and([term("colour"), term("red")]))
    }

    @Test("States and attributes are read")
    func states() {
        #expect(parse("is:unread") == .state(.unread))
        #expect(parse("is:starred") == .state(.starred))
        #expect(parse("has:media") == .state(.media))
        #expect(parse("has:fulltext") == .state(.fulltext))
    }

    @Test("Exclusion is a dash, a bang or a NOT")
    func negation() {
        let expected = QueryNode.not(term("medium.com", .site))
        #expect(parse("-site:medium.com") == expected)
        #expect(parse("!site:medium.com") == expected)
        #expect(parse("NOT site:medium.com") == expected)
    }

    @Test("A dash inside a word is part of the word")
    func hyphens() {
        #expect(parse("vision-pro") == term("vision-pro"))
    }

    @Test("OR binds looser than the implicit AND")
    func precedence() {
        #expect(parse("a b OR c") == .or([.and([term("a"), term("b")]), term("c")]))
        #expect(parse("a AND b OR c") == .or([.and([term("a"), term("b")]), term("c")]))
    }

    @Test("Brackets say what binds to what")
    func grouping() {
        #expect(parse("a (b OR c)") == .and([term("a"), .or([term("b"), term("c")])]))
        #expect(parse("(a OR b) (c OR d)") == .and([.or([term("a"), term("b")]), .or([term("c"), term("d")])]))
    }

    @Test("The example of the specification parses whole")
    func specificationExample() {
        let node = parse(
            "tag:veille/ios (title:\"vision pro\" OR title:visionos) -site:medium.com after:2026-01 is:unread")

        #expect(
            node
                == .and([
                    term("veille/ios", .tag),
                    .or([term("vision pro", .title, phrase: true), term("visionos", .title)]),
                    .not(term("medium.com", .site)),
                    .date(.after(QueryDates.date(from: "2026-01")!)),
                    .state(.unread),
                ])
        )
    }

    // MARK: - Dates

    @Test("A date is as precise as it was typed")
    func dates() {
        #expect(parse("after:2026") == .date(.after(QueryDates.date(from: "2026")!)))
        #expect(parse("before:2026-08-25") == .date(.before(QueryDates.date(from: "2026-08-25")!)))
        #expect(QueryDates.date(from: "2026-13") == nil)
        #expect(QueryDates.date(from: "yesterday") == nil)
    }

    @Test("An age is a duration, either side of it")
    func ages() {
        #expect(parse("age:<7d") == .date(.youngerThan(7 * 86400)))
        #expect(parse("age:>2w") == .date(.olderThan(14 * 86400)))
        #expect(parse("age:12h") == .date(.youngerThan(12 * 3600)))
        #expect(QueryDates.age(from: "soon") == nil)
        #expect(QueryDates.age(from: "0d") == nil)
    }

    // MARK: - FreshRSS

    @Test("The syntax of FreshRSS keeps working")
    func freshRSS() {
        #expect(parse("intitle:swift") == term("swift", .title))
        #expect(parse("intext:concurrency") == term("concurrency", .text))
        #expect(parse("inurl:example.com") == term("example.com", .site))
        #expect(parse("label:veille") == term("veille", .tag))
        #expect(parse("is:favorite") == .state(.starred))
    }

    @Test("A word that merely looks like an operator is left alone")
    func translationIsNarrow() {
        #expect(parse("intitles") == term("intitles"))
        #expect(FreshRSSSyntax.translated("https://example.com/a") == "https://example.com/a")
    }

    // MARK: - Hostile input

    @Test(
        "Nothing typed into a search field can fail to parse",
        arguments: [
            "", "   ", "(", ")", "()", "((()))", "-", "!", "\"", "\"unterminated",
            "AND", "OR", "NOT", "a OR", "OR a", "a AND AND b", "- -", ":", "::", "a:",
            "title:", "is:", "is:nonsense", "after:", "age:", "age:<", "*", "a*", "**",
            "'; DROP TABLE entry; --", "a) b", "((a) OR b))", "NEAR(a b)", "^a", "a NEAR b",
            "\u{0000}\u{FFFD}", "🙂 🙃", "a\"b\"c",
        ]
    )
    func hostileInput(query: String) {
        // The only requirement is that it comes back with a tree rather than a
        // crash : a search field that can be broken is a search field nobody
        // trusts.
        _ = parse(query)
    }

    @Test("A very long query is still just a query")
    func longInput() {
        let query = Array(repeating: "réforme", count: 2000).joined(separator: " OR ")
        let node = parse(query)

        guard case .or(let branches) = node else {
            Issue.record("Expected a disjunction")
            return
        }
        #expect(branches.count == 2000)
    }

    @Test("An empty query matches everything")
    func emptyQuery() {
        #expect(parse("") == .all)
        #expect(parse("   ") == .all)
    }

    @Test("A tail left over by a stray bracket is not dropped")
    func strayBrackets() {
        #expect(parse("a) b") == .and([term("a"), term("b")]))
    }

    // MARK: - Shape

    @Test("A subtree is only handed to the index when the index can answer it")
    func indexability() {
        #expect(parse("vision pro").isIndexed)
        #expect(parse("title:a OR author:b").isIndexed)
        #expect(!parse("lang:fr").isIndexed)
        #expect(!parse("is:unread").isIndexed)
        #expect(!parse("-a").isIndexed)
        #expect(!parse("a is:unread").isIndexed)
    }
}
