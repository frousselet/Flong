//
//  OPMLReader.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Why an OPML file could not be read.
nonisolated enum OPMLError: Error, Hashable, Sendable {
    /// The bytes are not XML, even after the repair pass.
    case unreadable
    /// Well formed, but it holds no `opml` element.
    case notOPML
}

/// Reads an OPML file into an ``OPMLDocument``.
///
/// Exported OPML is routinely broken : a bare ampersand in a title, a control
/// character in the middle of a description, an encoding the declaration lies
/// about. Section 19 of the specification asks for tolerance, so a file that
/// `XMLParser` refuses is repaired once and parsed again, rather than being
/// handed back to the reader as a failure.
nonisolated enum OPMLReader {
    static func read(_ data: Data) throws -> OPMLDocument {
        do {
            return try parse(data)
        } catch OPMLError.unreadable {
            return try parse(repaired(data))
        }
    }

    private static func parse(_ data: Data) throws -> OPMLDocument {
        let parser = XMLParser(data: data)
        let delegate = Builder()
        parser.delegate = delegate

        guard parser.parse() else { throw OPMLError.unreadable }
        guard delegate.sawOPML else { throw OPMLError.notOPML }
        return delegate.document
    }

    // MARK: - Repair

    /// Rewrites bytes `XMLParser` refuses into something it accepts.
    ///
    /// Three things go wrong in the wild, and all three are recoverable :
    /// an encoding the declaration gets wrong, a bare `&` that is not an entity,
    /// and control characters XML forbids.
    static func repaired(_ data: Data) -> Data {
        var text = decoded(data)
        text = withoutDeclaration(text)
        text = withoutForbiddenCharacters(text)
        text = escapingBareAmpersands(text)
        return Data(text.utf8)
    }

    /// Reads the bytes as text, falling back rather than giving up.
    private static func decoded(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let latin1 = String(data: data, encoding: .isoLatin1) { return latin1 }
        return String(decoding: data, as: UTF8.self)
    }

    /// Drops the XML declaration.
    ///
    /// The text is handed back as UTF-8, so a declaration naming another
    /// encoding would send the parser looking for bytes that are no longer
    /// there. Without a declaration, UTF-8 is the default.
    private static func withoutDeclaration(_ text: String) -> String {
        var text = text
        if text.first == "\u{FEFF}" {
            text.removeFirst()
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<?xml"), let end = trimmed.range(of: "?>") else { return text }
        return String(trimmed[end.upperBound...])
    }

    private static func withoutForbiddenCharacters(_ text: String) -> String {
        String(
            String.UnicodeScalarView(
                text.unicodeScalars.filter { scalar in
                    switch scalar.value {
                    case 0x09, 0x0A, 0x0D: true
                    case 0x00..<0x20: false
                    case 0xFFFE, 0xFFFF: false
                    default: true
                    }
                }
            )
        )
    }

    /// Escapes an `&` that starts nothing.
    ///
    /// `Cook & Book` is what a title looks like in half the files out there, and
    /// it makes the whole document unparseable. An `&` that does open a known or
    /// numeric entity is left as it is.
    private static func escapingBareAmpersands(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)

        var index = text.startIndex
        while let ampersand = text[index...].firstIndex(of: "&") {
            result += text[index..<ampersand]
            result += opensEntity(in: text, at: ampersand) ? "&" : "&amp;"
            index = text.index(after: ampersand)
        }
        result += text[index...]
        return result
    }

    /// Whether the `&` at that position opens an entity XML knows.
    ///
    /// XML declares five named entities and nothing else. `&eacute;`, which HTML
    /// exporters write freely, is undefined here and kills the parse just as
    /// surely as a bare ampersand, so it is escaped too and shows up as itself
    /// in the title. Losing the whole file over one accent would be worse.
    private static func opensEntity(in text: String, at ampersand: String.Index) -> Bool {
        var index = text.index(after: ampersand)
        guard index < text.endIndex else { return false }

        if text[index] == "#" {
            index = text.index(after: index)
            var length = 0
            while index < text.endIndex, length < 8 {
                let character = text[index]
                if character == ";" { return length > 0 }
                guard character.isHexDigit || character == "x" else { return false }
                index = text.index(after: index)
                length += 1
            }
            return false
        }

        var name = ""
        while index < text.endIndex, name.count < 5 {
            let character = text[index]
            if character == ";" { return Self.xmlEntities.contains(name) }
            guard character.isLetter else { return false }
            name.append(character)
            index = text.index(after: index)
        }
        return false
    }

    private static let xmlEntities: Set<String> = ["amp", "lt", "gt", "quot", "apos"]

    // MARK: - Parsing

    /// Builds the tree as `XMLParser` walks the file.
    private final class Builder: NSObject, XMLParserDelegate {
        private(set) var document = OPMLDocument()
        private(set) var sawOPML = false

        private var stack: [OPMLOutline] = []
        private var headTitle: String?
        private var isInHeadTitle = false

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            switch elementName.lowercased() {
            case "opml":
                sawOPML = true
            case "title":
                isInHeadTitle = true
            case "outline":
                stack.append(
                    OPMLOutline(
                        text: Builder.attribute("text", of: attributes),
                        title: Builder.attribute("title", of: attributes),
                        xmlURL: Builder.attribute("xmlUrl", of: attributes),
                        htmlURL: Builder.attribute("htmlUrl", of: attributes),
                        type: Builder.attribute("type", of: attributes),
                        category: Builder.attribute("category", of: attributes)
                    )
                )
            default:
                break
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            switch elementName.lowercased() {
            case "title":
                isInHeadTitle = false
                if document.title == nil, let headTitle, !headTitle.isEmpty {
                    document.title = headTitle
                }
                headTitle = nil
            case "outline":
                guard let outline = stack.popLast() else { return }
                if stack.isEmpty {
                    document.outlines.append(outline)
                } else {
                    stack[stack.count - 1].children.append(outline)
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard isInHeadTitle else { return }
            headTitle = (headTitle ?? "") + string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// Reads an attribute whatever case the exporter wrote it in.
        ///
        /// `xmlUrl`, `xmlurl` and `XMLURL` all appear in files that are otherwise
        /// perfectly valid.
        private static func attribute(_ name: String, of attributes: [String: String]) -> String? {
            let value =
                attributes[name] ?? attributes.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
    }
}
