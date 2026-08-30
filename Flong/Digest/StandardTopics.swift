//
//  StandardTopics.swift
//  Flong
//
//  Created by François Rousselet on 31/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The sections a newspaper has always had.
///
/// **A vocabulary the reader does not have to build.** The model used to start
/// with nothing and name every subject itself, so the first weeks of a library
/// were a drift of near-synonyms and the reader had nothing to hold an opinion
/// about until the drift settled. These are there from the first launch : the
/// names any reader already knows, because every paper and every news
/// application has used them for a century.
///
/// **They are seeded and then ordinary.** Nothing keeps them apart afterwards
/// except that the reader may not delete them : a story is filed under one the
/// same way it is filed under any other, and a preference attached to one works
/// the same. What they buy is a page that reads sensibly on its first day.
///
/// **Stored in the reader's language, like everything else the model writes.**
/// A subject is a string in the store, and the model is shown strings and
/// answers with them ; a key resolved at each draw would have to be resolved
/// for the model too, which would mean translating what it answers back. The
/// cost is the one the model's own subjects already carry : a reader who
/// changes language keeps the names they had.
nonisolated enum StandardTopics {
    /// The list, in the order a page would print them.
    static let all: [LocalizedStringResource] = [
        "Politique",
        "International",
        "Économie",
        "Société",
        "Écologie",
        "Sciences",
        "Technologie",
        "Santé",
        "Culture",
        "Sport",
        "Éducation",
        "Justice",
        "Médias",
    ]

    /// The names as this reader reads them.
    static func names(for locale: Locale = .current) -> [String] {
        all.map {
            var resource = $0
            resource.locale = locale
            return String(localized: resource)
        }
    }
}
