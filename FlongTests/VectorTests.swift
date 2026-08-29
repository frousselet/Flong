//
//  VectorTests.swift
//  FlongTests
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CloudKit
import Foundation
import GRDB
import NaturalLanguage
import Testing

@testable import Flong

@Suite("Vectors")
struct ArticleVectorTests {
    private func vector(_ values: [Float], model: String = "nl.sentence.fr", revision: Int = 1) -> ArticleVector {
        ArticleVector(model: model, revision: revision, values: values)
    }

    @Test("A vector is stored with a length of one, so a dot product is a cosine")
    func normalization() {
        let vector = vector([3, 4, 0])
        let length = sqrt(vector.values.reduce(0) { $0 + $1 * $1 })

        #expect(abs(length - 1) < 0.0001)
        #expect(abs(vector.similarity(to: vector) - 1) < 0.0001)
    }

    @Test("Opposite directions are as far apart as directions get")
    func similarity() {
        let east = vector([1, 0])
        let north = vector([0, 1])
        let west = vector([-1, 0])

        #expect(abs(east.similarity(to: north)) < 0.0001)
        #expect(east.similarity(to: west) < -0.99)
        #expect(east.similarity(to: vector([2, 0])) > 0.99)
    }

    @Test("A vector from another model is never compared, only ignored")
    func modelMismatch() {
        let mine = vector([1, 0, 0])
        let otherModel = vector([1, 0, 0], model: "nl.sentence.en")
        let otherRevision = vector([1, 0, 0], revision: 2)

        #expect(!mine.isComparable(to: otherModel))
        #expect(!mine.isComparable(to: otherRevision))
        #expect(!mine.isComparable(to: vector([1, 0])))

        // A comparison that cannot be made returns nothing, never nonsense.
        #expect(mine.similarity(to: otherRevision) == 0)
    }

    @Test("Quantizing to eight bits costs a thousandth and saves three quarters")
    func quantization() throws {
        let values = (0..<512).map { _ in Float.random(in: -1...1) }
        let original = vector(values)

        let data = original.quantized()
        let restored = try #require(ArticleVector.dequantized(data, model: original.model, revision: 1))

        #expect(data.count == 512)
        #expect(data.count == values.count * MemoryLayout<Float>.size / 4)
        #expect(original.similarity(to: restored) > 0.9999)
    }

    @Test("A quantized vector of nothing is nothing")
    func emptyQuantization() {
        #expect(ArticleVector.dequantized(Data(), model: "nl.sentence.fr", revision: 1) == nil)
    }
}

/// Whether this machine has the model. A simulator often does not, and an
/// article in a language the system cannot embed is a case the application
/// handles rather than a case a test may pretend away.
private var hasFrenchEmbedding: Bool { NLEmbedding.sentenceEmbedding(for: .french) != nil }

@Suite("Embedding")
struct EmbedderTests {
    private let embedder = Embedder()

    @Test("An article becomes a vector that says what it is about", .enabled(if: hasFrenchEmbedding))
    func embedding() throws {
        let calendar = embedder.vector(
            title: "Une réforme du calendrier scolaire",
            text: "Le ministère envisage de décaler la rentrée de septembre à la mi-août.",
            language: "fr"
        )
        let school = embedder.vector(
            title: "La rentrée scolaire décalée",
            text: "Les académies pilotes commenceront à la mi-août.",
            language: "fr"
        )
        let typography = embedder.vector(
            title: "Pourquoi les grotesques reviennent",
            text: "Les caractères sans empattement de la fin du dix-neuvième siècle reprennent leur place.",
            language: "fr"
        )

        let first = try #require(calendar)
        let second = try #require(school)
        let third = try #require(typography)

        #expect(first.model == "nl.sentence.fr")
        #expect(first.dimensions > 0)
        // Two articles about the same thing are closer than two about different
        // things. That is the only property worth asserting about a model
        // somebody else trained.
        #expect(first.similarity(to: second) > first.similarity(to: third))
    }

    @Test("A language the system cannot embed is not an error")
    func unsupportedLanguage() {
        #expect(embedder.vector(title: nil, text: "", language: "fr") == nil)
        #expect(embedder.vector(title: nil, text: "Text", language: "zxx") == nil)
    }

    @Test("This device knows which vectors it may trust", .enabled(if: hasFrenchEmbedding))
    func currentModel() throws {
        let revision = NLEmbedding.currentSentenceEmbeddingRevision(for: .french)
        #expect(embedder.isCurrent(model: "nl.sentence.fr", revision: revision))
        #expect(!embedder.isCurrent(model: "nl.sentence.fr", revision: revision + 100))
        #expect(!embedder.isCurrent(model: "some.other.model", revision: revision))
    }
}

@Suite("Vectors in the store")
struct VectorStoreTests {
    private let database: AppDatabase
    private let library: LibraryStore
    private let vectors: VectorStore
    private let feed: Feed
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() async throws {
        database = try AppDatabase.inMemory()
        library = LibraryStore(database)
        vectors = VectorStore(database)
        feed = try await SubscriptionStore(database).subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "A Feed")
        ).feed
    }

    @discardableResult
    private func keep(_ title: String, text: String) async throws -> LibraryItem {
        var entry = Entry(
            feedID: feed.id,
            guid: "urn:example:\(title)",
            title: title,
            language: "fr",
            publishedAt: now
        )
        entry.hasMedia = false

        try await database.writer.write { db in
            try entry.insert(db)
            try EntryBody(entryID: entry.id, sanitizedHTML: "<p>\(text)</p>", plainText: text).insert(db)
        }
        let change = try await library.setStarred([entry.id], to: true, at: now)
        return change.kept[0]
    }

    @Test("A kept article without a vector is one that needs one")
    func outstanding() async throws {
        try await keep("Une réforme", text: "Le ministère envisage un décalage de la rentrée scolaire.")

        #expect(try await vectors.outstandingCount() == 1)
        #expect(try await vectors.itemsNeedingVectors().count == 1)
    }

    @Test("Vectorizing writes the vector and the pair that validates it", .enabled(if: hasFrenchEmbedding))
    func vectorizing() async throws {
        let item = try await keep("Une réforme", text: "Le ministère envisage un décalage de la rentrée scolaire.")

        let written = try await vectors.vectorize([item])

        #expect(written == 1)
        let stored = try #require(try await library.item(id: item.id))
        #expect(stored.vector != nil)
        #expect(stored.vectorModel == "nl.sentence.fr")
        #expect(stored.vectorRevision != nil)
        #expect(try await vectors.outstandingCount() == 0)
    }

    @Test("A vector from a revision this device does not run is done again")
    func staleVector() async throws {
        let item = try await keep("Une réforme", text: "Le ministère envisage un décalage.")

        try await database.writer.write { db in
            var stored = try LibraryItem.fetchOne(db, key: item.id)!
            stored.vector = Data(repeating: 128, count: 512)
            stored.vectorModel = "nl.sentence.fr"
            stored.vectorRevision = "999999"
            try stored.update(db)
        }

        #expect(try await vectors.outstandingCount() == 1)
    }

    @Test("The library answers what it means, not only what it says", .enabled(if: hasFrenchEmbedding))
    func semanticSearch() async throws {
        let school = try await keep(
            "Une réforme du calendrier scolaire",
            text: "Le ministère envisage de décaler la rentrée de septembre à la mi-août."
        )
        try await keep(
            "Pourquoi les grotesques reviennent",
            text: "Les caractères sans empattement de la fin du dix-neuvième siècle reprennent leur place."
        )
        try await vectors.vectorize(try await vectors.itemsNeedingVectors())

        let matches = try await vectors.semanticMatches(for: "la rentrée des classes est repoussée")

        // The article about the school year comes first, without sharing a word
        // with the question.
        #expect(matches.first == school.id)
    }
}
