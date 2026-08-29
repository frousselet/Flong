//
//  FreshRSSSyntax.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Reads the syntax a reader arriving from FreshRSS already knows.
///
/// Section 12 of the specification asks for it to be translated silently, so
/// that a saved search carried over from another reader keeps working rather
/// than quietly returning nothing.
///
/// The translation is on the words, before the query is parsed. What has no
/// equivalent is left as it stands and searched for as text, which is what an
/// unknown operator means anyway.
nonisolated enum FreshRSSSyntax {
    private static let fields = [
        "intitle": "title",
        "intext": "text",
        "inurl": "site",
        "label": "tag",
        "feed": "feed",
        "author": "author",
    ]

    static func translated(_ query: String) -> String {
        var result = ""
        var name = ""

        for character in query {
            if character == ":" {
                result += (fields[name.lowercased()] ?? name) + ":"
                name = ""
                continue
            }
            if character.isLetter {
                name.append(character)
                continue
            }
            result += name + String(character)
            name = ""
        }

        return result + name
    }
}
