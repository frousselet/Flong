//
//  QueryCompiler.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB

/// A query, ready to run.
nonisolated struct CompiledQuery: Sendable {
    /// A condition over the article `e` and its feed `f`.
    let condition: String
    let arguments: StatementArguments
    /// The whole query is answered by the index, so results can be ranked by it.
    let matchExpression: String?
}

/// Turns a parsed query into SQL.
///
/// Every value the reader typed travels as a bound parameter, and every word
/// handed to the full-text index is quoted first. Nothing is ever pasted into a
/// statement : a search field that builds SQL by concatenation is a search field
/// that runs whatever is typed into it.
nonisolated enum QueryCompiler {
    /// The weight of each column in the ranking, in the order the index declares
    /// them : a word in a title says far more than the same word in a body.
    static let ranking = "bm25(entry_fts, 10.0, 4.0, 1.0, 3.0)"

    static func compile(_ node: QueryNode, now: Date = Date()) -> CompiledQuery {
        var arguments: [any DatabaseValueConvertible] = []
        let condition = self.condition(node, now: now, arguments: &arguments)

        return CompiledQuery(
            condition: condition,
            arguments: StatementArguments(arguments),
            matchExpression: node.isIndexed ? matchExpression(node) : nil
        )
    }

    // MARK: - SQL

    private static func condition(
        _ node: QueryNode,
        now: Date,
        arguments: inout [any DatabaseValueConvertible]
    ) -> String {
        // A subtree the index can answer whole becomes one match, however deep
        // it is. Anything else is taken apart.
        if node.isIndexed, let expression = matchExpression(node) {
            arguments.append(expression)
            return "e.rowid IN (SELECT rowid FROM entry_fts WHERE entry_fts MATCH ?)"
        }

        switch node {
        case .all:
            return "1"

        case .and(let children):
            let parts = children.map { condition($0, now: now, arguments: &arguments) }
            return parts.isEmpty ? "1" : "(" + parts.joined(separator: " AND ") + ")"

        case .or(let children):
            let parts = children.map { condition($0, now: now, arguments: &arguments) }
            return parts.isEmpty ? "1" : "(" + parts.joined(separator: " OR ") + ")"

        case .not(let child):
            return "NOT (" + condition(child, now: now, arguments: &arguments) + ")"

        case .state(let state):
            return self.condition(for: state)

        case .date(let date):
            return self.condition(for: date, now: now, arguments: &arguments)

        case .term(let term):
            return self.condition(for: term, arguments: &arguments)
        }
    }

    private static func condition(for state: QueryState) -> String {
        switch state {
        case .unread: "e.is_read = 0"
        case .read: "e.is_read = 1"
        case .starred: "e.is_starred = 1"
        case .media: "e.has_media = 1"
        case .library: "EXISTS (SELECT 1 FROM library_item l WHERE l.entry_id = e.id)"
        case .fulltext:
            "EXISTS (SELECT 1 FROM entry_body b WHERE b.entry_id = e.id AND COALESCE(b.plain_text, '') <> '')"
        }
    }

    private static func condition(
        for date: QueryDate,
        now: Date,
        arguments: inout [any DatabaseValueConvertible]
    ) -> String {
        let published = "COALESCE(e.published_at, e.received_at)"

        switch date {
        case .after(let moment):
            arguments.append(moment)
            return "\(published) >= ?"
        case .before(let moment):
            arguments.append(moment)
            return "\(published) < ?"
        case .youngerThan(let age):
            arguments.append(now.addingTimeInterval(-age))
            return "\(published) >= ?"
        case .olderThan(let age):
            arguments.append(now.addingTimeInterval(-age))
            return "\(published) < ?"
        }
    }

    /// The fields the index does not hold, which are matched in SQL.
    private static func condition(for term: QueryTerm, arguments: inout [any DatabaseValueConvertible]) -> String {
        switch term.field {
        case .feed:
            arguments.append(contains(term.value))
            return "f.title LIKE ? ESCAPE '\\'"

        case .site:
            let pattern = contains(term.value)
            arguments.append(contentsOf: [pattern, pattern, pattern])
            return "(e.url LIKE ? ESCAPE '\\' OR f.site_url LIKE ? ESCAPE '\\' OR f.url LIKE ? ESCAPE '\\')"

        case .lang:
            let language = Locale.Language(identifier: term.value).languageCode?.identifier
            arguments.append(language ?? term.value.lowercased())
            return "e.language = ?"

        case .tag:
            // A folder is a view over a root tag, so a feed filed under a path
            // answers to it exactly as a tagged article does.
            let path = term.value
            let below = contains(path + "/", anchored: true)
            arguments.append(contentsOf: [path, below, path, below])
            return """
                (EXISTS (
                     SELECT 1 FROM tag_binding tb JOIN tag t ON t.id = tb.tag_id
                     WHERE tb.target_kind = 'entry' AND tb.target_id = e.id
                       AND (t.path = ? OR t.path LIKE ? ESCAPE '\\')
                 )
                 OR f.folder = ? OR f.folder LIKE ? ESCAPE '\\')
                """

        case .any, .title, .text, .author:
            // Reached only when the term sits under a negation, which the index
            // cannot express. The body is the one column worth searching in SQL.
            arguments.append(contains(term.value))
            return "(e.title LIKE ? ESCAPE '\\')"
        }
    }

    /// A `LIKE` pattern that matches anywhere, with the wildcards of the
    /// reader's own text escaped so they stay text.
    private static func contains(_ value: String, anchored: Bool = false) -> String {
        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return anchored ? escaped + "%" : "%" + escaped + "%"
    }

    // MARK: - The index

    /// The FTS5 expression for a subtree the index can answer.
    ///
    /// Every word is quoted, so a reader typing `NEAR(` or `^` searches for it
    /// rather than instructing the index with it. The only operators in the
    /// expression are the ones the grammar put there.
    static func matchExpression(_ node: QueryNode) -> String? {
        switch node {
        case .term(let term):
            guard term.isIndexed else { return nil }
            let quoted = "\"" + term.value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let phrase = term.isPrefix ? quoted + "*" : quoted

            return switch term.field {
            case .title: "{title}:\(phrase)"
            case .text: "{excerpt body}:\(phrase)"
            case .author: "{author}:\(phrase)"
            default: phrase
            }

        case .and(let children):
            let parts = children.compactMap(matchExpression)
            guard parts.count == children.count, !parts.isEmpty else { return nil }
            return "(" + parts.joined(separator: " AND ") + ")"

        case .or(let children):
            let parts = children.compactMap(matchExpression)
            guard parts.count == children.count, !parts.isEmpty else { return nil }
            return "(" + parts.joined(separator: " OR ") + ")"

        case .all, .state, .date, .not:
            return nil
        }
    }
}
