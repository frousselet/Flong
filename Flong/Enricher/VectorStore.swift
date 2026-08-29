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

/// The vectors of the library, and the search they answer.
///
/// Only the library is vectorized. Section 11 is explicit that the stream is
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

    /// The kept articles whose vector is missing or was made by another model.
    ///
    /// A vector from a model this device no longer runs is worse than none : it
    /// would be compared against vectors it has nothing in common with.
    func itemsNeedingVectors(limit: Int = VectorStore.batchSize) async throws -> [LibraryItem] {
        let candidates = try await database.writer.read { db in
            try LibraryItem.order(Column("promoted_at").desc).fetchAll(db)
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
    func vectorize(_ items: [LibraryItem]) async throws -> Int {
        // Computed before the transaction opens, and handed in as one value :
        // embedding is the slow part, and a write transaction is the last place
        // to do slow things.
        let vectors: [UUID: ArticleVector] = items.reduce(into: [:]) { result, item in
            result[item.id] = embedder.vector(for: item)
        }
        let ids = items.map(\.id)

        return try await database.writer.write { db in
            var written = 0
            for id in ids {
                guard var item = try LibraryItem.fetchOne(db, key: id) else { continue }
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
    func outstandingCount() async throws -> Int {
        try await itemsNeedingVectors(limit: .max).count
    }

    // MARK: - Reading

    func vector(of itemID: UUID) async throws -> ArticleVector? {
        let item = try await database.writer.read { db in try LibraryItem.fetchOne(db, key: itemID) }
        return item.flatMap(Self.vector)
    }

    static func vector(of item: LibraryItem) -> ArticleVector? {
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
    /// Cosine similarity over the whole library, which needs no index structure
    /// at this scale : a few thousand vectors against one is a few million
    /// multiplications.
    func semanticMatches(for text: String, limit: Int = 50) async throws -> [UUID] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let items = try await database.writer.read { db in
            try LibraryItem.filter(Column("vector") != nil).fetchAll(db)
        }

        // The query is embedded once per model the library holds. A search is
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
