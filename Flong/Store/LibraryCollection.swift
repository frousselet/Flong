//
//  LibraryCollection.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// One square on the collections page.
///
/// **Every one of these is a question the kept articles can answer about
/// themselves**, and none of them is a folder the reader has to keep tidy.
/// Favourites is what they starred, notes is what they wrote on, and the months
/// fall out of when a copy was kept.
///
/// **All of it reads the copy and none of it reads the stream.** A kept article
/// points at the article it came from with `ON DELETE SET NULL`, so anything
/// asked of that row is an answer that disappears the day retention runs. The
/// library exists precisely so that what was kept survives its source, and a
/// collection is not allowed to be the exception.
nonisolated struct LibraryCollection: Identifiable, Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        /// What the reader starred.
        case starred
        /// What the reader wrote something on.
        case annotated
        /// One month of keeping, named by its first day.
        case month(Date)
    }

    var kind: Kind
    var count: Int
    /// The picture of the most recent article in it, when there is one.
    var cover: URL?

    var id: Kind { kind }
}
