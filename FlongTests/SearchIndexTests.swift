//
//  SearchIndexTests.swift
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

@Suite("Search index")
struct SearchIndexTests {
    private let database: AppDatabase
    private let index: SearchIndex
    private let feed: Feed

    init() async throws {
        database = try AppDatabase.inMemory()
        index = SearchIndex(database)
        feed = try await SubscriptionStore(database).subscribe(
            to: Subscription(address: "https://a.example.com/f.xml", title: "A Feed")
        ).feed
    }

    @discardableResult
    private func add(title: String, excerpt: String? = nil, author: String? = nil, body: String? = nil) async throws
        -> Entry
    {
        var entry = Entry(feedID: feed.id, guid: "urn:example:\(title)", title: title, excerpt: excerpt, author: author)
        entry.hasMedia = false

        try await database.writer.write { db in
            try entry.insert(db)
            if let body {
                try EntryBody(entryID: entry.id, sanitizedHTML: "<p>\(body)</p>", plainText: body).insert(db)
            }
        }
        return entry
    }

    /// The identifiers the index gives back for a raw FTS5 query.
    private func matches(_ query: String) async throws -> [UUID] {
        try await database.writer.read { db in
            try UUID.fetchAll(
                db,
                sql: """
                    SELECT e.id FROM entry_fts f JOIN entry e ON e.rowid = f.rowid
                    WHERE entry_fts MATCH ? ORDER BY rank
                    """,
                arguments: [query]
            )
        }
    }

    // MARK: - Staying in step

    @Test("An article is indexed as it is stored")
    func indexingOnInsert() async throws {
        let entry = try await add(title: "Une réforme du calendrier")

        #expect(try await matches("réforme") == [entry.id])
        #expect(try await index.count() == 1)
    }

    @Test("A body arriving after its article is indexed too")
    func indexingABody() async throws {
        let entry = try await add(title: "Sans rapport", body: "Le corps parle de typographie")

        #expect(try await matches("typographie") == [entry.id])
        #expect(try await index.count() == 1)
    }

    @Test("Every column of the article is searchable")
    func indexedColumns() async throws {
        let entry = try await add(
            title: "Titre",
            excerpt: "Un chapeau distinctif",
            author: "Camille Dupuis",
            body: "Un corps reconnaissable"
        )

        #expect(try await matches("chapeau") == [entry.id])
        #expect(try await matches("Dupuis") == [entry.id])
        #expect(try await matches("reconnaissable") == [entry.id])
    }

    @Test("Rewriting an article rewrites its index entry")
    func indexingOnUpdate() async throws {
        var entry = try await add(title: "Premier titre", body: "Premier corps")

        entry.title = "Titre corrigé"
        try await database.writer.write { db in
            try entry.update(db)
            try EntryBody(entryID: entry.id, plainText: "Corps corrigé").upsert(db)
        }

        #expect(try await matches("premier").isEmpty)
        #expect(try await matches("corrigé") == [entry.id])
        #expect(try await index.count() == 1)
    }

    @Test("An article that goes takes its index entry with it")
    func indexingOnDelete() async throws {
        let entry = try await add(title: "Éphémère", body: "Un corps")
        try await database.writer.write { db in _ = try entry.delete(db) }

        #expect(try await matches("éphémère").isEmpty)
        #expect(try await index.count() == 0)
        #expect(try await index.isConsistent())
    }

    @Test("A feed that goes takes its articles out of the index")
    func indexingOnCascade() async throws {
        try await add(title: "Un article", body: "Un corps")
        try await SubscriptionStore(database).unsubscribe(feed.id)

        #expect(try await index.count() == 0)
        #expect(try await index.isConsistent())
    }

    // MARK: - Matching

    @Test(
        "Accents and endings do not have to be spelled the way the article did",
        arguments: [
            ("reforme", "Une réforme du calendrier scolaire"),
            ("RÉFORME", "Une réforme du calendrier scolaire"),
            ("calendrier", "Une réforme des calendriers scolaires"),
            ("Nimes", "Une soirée à Nîmes"),
        ]
    )
    func matching(query: String, title: String) async throws {
        let entry = try await add(title: title)
        #expect(try await matches(query) == [entry.id])
    }

    @Test("A phrase matches in order, and not out of it")
    func phrases() async throws {
        let entry = try await add(title: "Le calendrier scolaire et ses réformes")

        #expect(try await matches("\"calendrier scolaire\"") == [entry.id])
        #expect(try await matches("\"scolaire calendrier\"").isEmpty)
    }

    @Test("A prefix finds what has only been typed halfway")
    func prefixes() async throws {
        let entry = try await add(title: "Typographie et empattements")

        #expect(try await matches("typo*") == [entry.id])
    }

    // MARK: - Rebuilding

    @Test("The index can be thrown away and built again")
    func rebuilding() async throws {
        for index in 0..<20 {
            try await add(title: "Article \(index)", body: "Un corps numéro \(index)")
        }

        try await database.writer.write { db in
            try db.execute(sql: "INSERT INTO entry_fts(entry_fts) VALUES('delete-all')")
        }
        #expect(try await index.count() == 0)
        #expect(try await index.isConsistent() == false)

        let rebuilt = try await index.rebuild()

        #expect(rebuilt == 20)
        #expect(try await index.isConsistent())
        #expect(try await matches("numéro").count == 20)
    }

    @Test("Compacting the index leaves it answering the same")
    func optimizing() async throws {
        let entry = try await add(title: "Une réforme", body: "Un corps")
        try await index.optimize()

        #expect(try await matches("réforme") == [entry.id])
    }
}

@Suite("Language detection")
struct LanguageDetectionTests {
    @Test("A stated language is believed, and normalized")
    func statedLanguage() {
        #expect(LanguageDetection.language(stated: "fr-FR", title: nil, body: nil) == "fr")
        #expect(LanguageDetection.language(stated: "EN", title: nil, body: nil) == "en")
    }

    @Test("A feed that states nothing is read")
    func detection() {
        let french = """
            Le ministère envisage de décaler la rentrée de septembre à la mi-août dans trois académies pilotes,
            une décision qui ne fait pas l'unanimité chez les enseignants.
            """
        let english = """
            The department is considering moving the start of the school year from September to mid August in
            three pilot regions, a decision teachers have not welcomed.
            """

        #expect(LanguageDetection.language(stated: nil, title: nil, body: french) == "fr")
        #expect(LanguageDetection.language(stated: nil, title: nil, body: english) == "en")
    }

    @Test("Too little text is no reason to guess")
    func shortText() {
        #expect(LanguageDetection.language(of: "Bonjour") == nil)
        #expect(LanguageDetection.language(stated: nil, title: "Hello", body: nil) == nil)
    }
}
