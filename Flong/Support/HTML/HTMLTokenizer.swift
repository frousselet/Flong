//
//  HTMLTokenizer.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// One attribute of a tag.
nonisolated struct HTMLAttribute: Hashable, Sendable {
    let name: String
    let value: String
}

/// One piece of an HTML document.
nonisolated enum HTMLToken: Hashable, Sendable {
    case startTag(name: String, attributes: [HTMLAttribute], isSelfClosing: Bool)
    case endTag(name: String)
    case text(String)
    case comment(String)
}

/// Splits HTML into tokens, the way a browser would rather than the way a
/// validator would.
///
/// Feed content is written by a thousand different generators and is almost
/// never well formed : unclosed paragraphs, unquoted attributes, stray `<`, a
/// `<br>` that never closes. None of it may lose the article, so the tokenizer
/// has no failure mode. Anything it cannot make sense of comes back as text.
///
/// It implements the shape of the HTML5 tokenizer, not its letter : enough for
/// the sanitizer of section 10 of the specification, for feed discovery, and for
/// the h-feed parser to work on real pages.
nonisolated enum HTMLTokenizer {
    /// Elements that never hold anything, whether or not they are written closed.
    static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
    ]

    /// Elements whose content is text, never markup.
    ///
    /// A `<` inside a script is not a tag, and treating it as one is how a
    /// sanitizer ends up letting one through.
    static let rawTextElements: Set<String> = ["script", "style", "textarea", "title"]

    static func tokens(in html: String) -> [HTMLToken] {
        var tokens: [HTMLToken] = []
        let characters = Array(html)
        var index = 0

        while index < characters.count {
            guard characters[index] == "<" else {
                let start = index
                while index < characters.count, characters[index] != "<" { index += 1 }
                tokens.append(.text(String(characters[start..<index])))
                continue
            }

            if let (token, next) = markup(in: characters, at: index) {
                tokens.append(token)
                index = next

                // The content of a script or a style is text, whatever it holds.
                if case .startTag(let name, _, let isSelfClosing) = token,
                    rawTextElements.contains(name),
                    !isSelfClosing
                {
                    let (raw, afterRaw) = rawText(in: characters, from: index, until: name)
                    if !raw.isEmpty { tokens.append(.text(raw)) }
                    // The closing tag was consumed with the raw text, and the
                    // tree still has to hear about it.
                    tokens.append(.endTag(name: name))
                    index = afterRaw
                }
            } else {
                // A `<` that opens nothing is a `<`.
                tokens.append(.text("<"))
                index += 1
            }
        }

        return tokens
    }

    // MARK: - Markup

    /// Reads whatever a `<` opens, or `nil` when it opens nothing.
    private static func markup(in characters: [Character], at index: Int) -> (HTMLToken, Int)? {
        let next = index + 1
        guard next < characters.count else { return nil }

        if matches(characters, at: next, "!--") {
            return comment(in: characters, from: next + 3)
        }
        if characters[next] == "!" || characters[next] == "?" {
            // A doctype or a processing instruction : skipped whole.
            var end = next
            while end < characters.count, characters[end] != ">" { end += 1 }
            return (.comment(String(characters[next..<min(end, characters.count)])), min(end + 1, characters.count))
        }
        if characters[next] == "/" {
            return endTag(in: characters, from: next + 1)
        }
        guard characters[next].isLetter else { return nil }
        return startTag(in: characters, from: next)
    }

    private static func comment(in characters: [Character], from index: Int) -> (HTMLToken, Int) {
        var end = index
        while end < characters.count {
            if characters[end] == "-", matches(characters, at: end, "-->") {
                return (.comment(String(characters[index..<end])), end + 3)
            }
            end += 1
        }
        return (.comment(String(characters[index...])), characters.count)
    }

    private static func endTag(in characters: [Character], from index: Int) -> (HTMLToken, Int)? {
        var end = index
        while end < characters.count, characters[end].isTagName { end += 1 }
        guard end > index else { return nil }

        let name = String(characters[index..<end]).lowercased()
        while end < characters.count, characters[end] != ">" { end += 1 }
        return (.endTag(name: name), min(end + 1, characters.count))
    }

    private static func startTag(in characters: [Character], from index: Int) -> (HTMLToken, Int) {
        var cursor = index
        while cursor < characters.count, characters[cursor].isTagName { cursor += 1 }
        let name = String(characters[index..<cursor]).lowercased()

        var attributes: [HTMLAttribute] = []
        var isSelfClosing = false

        while cursor < characters.count {
            while cursor < characters.count, characters[cursor].isHTMLWhitespace { cursor += 1 }
            guard cursor < characters.count else { break }

            if characters[cursor] == ">" {
                cursor += 1
                break
            }
            if characters[cursor] == "/" {
                isSelfClosing = true
                cursor += 1
                continue
            }

            let (attribute, next) = self.attribute(in: characters, from: cursor)
            cursor = next
            if let attribute, !attributes.contains(where: { $0.name == attribute.name }) {
                attributes.append(attribute)
            }
        }

        return (
            .startTag(
                name: name,
                attributes: attributes,
                isSelfClosing: isSelfClosing || voidElements.contains(name)
            ),
            cursor
        )
    }

    /// Reads one attribute, quoted, unquoted or valueless.
    private static func attribute(in characters: [Character], from index: Int) -> (HTMLAttribute?, Int) {
        var cursor = index
        let start = cursor
        while cursor < characters.count, characters[cursor].isAttributeName { cursor += 1 }

        guard cursor > start else {
            // A character that cannot start a name : stepped over so the loop
            // always makes progress.
            return (nil, cursor + 1)
        }
        let name = String(characters[start..<cursor]).lowercased()

        while cursor < characters.count, characters[cursor].isHTMLWhitespace { cursor += 1 }
        guard cursor < characters.count, characters[cursor] == "=" else {
            return (HTMLAttribute(name: name, value: ""), cursor)
        }

        cursor += 1
        while cursor < characters.count, characters[cursor].isHTMLWhitespace { cursor += 1 }
        guard cursor < characters.count else { return (HTMLAttribute(name: name, value: ""), cursor) }

        let quote = characters[cursor]
        if quote == "\"" || quote == "'" {
            cursor += 1
            let valueStart = cursor
            while cursor < characters.count, characters[cursor] != quote { cursor += 1 }
            let value = String(characters[valueStart..<min(cursor, characters.count)])
            return (HTMLAttribute(name: name, value: HTMLEntities.decode(value)), min(cursor + 1, characters.count))
        }

        let valueStart = cursor
        while cursor < characters.count, !characters[cursor].isHTMLWhitespace, characters[cursor] != ">" {
            cursor += 1
        }
        let value = HTMLEntities.decode(String(characters[valueStart..<cursor]))
        return (HTMLAttribute(name: name, value: value), cursor)
    }

    /// Everything up to the closing tag of a raw text element.
    private static func rawText(in characters: [Character], from index: Int, until name: String) -> (String, Int) {
        var end = index
        while end < characters.count {
            if characters[end] == "<", matches(characters, at: end + 1, "/" + name) {
                let raw = String(characters[index..<end])
                var close = end
                while close < characters.count, characters[close] != ">" { close += 1 }
                return (raw, min(close + 1, characters.count))
            }
            end += 1
        }
        return (String(characters[index...]), characters.count)
    }

    /// Whether the characters at that position spell the given text, ignoring case.
    private static func matches(_ characters: [Character], at index: Int, _ text: String) -> Bool {
        let expected = Array(text)
        guard index >= 0, index + expected.count <= characters.count else { return false }
        for offset in 0..<expected.count {
            guard characters[index + offset].lowercased() == expected[offset].lowercased() else { return false }
        }
        return true
    }
}

extension Character {
    fileprivate var isHTMLWhitespace: Bool {
        self == " " || self == "\t" || self == "\n" || self == "\r" || self == "\u{0C}"
    }

    fileprivate var isTagName: Bool {
        isLetter || isNumber || self == "-" || self == "_" || self == ":" || self == "."
    }

    fileprivate var isAttributeName: Bool {
        !isHTMLWhitespace && self != "=" && self != ">" && self != "/" && self != "\"" && self != "'" && self != "<"
    }
}
