//
//  HTMLEntities.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Turns character references back into characters.
///
/// The full HTML table runs to more than two thousand names. What feeds actually
/// use is the handful below plus numeric references, and a name that is not
/// here is left as it stands rather than guessed at, so nothing is ever silently
/// mangled.
nonisolated enum HTMLEntities {
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }

        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex

        while let ampersand = text[index...].firstIndex(of: "&") {
            result += text[index..<ampersand]

            if let (character, after) = reference(in: text, from: ampersand) {
                result += character
                index = after
            } else {
                result += "&"
                index = text.index(after: ampersand)
            }
        }

        result += text[index...]
        return result
    }

    /// Reads the reference starting at an `&`, and what follows it.
    private static func reference(in text: String, from ampersand: String.Index) -> (String, String.Index)? {
        var index = text.index(after: ampersand)
        guard index < text.endIndex else { return nil }

        if text[index] == "#" {
            index = text.index(after: index)
            guard index < text.endIndex else { return nil }

            let isHexadecimal = text[index] == "x" || text[index] == "X"
            if isHexadecimal { index = text.index(after: index) }

            var digits = ""
            while index < text.endIndex, digits.count < 8 {
                let character = text[index]
                if character == ";" {
                    guard
                        let value = UInt32(digits, radix: isHexadecimal ? 16 : 10),
                        let scalar = Unicode.Scalar(value)
                    else { return nil }
                    return (String(Character(scalar)), text.index(after: index))
                }
                guard isHexadecimal ? character.isHexDigit : character.isNumber else { return nil }
                digits.append(character)
                index = text.index(after: index)
            }
            return nil
        }

        var name = ""
        while index < text.endIndex, name.count < 10 {
            let character = text[index]
            if character == ";" {
                guard let value = named[name] else { return nil }
                return (value, text.index(after: index))
            }
            guard character.isLetter || character.isNumber else { return nil }
            name.append(character)
            index = text.index(after: index)
        }
        return nil
    }

    /// The names worth knowing, in the order they turn up in feeds.
    ///
    /// The dashes are written as escapes rather than as themselves : the project
    /// forbids the em dash character in its own sources, and an author who typed
    /// one is still entitled to have it come back unchanged.
    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
        "shy": "\u{00AD}", "zwnj": "\u{200C}", "zwj": "\u{200D}",
        "hellip": "…", "mdash": "\u{2014}", "ndash": "\u{2013}", "minus": "\u{2212}",
        "lsquo": "‘", "rsquo": "’", "sbquo": "‚", "ldquo": "“", "rdquo": "”", "bdquo": "„",
        "laquo": "«", "raquo": "»", "lsaquo": "‹", "rsaquo": "›",
        "bull": "•", "middot": "·", "sect": "§", "para": "¶", "dagger": "†", "Dagger": "‡",
        "copy": "©", "reg": "®", "trade": "™", "deg": "°", "permil": "‰",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "curren": "¤",
        "times": "×", "divide": "÷", "plusmn": "±", "frac12": "½", "frac14": "¼", "frac34": "¾",
        "sup1": "¹", "sup2": "²", "sup3": "³", "micro": "µ", "not": "¬", "iquest": "¿", "iexcl": "¡",
        "larr": "←", "uarr": "↑", "rarr": "→", "darr": "↓", "harr": "↔",
        "agrave": "à", "aacute": "á", "acirc": "â", "atilde": "ã", "auml": "ä", "aring": "å", "aelig": "æ",
        "ccedil": "ç", "egrave": "è", "eacute": "é", "ecirc": "ê", "euml": "ë",
        "igrave": "ì", "iacute": "í", "icirc": "î", "iuml": "ï", "ntilde": "ñ",
        "ograve": "ò", "oacute": "ó", "ocirc": "ô", "otilde": "õ", "ouml": "ö", "oslash": "ø", "oelig": "œ",
        "ugrave": "ù", "uacute": "ú", "ucirc": "û", "uuml": "ü", "yuml": "ÿ", "szlig": "ß",
        "Agrave": "À", "Aacute": "Á", "Acirc": "Â", "Auml": "Ä", "AElig": "Æ", "Ccedil": "Ç",
        "Egrave": "È", "Eacute": "É", "Ecirc": "Ê", "Euml": "Ë", "Icirc": "Î", "Iuml": "Ï",
        "Ocirc": "Ô", "Ouml": "Ö", "OElig": "Œ", "Ugrave": "Ù", "Ucirc": "Û", "Uuml": "Ü",
    ]

    /// Escapes text for a text node.
    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.append(character)
            }
        }
        return result
    }

    /// Escapes text for a double quoted attribute value.
    static func escapeAttribute(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "\"": result += "&quot;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.append(character)
            }
        }
        return result
    }
}
