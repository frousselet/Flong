//
//  QueryLexer.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// One piece of a query as it was typed.
nonisolated enum QueryToken: Hashable, Sendable {
    case word(String)
    case phrase(String)
    /// A name followed by a colon, `title:`.
    case field(String)
    case and
    case or
    case not
    case openParenthesis
    case closeParenthesis
    /// A `-` or a `!` in front of what it excludes.
    case minus
}

/// Cuts a query into tokens.
///
/// It never fails. Anything it cannot make sense of, an unterminated quote, a
/// stray colon, a lone bracket, becomes an ordinary word : a search field that
/// refuses to search is worse than one that searches for something slightly
/// different from what was meant.
nonisolated enum QueryLexer {
    static func tokens(in query: String) -> [QueryToken] {
        var tokens: [QueryToken] = []
        let characters = Array(query)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character.isWhitespace {
                index += 1
                continue
            }

            switch character {
            case "(":
                tokens.append(.openParenthesis)
                index += 1
                continue
            case ")":
                tokens.append(.closeParenthesis)
                index += 1
                continue
            case "-", "!":
                // A dash excludes what follows only when it opens a term. Glued
                // to what precedes it, it is part of a word, as in "vision-pro".
                let previous = index > 0 ? characters[index - 1] : " "
                if previous.isWhitespace || previous == "(" {
                    tokens.append(.minus)
                    index += 1
                    continue
                }
            case "\"", "'":
                let (phrase, next) = Self.phrase(in: characters, from: index, quote: character)
                tokens.append(.phrase(phrase))
                index = next
                continue
            default:
                break
            }

            let (word, next) = Self.word(in: characters, from: index)
            index = next

            if word.hasSuffix(":"), word.count > 1 {
                tokens.append(.field(String(word.dropLast()).lowercased()))
                continue
            }

            switch word.uppercased() {
            case "AND": tokens.append(.and)
            case "OR": tokens.append(.or)
            case "NOT": tokens.append(.not)
            default: tokens.append(.word(word))
            }
        }

        return tokens
    }

    /// Reads a quoted phrase. An unterminated quote runs to the end, which is
    /// what someone typing one is in the middle of doing.
    private static func phrase(in characters: [Character], from index: Int, quote: Character) -> (String, Int) {
        var end = index + 1
        var value = ""

        while end < characters.count, characters[end] != quote {
            value.append(characters[end])
            end += 1
        }
        return (value, min(end + 1, characters.count))
    }

    private static func word(in characters: [Character], from index: Int) -> (String, Int) {
        var end = index
        var value = ""

        while end < characters.count {
            let character = characters[end]
            if character.isWhitespace || character == "(" || character == ")" || character == "\"" { break }

            value.append(character)
            end += 1

            // A colon ends a field name, so `title:"a b"` reads as a field and a
            // phrase rather than as one long word.
            if character == ":" { break }
        }
        return (value, end)
    }
}
