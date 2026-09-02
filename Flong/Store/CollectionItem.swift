//
//  CollectionItem.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// One row of an opened collection, whoever put it there.
///
/// **A collection is one list and is read as one.** What the reader filed and
/// what somebody else filed were two bands under two headings, which said the
/// two were different kinds of thing. They are not : they are what is in the
/// collection, and a reader going back to something they saw yesterday does not
/// remember which of them put it there. So there is one run of rows in date
/// order, and who filed each one is a line on the row rather than a wall
/// between them.
///
/// **What differs is not who filed it but what this device holds.** A piece the
/// reader follows the source of is their own article, with its body, its read
/// state and their marks ; one from a feed they do not follow is the excerpt
/// its publisher put in the feed, and the article itself is at the end of a
/// link. ``ArticleKey`` decides which of the two a shared entry is, and it is
/// the only thing this distinction is ever about.
nonisolated enum CollectionItem: Identifiable, Hashable, Sendable {
    /// An article this device holds, whether the reader filed it or somebody
    /// else did and the reader happens to follow the same source.
    case held(ArticleSummary)
    /// An excerpt somebody sent, of a piece this device does not hold.
    case excerpt(SharedEntry)

    var id: String {
        switch self {
        case .held(let article): "held-" + article.id.uuidString
        case .excerpt(let entry): "sent-" + entry.guid
        }
    }

    /// What the run of rows is ordered by : published where anybody said so,
    /// and failing that when it reached this device.
    var date: Date {
        switch self {
        case .held(let article): article.date
        case .excerpt(let entry): entry.date
        }
    }

    /// The article's identity as everybody's copy of it is keyed, for the rows
    /// that have one. It is what a removal is written against.
    var guid: String? {
        switch self {
        case .held: nil
        case .excerpt(let entry): entry.guid
        }
    }

    /// Merges what this device holds with what was sent, newest first.
    ///
    /// **A sent excerpt gives way to the reader's own copy of the piece.** Where
    /// they follow the same source they already have the article, and the
    /// specification asks for theirs to be the one shown : with its body, its
    /// read state and their marks, rather than three hundred characters of it.
    /// `held` is what they filed themselves and `local` what they hold without
    /// having filed it, and an article that turns up in both is one row.
    static func merge(
        held: [ArticleSummary],
        sent: [SharedEntry],
        localCopies: [String: ArticleSummary],
        key: (SharedEntry) -> String?
    ) -> [CollectionItem] {
        var items = held.map(CollectionItem.held)
        var seen = Set(held.map(\.id))

        for entry in sent {
            if let copy = key(entry).flatMap({ localCopies[$0] }) {
                guard seen.insert(copy.id).inserted else { continue }
                items.append(.held(copy))
            } else {
                items.append(.excerpt(entry))
            }
        }

        // Ties broken by the identifier so the order is the same on every
        // read : two pieces published in the same second must not swap places
        // under the reader between one load and the next.
        return items.sorted { one, other in
            one.date == other.date ? one.id < other.id : one.date > other.date
        }
    }
}
