//
//  CollectionCovers.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The handful of pictures a collection's square is drawn from.
///
/// **Four, in a two by two.** One picture said what a collection held only for
/// the collections whose newest article happened to be typical of it ; four say
/// it for the rest, and a square of four small photographs is read as a
/// collection rather than as an article. It is the shape a photo library and a
/// record shelf both give the same idea, so a reader has met it before.
///
/// **The same four, drawn once, for every square on the page.** Six different
/// places work out what a collection holds : the marks, the two directories,
/// the ones the reader filled, the ones they described, and the ones somebody
/// shared. What they have in common is exactly this, and a second spelling of
/// it is a page where one band of squares picks its pictures differently from
/// the band above it.
nonisolated enum CollectionCovers {
    /// How many pictures a square shows.
    static let most = 4

    /// How far back the four are looked for.
    ///
    /// **Bounded, because a square is not worth a scan.** The newest few are
    /// what a picture of a collection should be made of anyway, and a corpus of
    /// a hundred and twenty-five thousand articles is not a thing to sort in
    /// full so that a thumbnail can have a fourth quarter.
    static let pool = 40

    /// The pictures, as a column a query can select.
    ///
    /// The addresses arrive joined by newlines, which no URL may contain, so
    /// nothing has to be escaped and nothing can be split wrongly.
    ///
    /// **One picture per address, however many articles carry it.** A morning's
    /// wire from one newsroom is routinely four articles under one photograph,
    /// and four copies of it in a square is a square that looks broken. So the
    /// newest few are grouped by address before four of them are kept, and what
    /// the reader sees is four different pictures or as many as there are.
    ///
    /// - Parameter condition: what makes an article one of this collection's,
    ///   written against the alias `i`.
    static func sql(where condition: String) -> String {
        """
        (SELECT group_concat(u, char(10)) FROM (
            SELECT u FROM (
                SELECT i.image_url AS u, COALESCE(i.published_at, i.received_at) AS seen
                FROM entry i WHERE \(condition) AND i.image_url IS NOT NULL
                ORDER BY seen DESC LIMIT \(pool)
            )
            GROUP BY u ORDER BY MAX(seen) DESC LIMIT \(most)
        ))
        """
    }

    /// What that column holds, read back as addresses.
    static func read(_ joined: String?) -> [URL] {
        (joined ?? "").split(separator: "\n").compactMap { URL(string: String($0)) }
    }

    /// The same four, chosen in Swift rather than in SQL.
    ///
    /// For the two collections whose contents no single query answers : one
    /// described rather than filled, and one somebody else shared. They are
    /// handed their articles newest first and the rule is the one above, so a
    /// square drawn from either matches the squares beside it.
    static func of(_ addresses: some Sequence<URL>) -> [URL] {
        var seen: Set<URL> = []
        var found: [URL] = []
        for address in addresses where seen.insert(address).inserted {
            found.append(address)
            if found.count == most { break }
        }
        return found
    }
}
