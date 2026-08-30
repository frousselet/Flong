//
//  ArticleCollection.swift
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
/// **Three natures, and what travels between the reader's devices is different
/// for each.** That is not an implementation detail : it is the whole of what
/// tells them apart, and getting it wrong is how a budget of three thousand
/// records becomes a hundred thousand.
///
/// - A **built-in** one is a question every reader's articles answer about
///   themselves. Favourites is the state of one article, yes or no, and that
///   state is what travels : the collection itself is not a thing that exists
///   anywhere, it is what the answers add up to.
/// - A **made** one is filled article by article, and the pair of the two is
///   what travels : this article, in that collection. It rides on the article's
///   own record, so a filing costs a field and not a record.
/// - A **dynamic** one is described rather than filled. The reader writes what
///   they are after and whatever matches is in it, so what travels is the
///   description and never the articles. It costs one small record however many
///   articles it holds, which is the reason to have it at all.
nonisolated struct ArticleCollection: Identifiable, Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        /// One the application defines and every reader has.
        case builtIn(BuiltIn)
        /// One the reader made, filled article by article, by its name.
        case made(String)
        /// One the reader described, filled by whatever matches, by its name.
        case dynamic(String)
    }

    /// The ones that are not made and cannot be unmade.
    ///
    /// Each is a column on an article rather than a list of anything, which is
    /// why there is no adding to one : an article joins the favourites by being
    /// starred and the notes by being written on.
    nonisolated enum BuiltIn: String, Hashable, Sendable, CaseIterable {
        case starred
        case annotated
    }

    var kind: Kind
    var count: Int
    /// The picture of the most recent article in it, when there is one.
    var cover: URL?

    var id: Kind { kind }

    /// The name the reader gave it, when they gave it one.
    var name: String? {
        switch kind {
        case .builtIn: nil
        case .made(let name), .dynamic(let name): name
        }
    }

    /// Whether the reader may rename it or take it away.
    ///
    /// A built-in one is neither : it is not a thing that was made, so there is
    /// nothing there to unmake.
    var isTheReaders: Bool { kind.isTheReaders }
}

nonisolated extension ArticleCollection.Kind {
    /// Whether the reader may rename it or take it away.
    var isTheReaders: Bool {
        switch self {
        case .builtIn: false
        case .made, .dynamic: true
        }
    }
}
