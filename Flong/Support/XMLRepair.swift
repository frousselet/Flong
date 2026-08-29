//
//  XMLRepair.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Makes bytes that claim to be XML parseable.
///
/// Exported subscription lists and published feeds are broken in the same ways,
/// and neither the reader nor Flong can ask the publisher to fix them. A
/// document `XMLParser` refuses is repaired once and parsed again, rather than
/// being handed back as a failure.
///
/// The pass does four things and nothing else. It never rewrites structure, so a
/// document that is genuinely not XML stays refused.
nonisolated enum XMLRepair {
    /// Rewrites bytes `XMLParser` refuses into something it accepts.
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
}
