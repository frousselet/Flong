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
///   themselves. Starred articles is the state of one article, yes or no, and
///   that state is what travels : the collection itself is not a thing that
///   exists anywhere, it is what the answers add up to. Favourite sources asks
///   the question of the publisher instead, and favourite authors of whoever
///   signed the piece ; in both the answer is no less the reader's for being
///   written a row further out.
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
    /// Each is a column rather than a list of anything, which is why there is
    /// no adding to one : an article joins the starred by being starred, the
    /// notes by being written on, and the favourite sources by having been
    /// published by a source the reader singled out.
    ///
    /// **Favourite sources is not a second name for the star**, and the two
    /// squares sit side by side so that it cannot be read as one. Starring an
    /// article is a judgement about that article ; making a source a favourite
    /// is a judgement about the publisher, and it never stars anything. A
    /// reader who follows `lemonde.fr` closely and has starred four of its
    /// pieces has one square holding a morning's worth and another holding
    /// four, which is exactly the distinction.
    ///
    /// **A favourite author is the third of those judgements**, and it is about
    /// neither the article nor the paper : a reader follows a writer across the
    /// papers they write for, which is a thing no subscription can express. It
    /// stars nothing either, and it stands third in the row so that the three
    /// are read as three.
    ///
    /// **The order is the order of the page**, since these are the squares the
    /// reader did not make and cannot arrange. The three judgements come first,
    /// each about a different thing : an article, a publisher, a writer. Then
    /// the notes, which are the reader's own words. Then the authors, which is
    /// the one square that opens on people rather than on articles, and which
    /// belongs at the end for exactly that reason.
    nonisolated enum BuiltIn: String, Hashable, Sendable, CaseIterable {
        case starred
        case favouriteSources
        case favouriteAuthors
        case annotated
        /// Every byline there is, which is a directory and not a collection of
        /// articles. It is here because it is a square on that page and the
        /// reader reads it as one ; it is the only one that opens on a list of
        /// people, and ``ArticleStore`` answers no articles for it on purpose.
        case authors

        /// Where it goes on the page.
        var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
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
