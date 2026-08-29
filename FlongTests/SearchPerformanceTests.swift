//
//  SearchPerformanceTests.swift
//  FlongTests
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import Testing

@testable import Flong

/// The targets of section 11 of the specification, against the corpus it names.
///
/// Building 125 000 articles takes a minute, so the suite is opt in : it runs
/// when `FLONG_PERFORMANCE` is set, which is what continuous integration will
/// set once there is any. Nothing else in the suite is slow, and nobody should
/// have to wait for this to find out that a parser test broke.
///
/// ```bash
/// FLONG_PERFORMANCE=1 xcodebuild test -project Flong.xcodeproj -scheme Flong \
///   -destination 'platform=macOS' -only-testing:FlongTests/SearchPerformanceTests
/// ```
@Suite("Search performance", .enabled(if: ProcessInfo.processInfo.environment["FLONG_PERFORMANCE"] != nil))
struct SearchPerformanceTests {
    private static let corpusSize = 125_000
    private static let batchSize = 2_000

    @Test("The corpus of the specification meets its targets", .timeLimit(.minutes(10)))
    func targets() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let database = try AppDatabase.onDisk(folder: folder)
        let feed = try await SubscriptionStore(database).subscribe(
            to: Subscription(address: "https://feeds.example.com/perf.xml", title: "Corpus")
        ).feed

        // Ingestion, which is an insert and the trigger that indexes it.
        let written = ContinuousClock().measure {
            try? fill(database, feed: feed)
        }
        let perArticle = written / Self.corpusSize
        print("Ingested \(Self.corpusSize) articles in \(written), \(perArticle) each")
        #expect(perArticle < .milliseconds(10), "Indexing one article at ingestion must stay under 10 ms")

        let articles = ArticleStore(database)
        #expect(try await articles.count(.all) == Self.corpusSize)

        // A lexical query over the whole corpus.
        for query in ["réforme", "title:calendrier", "\"macros swift\"", "concurrence OR typographie"] {
            let node = QueryParser.parse(query)
            var results: [ArticleSummary] = []

            let elapsed = try await ContinuousClock().measure {
                results = try await articles.summaries(.all, matching: node, limit: 100)
            }
            print("\(query) : \(results.count) results in \(elapsed)")
            #expect(elapsed < .milliseconds(100), "A lexical query over the corpus must stay under 100 ms : \(query)")
        }

        // A full rebuild of the index.
        let index = SearchIndex(database)
        let rebuilt = try await ContinuousClock().measure {
            _ = try await index.rebuild()
        }
        print("Rebuilt the index in \(rebuilt)")
        #expect(rebuilt < .seconds(120), "A full rebuild must stay under two minutes")
        #expect(try await index.isConsistent())
    }

    /// Writes the corpus, in transactions of a few thousand.
    ///
    /// The text has to be shaped like a real corpus, not merely be large. A
    /// vocabulary of thirty words repeated everywhere would put every word in
    /// every article, and a query for one of them would match all 125 000 : that
    /// measures how fast a full scan ranks, which is not what anybody searches
    /// for. Words here follow the usual lopsided distribution, and the terms the
    /// test searches for are planted at known rates.
    private func fill(_ database: AppDatabase, feed: Feed) throws {
        var generator = SystemRandomNumberGenerator()
        let start = Date(timeIntervalSince1970: 1_600_000_000)

        for batch in stride(from: 0, to: Self.corpusSize, by: Self.batchSize) {
            try database.writer.writeWithoutTransaction { db in
                try db.inTransaction {
                    for offset in batch..<min(batch + Self.batchSize, Self.corpusSize) {
                        var title = Self.words(8, using: &generator)
                        var body = Self.words(140, using: &generator)

                        // Planted terms, at the rates a topical word really has.
                        if offset % 20 == 0 { body += " réforme" }  // one article in twenty
                        if offset % 50 == 0 { title += " calendrier" }  // one in fifty
                        if offset % 100 == 0 { body += " typographie" }  // one in a hundred
                        if offset % 200 == 0 { body += " macros swift" }  // one in two hundred
                        if offset % 500 == 0 { body += " concurrence" }  // one in five hundred

                        var entry = Entry(
                            feedID: feed.id,
                            guid: "urn:example:\(offset)",
                            url: URL(string: "https://example.com/\(offset)"),
                            title: title,
                            excerpt: String(body.prefix(120)),
                            author: Self.authors[offset % Self.authors.count],
                            language: "fr",
                            publishedAt: start.addingTimeInterval(Double(offset) * 60),
                            receivedAt: start.addingTimeInterval(Double(offset) * 60)
                        )
                        entry.hasMedia = false

                        try entry.insert(db)
                        try EntryBody(entryID: entry.id, sanitizedHTML: "<p>\(body)</p>", plainText: body).insert(db)
                    }
                    return .commit
                }
            }
        }
    }

    /// A few words, drawn the way words really fall : a handful used constantly,
    /// a long tail hardly ever.
    private static func words(_ count: Int, using generator: inout SystemRandomNumberGenerator) -> String {
        (0..<count)
            .map { _ in
                let rank = Int(pow(Double.random(in: 0..<1, using: &generator), 3) * Double(vocabulary.count))
                return vocabulary[min(rank, vocabulary.count - 1)]
            }
            .joined(separator: " ")
    }

    private static let authors = ["Camille Dupuis", "Alex Martin", "Dominique Roy", "Claude Bernard"]

    /// Five thousand words, the first of them the commonest.
    private static let vocabulary: [String] = {
        let common = [
            "le", "la", "les", "des", "une", "pour", "dans", "avec", "sur", "par", "que", "qui", "plus", "cette",
            "article", "lecture", "flux", "ministre", "ville", "rapport", "projet", "mesure", "public", "travail",
        ]
        let tail = (0..<5000).map { "mot\($0)" }
        return common + tail
    }()
}
