//
//  VectorStore.swift
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
import OSLog

/// The vectors of what the reader marked, and the search they answer.
///
/// Only what the reader marked is vectorized. Section 11 is explicit that the
/// rest of the stream is
/// not : a hundred and twenty five thousand vectors would cost hours of device
/// time to compute and would answer a question nobody asks of a cache.
nonisolated struct VectorStore: Sendable {
    /// How many are computed in one go, which is what makes the work resumable.
    static let batchSize = 50

    /// Written where a model name should be when the system has none for that
    /// language.
    ///
    /// Without it the article has no vector, the queue offers it again, and the
    /// job asks the same impossible question for ever. This says the question
    /// was asked and answered.
    static let noModel = "none"

    private let database: AppDatabase
    private let embedder: Embedder

    init(_ database: AppDatabase, embedder: Embedder = Embedder()) {
        self.database = database
        self.embedder = embedder
    }

    // MARK: - Computing

    /// The marked articles whose vector is missing or was made by another model.
    ///
    /// A vector from a model this device no longer runs is worse than none : it
    /// would be compared against vectors it has nothing in common with.
    ///
    /// **Only what the reader marked.** Section 11 says the rest of the stream
    /// is not vectorized, and it matters more than it did : the stream was
    /// thirty days of articles and is now every article there has ever been, so
    /// asking for all of them would be embedding a hundred thousand pieces to
    /// answer questions about the few hundred somebody chose.
    @concurrent
    func itemsNeedingVectors(limit: Int = VectorStore.batchSize) async throws -> [Entry] {
        let candidates = try await database.writer.read { db in
            try Entry.fetchAll(
                db,
                sql: """
                    SELECT * FROM entry
                    WHERE is_hidden = 0 AND duplicate_of IS NULL
                      AND (is_starred = 1 OR COALESCE(annotation, '') <> ''
                           OR id IN (SELECT target_id FROM tag_binding WHERE target_kind = 'entry'))
                    ORDER BY received_at DESC
                    """
            )
        }

        return
            candidates
            .filter { item in
                // Already answered, even when the answer was that there is no
                // model for this language.
                guard item.vectorModel != Self.noModel else { return false }

                guard let model = item.vectorModel, let revision = item.vectorRevision.flatMap(Int.init),
                    item.vector != nil
                else { return true }
                return !embedder.isCurrent(model: model, revision: revision)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Computes and stores the vectors of a batch.
    @discardableResult
    @concurrent
    func vectorize(_ items: [Entry]) async throws -> Int {
        // Computed before the transaction opens, and handed in as one value :
        // embedding is the slow part, and a write transaction is the last place
        // to do slow things.
        // The text is beside the article rather than on it, so it is fetched
        // once for the batch instead of once per article.
        let texts: [UUID: String] = try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT entry_id AS id, plain_text AS text FROM entry_body
                    WHERE entry_id IN (\(databaseQuestionMarks(count: items.count)))
                    """,
                arguments: StatementArguments(items.map { $0.id.databaseValue })
            )
            .reduce(into: [:]) { all, row in
                if let text = row["text"] as String? { all[row["id"] as UUID] = text }
            }
        }

        let vectors: [UUID: ArticleVector] = items.reduce(into: [:]) { result, item in
            result[item.id] = embedder.vector(for: item, text: texts[item.id])
        }
        let ids = items.map(\.id)

        return try await database.writer.write { db in
            var written = 0
            for id in ids {
                guard var item = try Entry.fetchOne(db, key: id) else { continue }
                let vector = vectors[id]

                item.vector = vector?.quantized()
                item.vectorModel = vector?.model
                item.vectorRevision = vector.map { String($0.revision) }
                try item.update(db)

                if vector != nil { written += 1 }
            }
            return written
        }
    }

    /// How many kept articles are still waiting for a vector.
    @concurrent
    func outstandingCount() async throws -> Int {
        try await itemsNeedingVectors(limit: .max).count
    }

    // MARK: - Reading

    func vector(of itemID: UUID) async throws -> ArticleVector? {
        let item = try await database.writer.read { db in try Entry.fetchOne(db, key: itemID) }
        return item.flatMap(Self.vector)
    }

    static func vector(of item: Entry) -> ArticleVector? {
        guard let data = item.vector, let model = item.vectorModel,
            let revision = item.vectorRevision.flatMap(Int.init)
        else { return nil }
        return ArticleVector.dequantized(data, model: model, revision: revision)
    }

    // MARK: - Searching

    /// How far above the crowd a similarity has to stand, in standard
    /// deviations.
    ///
    /// A fixed threshold does not work here, and measuring said so : the
    /// system's sentence embeddings put two unrelated French articles at 0.93
    /// and two about the same event at 0.92. What separates them is not the
    /// value but the **distance from the rest** : the article a question is
    /// about stands above its neighbours even when everything scores high.
    static let standardDeviations: Float = 1.5

    /// The kept articles closest in meaning to a phrase.
    ///
    /// Cosine similarity over what is marked, which needs no index structure
    /// at this scale : a few thousand vectors against one is a few million
    /// multiplications.
    func semanticMatches(for text: String, limit: Int = 50) async throws -> [UUID] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let items = try await database.writer.read { db in
            try Entry.filter(Column("vector") != nil).fetchAll(db)
        }

        // The query is embedded once per model there is. A search is
        // three words long and has no language to detect ; guessing one would
        // send a French question to an English model, which comes back with
        // nothing rather than with an error.
        var queries: [String: ArticleVector] = [:]
        for model in Set(items.compactMap(\.vectorModel)) {
            queries[model] = embedder.vector(text: text, model: model)
        }

        let scored = items.compactMap { item -> (UUID, Float)? in
            guard let vector = Self.vector(of: item),
                let query = queries[vector.model],
                vector.isComparable(to: query)
            else { return nil }

            return (item.id, vector.similarity(to: query))
        }
        guard scored.count > 2 else { return scored.map(\.0) }

        let similarities = scored.map(\.1)
        let mean = similarities.reduce(0, +) / Float(similarities.count)
        let variance = similarities.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(similarities.count)
        let bar = mean + Self.standardDeviations * sqrt(variance)

        return
            scored
            .filter { $0.1 >= bar }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
