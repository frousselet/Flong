//
//  QueryNode.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Where a word is looked for.
nonisolated enum QueryField: String, Hashable, Sendable, CaseIterable {
    /// Every indexed column.
    case any
    case title
    /// The body and the standfirst.
    case text
    case author
    /// The name of the feed, which is not indexed and is matched in SQL.
    case feed
    case site
    case tag
    case lang
}

/// A word or a phrase to look for.
nonisolated struct QueryTerm: Hashable, Sendable {
    let field: QueryField
    let value: String
    /// Written between quotes, so the words must appear in that order.
    let isPhrase: Bool
    /// Written with a trailing star, so it matches what has only been typed halfway.
    let isPrefix: Bool

    init(field: QueryField = .any, value: String, isPhrase: Bool = false, isPrefix: Bool = false) {
        self.field = field
        self.value = value
        self.isPhrase = isPhrase
        self.isPrefix = isPrefix
    }

    /// Whether the term is answered by the full-text index rather than by SQL.
    var isIndexed: Bool {
        switch field {
        case .any, .title, .text, .author: true
        case .feed, .site, .tag, .lang: false
        }
    }
}

/// A state an article is in.
nonisolated enum QueryState: String, Hashable, Sendable, CaseIterable {
    case unread
    case read
    case starred
    /// Filed in at least one collection the reader made.
    case collected
    /// Written on.
    case annotated
    case media
    case fulltext
}

/// A moment a query is measured against.
nonisolated enum QueryDate: Hashable, Sendable {
    /// Published on or after that moment.
    case after(Date)
    /// Published before that moment.
    case before(Date)
    /// Younger than that many seconds.
    case youngerThan(TimeInterval)
    /// Older than that many seconds.
    case olderThan(TimeInterval)
}

/// A query, parsed.
///
/// Section 12 of the specification asks for an explicit grammar parsed into a
/// tree, and for the tree to be what compiles to SQL. Nothing is ever built by
/// pasting the reader's words into a statement : that is how a search field
/// becomes a way to run anything.
nonisolated indirect enum QueryNode: Hashable, Sendable {
    case all
    case term(QueryTerm)
    case state(QueryState)
    case date(QueryDate)
    case and([QueryNode])
    case or([QueryNode])
    case not(QueryNode)

    /// Whether the whole subtree can be handed to the full-text index.
    ///
    /// A negation cannot : FTS5 only knows `NOT` as a binary operator, and
    /// rewriting a unary one into it is how a query starts meaning something
    /// else. Those become SQL instead.
    var isIndexed: Bool {
        switch self {
        case .term(let term): term.isIndexed
        case .and(let children), .or(let children): !children.isEmpty && children.allSatisfy(\.isIndexed)
        case .all, .state, .date, .not: false
        }
    }
}
