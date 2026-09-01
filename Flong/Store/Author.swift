//
//  Author.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Somebody who signed an article.
///
/// **An author is a name and nothing else.** There is no row for a person and
/// there could not be one : what a feed hands over is a byline, a piece of text
/// in a field, and the same person writing for two papers is two bylines that
/// only a human eye can tell are one. So the name is the identity, matched
/// exactly, and Flong never guesses that two spellings are one writer. That is
/// the same rule the import follows : what cannot be understood is not invented.
///
/// **What is normalized is the spelling and not the person.** A byline arrives
/// wrapped in the whitespace of a pretty-printed feed, and `Jean Dupont` with a
/// newline in front of it is not a second writer, it is the same one badly
/// typeset. The name is trimmed and its inner runs of whitespace collapsed on
/// the way in, once, so every later question is an exact comparison the index
/// can answer.
nonisolated struct Author: Identifiable, Hashable, Sendable {
    /// The byline, as the feed spells it, trimmed.
    var name: String

    /// How many of their articles this device holds.
    ///
    /// Zero is a real answer : a writer the reader singled out keeps their row
    /// after the last of their articles has been purged, and a favourite that
    /// arrived from another device names somebody this one has never read.
    var count: Int

    /// Whether the reader singled them out.
    var isFavourite: Bool

    var id: String { name }

    /// The spelling to keep, out of whatever the feed sent.
    ///
    /// Empty is nobody : a feed that carries an `author` element with nothing
    /// in it has not named an author, and a blank byline in the list would be a
    /// writer called nothing.
    static func name(from raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    /// The order a reader expects names in.
    ///
    /// Not the order SQLite puts them in : `ORDER BY` is byte order, where
    /// `Zola` comes before `Éluard` because a capital E with an acute accent
    /// starts with a higher byte than a Z.
    static func before(_ first: Author, _ second: Author) -> Bool {
        first.name.localizedStandardCompare(second.name) == .orderedAscending
    }
}
