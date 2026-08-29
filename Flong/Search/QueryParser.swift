//
//  QueryParser.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Turns a query into a tree.
///
/// The grammar, in the order it binds :
///
/// ```
/// query      = disjunction
/// disjunction = conjunction (OR conjunction)*
/// conjunction = unary (AND? unary)*
/// unary      = ("-" | "NOT") unary | primary
/// primary    = "(" query ")" | field ":" value | value
/// value      = word | phrase
/// ```
///
/// Words sitting next to each other are joined by an implicit `AND`, which is
/// what everyone expects of a search field.
///
/// The parser never fails. A bracket that closes nothing, an `OR` with nothing
/// after it, a field name with no value : each has a reading that keeps the rest
/// of the query working, and refusing the whole thing would only leave the
/// reader without results and without an explanation.
nonisolated struct QueryParser {
    private let tokens: [QueryToken]
    private var index = 0
    private let now: Date

    private init(tokens: [QueryToken], now: Date) {
        self.tokens = tokens
        self.now = now
    }

    /// Parses a query as it was typed.
    static func parse(_ query: String, now: Date = Date()) -> QueryNode {
        var parser = QueryParser(tokens: QueryLexer.tokens(in: FreshRSSSyntax.translated(query)), now: now)
        let node = parser.parseDisjunction()
        return parser.isAtEnd ? node : .and([node, parser.parseRemainder()])
    }

    // MARK: - Grammar

    private mutating func parseDisjunction() -> QueryNode {
        var branches = [parseConjunction()]

        while match(.or) {
            guard !isAtEnd else { break }
            branches.append(parseConjunction())
        }

        return branches.count == 1 ? branches[0] : .or(branches)
    }

    private mutating func parseConjunction() -> QueryNode {
        var terms: [QueryNode] = []

        while !isAtEnd {
            if peek == .or || peek == .closeParenthesis { break }
            _ = match(.and)
            if isAtEnd || peek == .or { break }

            let position = index
            if let term = parseUnary() {
                terms.append(term)
            }
            // A token that yielded nothing still has to be stepped over, or the
            // parser would sit on it for ever.
            if index == position { break }
        }

        return switch terms.count {
        case 0: .all
        case 1: terms[0]
        default: .and(terms)
        }
    }

    private mutating func parseUnary() -> QueryNode? {
        if match(.minus) || match(.not) {
            guard let node = parseUnary() else { return nil }
            return .not(node)
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> QueryNode? {
        guard let token = advance() else { return nil }

        switch token {
        case .openParenthesis:
            let node = parseDisjunction()
            _ = match(.closeParenthesis)
            return node

        case .closeParenthesis:
            // A bracket closing nothing is not a term, and not a reason to stop.
            return nil

        case .word(let word):
            let value = word.trimmingCharacters(in: .punctuation)
            guard !value.isEmpty else { return nil }
            return .term(QueryTerm(value: value, isPrefix: word.hasSuffix("*")))

        case .phrase(let phrase):
            guard !phrase.isEmpty else { return nil }
            return .term(QueryTerm(value: phrase, isPhrase: true))

        case .field(let name):
            return parseField(named: name)

        case .and, .or, .not, .minus:
            // An operator with nothing to operate on is skipped.
            return nil
        }
    }

    /// A `name:value` pair, or the name as an ordinary word when it stands alone.
    private mutating func parseField(named name: String) -> QueryNode? {
        guard let value = peekValue() else {
            return .term(QueryTerm(value: name))
        }

        switch name {
        case "is":
            guard let state = Self.state(named: value) else { return .term(QueryTerm(value: value)) }
            _ = advance()
            return .state(state)

        case "has":
            guard let state = Self.state(named: value) else { return .term(QueryTerm(value: value)) }
            _ = advance()
            return .state(state)

        case "after", "before":
            guard let date = QueryDates.date(from: value) else { return .term(QueryTerm(value: value)) }
            _ = advance()
            return .date(name == "after" ? .after(date) : .before(date))

        case "age":
            guard let age = QueryDates.age(from: value) else { return .term(QueryTerm(value: value)) }
            _ = advance()
            return .date(age)

        default:
            guard let field = QueryField(rawValue: name), field != .any else {
                // An unknown name is not an operator, so the pair is read as the
                // two words it looks like.
                return .term(QueryTerm(value: name))
            }
            let token = advance()
            let isPhrase = token.map { if case .phrase = $0 { true } else { false } } ?? false
            let text = isPhrase ? value : value.trimmingCharacters(in: .punctuation)
            guard !text.isEmpty else { return nil }

            return .term(
                QueryTerm(
                    field: field,
                    value: text,
                    isPhrase: isPhrase,
                    isPrefix: !isPhrase && value.hasSuffix("*")
                )
            )
        }
    }

    /// Everything left over after the grammar has had its say.
    ///
    /// A query like `a) b` leaves a tail. It is parsed as its own query and
    /// joined on, rather than dropped.
    private mutating func parseRemainder() -> QueryNode {
        var nodes: [QueryNode] = []
        while !isAtEnd {
            let before = index
            let node = parseDisjunction()
            if node != .all { nodes.append(node) }
            if index == before { index += 1 }
        }

        return switch nodes.count {
        case 0: .all
        case 1: nodes[0]
        default: .and(nodes)
        }
    }

    // MARK: - Tokens

    private var isAtEnd: Bool { index >= tokens.count }

    private var peek: QueryToken? { isAtEnd ? nil : tokens[index] }

    private mutating func advance() -> QueryToken? {
        guard !isAtEnd else { return nil }
        defer { index += 1 }
        return tokens[index]
    }

    private mutating func match(_ token: QueryToken) -> Bool {
        guard peek == token else { return false }
        index += 1
        return true
    }

    /// The text of the next token, when it carries any.
    private func peekValue() -> String? {
        switch peek {
        case .word(let word): word
        case .phrase(let phrase): phrase
        default: nil
        }
    }

    private static func state(named name: String) -> QueryState? {
        switch name.lowercased() {
        case "unread": .unread
        case "read": .read
        case "starred", "favorite", "favourite": .starred
        case "library", "kept": .library
        case "media", "enclosure", "podcast": .media
        case "fulltext", "content", "body": .fulltext
        default: nil
        }
    }
}

nonisolated extension CharacterSet {
    /// What a word may end with without meaning it : a trailing star is an
    /// instruction, and the rest is punctuation the reader typed by habit.
    fileprivate static let punctuation = CharacterSet(charactersIn: "*.,;")
}
