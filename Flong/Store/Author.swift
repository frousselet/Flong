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
/// **What is cleaned is the spelling, never the person.** A byline arrives
/// wrapped in the whitespace of a pretty-printed feed, or as the address RSS
/// 2.0 says the field holds, or behind the word a publisher puts in front of
/// every credit. None of that is information about who wrote the piece, and all
/// of it would otherwise be part of the name : `lawyer@boyer.net (Lawyer
/// Boyer)` would be a writer, and so would `By Lawyer Boyer`, and neither would
/// ever meet the other. The rules are in ``name(from:)``, they are applied once
/// on the way in, and every one of them is mechanical.
nonisolated struct Author: Identifiable, Hashable, Sendable {
    /// The byline, as the feed spells it, cleaned.
    var name: String

    /// How many of their articles this device holds.
    ///
    /// Zero is a real answer : a writer the reader singled out keeps their row
    /// after the last of their articles has been purged, and a favourite that
    /// arrived from another device names somebody this one has never read.
    var count: Int

    /// Whether the reader singled them out.
    var isFavourite: Bool

    /// Whether the reader asked to be told when they publish.
    ///
    /// Not the favourite above under another name. A favourite writer is
    /// somebody the reader wants gathered on a page of their own ; this is
    /// somebody worth being interrupted for, wherever they happen to write.
    var notifies: Bool = false

    /// Where they write, by publisher, most published in first.
    ///
    /// **The domains and not the marks.** A publisher's mark is drawn from
    /// what the reader is subscribed to now, by the one map the whole
    /// application looks it up in, so a page renaming a publisher renames it
    /// here too and a store that carried pictures would be carrying a second
    /// copy of something already answered. See `SourceIdentity`.
    var publishers: [String] = []

    var id: String { name }

    /// The spelling to keep, out of whatever the feed sent.
    ///
    /// **Deterministic, and deliberately so.** The stored byline is the
    /// identity a favourite is named after between devices, so a rule that
    /// answered differently on two of them would give one writer two rows and a
    /// favourite that only half travels. Nothing here asks a model, and nothing
    /// here depends on what the device can do.
    ///
    /// The rules, in the order they are applied :
    ///
    /// 1. **Entities are decoded and whitespace collapsed.** `Jean&nbsp;Dupont`
    ///    and a name sitting on its own line inside a pretty-printed element
    ///    are the same writer badly typeset, and not two.
    /// 2. **A person is taken out of an address.** RSS 2.0 defines the `author`
    ///    element as the author's e-mail address, with the convention of naming
    ///    them in brackets after it, so `lawyer@boyer.net (Lawyer Boyer)` is a
    ///    name wearing an inbox. The other spelling, `Lawyer Boyer
    ///    <lawyer@boyer.net>`, is the same thing the other way round.
    /// 3. **The word in front of the credit goes.** `By`, `Par`, `Written by`
    ///    and the rest are the publisher's furniture and never part of anybody's
    ///    name.
    /// 4. **What follows a vertical bar goes.** `Jean Dupont | Le Monde` is a
    ///    byline with a masthead stapled to it, and keeping it would give one
    ///    writer a row per paper they write for, which is the one thing the
    ///    authors page exists to undo.
    ///
    /// **A dash is left alone**, though `Jean Dupont - BBC News` is the same
    /// shape : a bar cannot be part of a name and a dash can, and cutting on it
    /// would be guessing where a name ends. A vertical bar is the only
    /// separator here that is never anything else.
    ///
    /// **Capitalization is left alone too.** `JEAN DUPONT` and `Jean Dupont`
    /// are two spellings of one person, which is a merge and not a cleaning :
    /// deciding they are the same is a judgement, and the initials, the
    /// acronyms and the names that really are set in capitals are what a rule
    /// would get wrong. It belongs to a layer where the reader can see it and
    /// undo it.
    ///
    /// **A newsroom is left alone.** `Rédaction`, `Editor` and `admin` are what
    /// the publisher said, and deciding they are not people is a judgement
    /// about the byline rather than a fact about its spelling.
    ///
    /// Nobody, on the other hand, is nobody : an empty field, a lone piece of
    /// punctuation, an address with no name on it and a link are all things a
    /// feed puts in that field, and none of them is somebody. They yield no
    /// author, which is the truth : that article is signed by nobody this can
    /// name.
    static func name(from raw: String?) -> String? {
        guard let raw else { return nil }

        var name = collapsed(HTMLEntities.decode(raw))
        name = person(inAddress: name) ?? name
        name = withoutQuotes(name)
        name = withoutCredit(name)
        name = withoutPublication(name)
        name = collapsed(name)

        return isAName(name) ? name : nil
    }

    /// Everybody a byline names, which is very often more than one.
    ///
    /// **One field for a whole newsroom.** No feed format has a place for a
    /// second author that publishers actually use, so they write both into the
    /// one field and leave the reader to unpick them : `Claire Ancelin et Paul
    /// Rey`, `Smith; Doe`, `A & B`. Kept whole, two people are a third person
    /// who has written one article, and neither of the two is ever findable.
    ///
    /// **The line is cleaned before it is cut**, since the wrappings go round
    /// the whole of it : `lawyer@boyer.net (Claire Ancelin and Paul Rey)` names
    /// two people inside one address, and cutting first would leave half an
    /// address on one of them. Each name is then put through ``name(from:)``
    /// again, which is what takes a masthead off the last of them and a credit
    /// off the first.
    ///
    /// **A comma is not a separator on its own.** `Dupont, Jean` is one person
    /// written the way a directory writes them, and `Claire Ancelin, Paul Rey`
    /// is two : what tells them apart is that neither half of the first holds a
    /// space. The rule is applied to each piece rather than to the line, so
    /// `Dupont, Jean; Curie, Marie` is two people written backwards and not
    /// four written wrong.
    ///
    /// Everything the comma cannot answer is left alone. `Claire Ancelin,
    /// Reporter` is a name and a job, and no rule can tell that from a name and
    /// a name.
    static func people(in raw: String?) -> [String] {
        guard let line = name(from: raw) else { return [] }

        return
            chunks(of: line)
            .flatMap(names(inChunk:))
            .compactMap { name(from: $0) }
            // A byline that names somebody twice names them once.
            .reduce(into: []) { found, person in
                if !found.contains(person) { found.append(person) }
            }
    }

    /// The order a reader expects names in.
    ///
    /// Not the order SQLite puts them in : `ORDER BY` is byte order, where
    /// `Zola` comes before `Éluard` because a capital E with an acute accent
    /// starts with a higher byte than a Z.
    static func before(_ first: Author, _ second: Author) -> Bool {
        first.name.localizedStandardCompare(second.name) == .orderedAscending
    }

    // MARK: - The rules

    /// One line, whatever the feed's indentation made of it.
    private static func collapsed(_ line: String) -> String {
        line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The person named beside an address, when the field holds one.
    ///
    /// Only where there is an address : a byline is not stripped of its
    /// brackets in general, since `Jean Dupont (Le Monde)` is a publisher the
    /// reader may well want to keep reading, and this is not the place to
    /// decide otherwise.
    private static func person(inAddress line: String) -> String? {
        guard line.contains("@") else { return nil }

        // `lawyer@boyer.net (Lawyer Boyer)`, which is what RSS 2.0's own
        // example looks like.
        if let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"), open < close {
            return String(line[line.index(after: open)..<close])
        }
        // `Lawyer Boyer <lawyer@boyer.net>`, which is how a mail client would
        // write the same thing. An address alone opens at the start and names
        // nobody.
        if let open = line.firstIndex(of: "<"), open != line.startIndex {
            return String(line[..<open])
        }
        return nil
    }

    /// The name inside the quotation marks a mail header puts round it.
    private static func withoutQuotes(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for quote in ["\"", "'"] where trimmed.count > 1 && trimmed.hasPrefix(quote) && trimmed.hasSuffix(quote) {
            return String(trimmed.dropFirst().dropLast())
        }
        return line
    }

    /// The words a publisher writes in front of every credit.
    ///
    /// Longest first, since `written by` starts with a word that is itself one
    /// of these and the shorter rule would leave `by` behind.
    private static let credits = [
        "written by ", "posted by ", "author : ", "author: ", "auteur : ", "auteur: ", "by ", "par ",
    ]

    private static func withoutCredit(_ line: String) -> String {
        for credit in credits {
            // Anchored and case-insensitive, and the range is taken from the
            // line itself rather than from a lowercased copy : folding case can
            // change a string's length, and dropping the wrong number of
            // characters would take a letter of the name with it.
            guard let word = line.range(of: credit, options: [.caseInsensitive, .anchored]),
                word.upperBound < line.endIndex
            else { continue }

            return String(line[word.upperBound...])
        }
        return line
    }

    /// What is before the bar, which is the byline. See ``name(from:)``.
    private static func withoutPublication(_ line: String) -> String {
        guard let bar = line.firstIndex(of: "|") else { return line }
        return String(line[..<bar])
    }

    /// The separators that are never anything but separators.
    ///
    /// A semicolon and an ampersand cannot be part of a name. `and` and `et`
    /// can only be read as one where they stand alone between two names, which
    /// is what the spaces round them say.
    private static let separators = [";", " & ", " and ", " et "]

    private static func chunks(of line: String) -> [String] {
        separators.reduce([line]) { found, separator in
            found.flatMap { split($0, on: separator) }
        }
    }

    /// One line cut on every occurrence of a separator, whatever its case.
    ///
    /// By hand rather than through `components(separatedBy:)`, which is case
    /// sensitive : `Ancelin AND Rey` is the same byline as `Ancelin and Rey`.
    private static func split(_ line: String, on separator: String) -> [String] {
        var parts: [String] = []
        var rest = Substring(line)

        while let found = rest.range(of: separator, options: .caseInsensitive) {
            parts.append(String(rest[..<found.lowerBound]))
            rest = rest[found.upperBound...]
        }
        parts.append(String(rest))
        return parts
    }

    /// The names in one piece of a byline, cut on its commas or not at all.
    private static func names(inChunk chunk: String) -> [String] {
        let parts =
            chunk
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // `Dupont, Jean` : two halves, neither of them holding a space, which
        // is one person written the way a directory writes them.
        if parts.count == 2, parts.allSatisfy({ !$0.contains(" ") }) {
            return [chunk.trimmingCharacters(in: .whitespaces)]
        }
        return parts
    }

    /// Whether what is left names somebody at all.
    private static func isAName(_ line: String) -> Bool {
        // A letter somewhere in it. What this refuses is the `-`, the `?` and
        // the `--` a publisher leaves in the field where there was nobody to
        // put in it.
        guard line.contains(where: \.isLetter) else { return false }

        // A link is where an article's byline points, and not who wrote it.
        let anchored: String.CompareOptions = [.caseInsensitive, .anchored]
        for scheme in ["http://", "https://"] where line.range(of: scheme, options: anchored) != nil {
            return false
        }

        // An address with nobody's name on it is an inbox. `noreply@` is the
        // ordinary case and not the odd one.
        return !(line.contains("@") && !line.contains(" "))
    }
}
