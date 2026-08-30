//
//  ArticleCollectionTests.swift
//  FlongTests
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import Testing

@testable import Flong

/// The three natures of a collection, and what each of them actually stores.
///
/// That is the whole distinction : a built-in one stores a column, a made one
/// stores a binding, a dynamic one stores a sentence. The last is the one worth
/// guarding, since a dynamic collection that quietly started writing bindings
/// would cost a record per article and nobody would notice until the budget
/// was gone.
@Suite("The squares on the collections page")
struct ArticleCollectionTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let articles: ArticleStore
    private let collections: CollectionStore
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
        articles = ArticleStore(database)
        collections = CollectionStore(database)
    }

    private func feed(_ address: String, title: String) async throws -> Feed {
        try await subscriptions.subscribe(to: Subscription(address: address, title: title)).feed
    }

    @discardableResult
    private func article(_ title: String, in feed: Feed, image: String? = nil) async throws -> UUID {
        var stored = Entry(
            feedID: feed.id,
            guid: "urn:example:\(title)",
            url: URL(string: "https://example.com/\(title)"),
            title: title,
            publishedAt: now,
            receivedAt: now
        )
        stored.imageURL = image.flatMap(URL.init(string:))
        try await database.writer.write { db in try stored.insert(db) }
        return stored.id
    }

    // MARK: - Made article by article

    @Test("A made collection holds what the reader put in it, and gives it back")
    func made() async throws {
        let paper = try await feed("https://a.example.com/f.xml", title: "Le Quotidien")
        let filed = try await article("Les macros Swift", in: paper, image: "https://example.com/a.jpg")
        try await article("Une réforme du calendrier", in: paper)

        #expect(try await collections.create("Typographie") == "Typographie")
        try await collections.add([filed], to: "Typographie")

        let made = try #require(await collections.made().first)
        #expect(made.kind == .made("Typographie"))
        #expect(made.count == 1)
        #expect(made.cover?.absoluteString == "https://example.com/a.jpg")
        #expect(try await articles.summaries(in: .made("Typographie")).map(\.title) == ["Les macros Swift"])
    }

    @Test("An article is in as many collections as the reader filed it in")
    func filedTwice() async throws {
        let paper = try await feed("https://a.example.com/f.xml", title: "Le Quotidien")
        let filed = try await article("Les macros Swift", in: paper)

        _ = try await collections.create("Typographie")
        _ = try await collections.create("À lire")
        try await collections.add([filed], to: "Typographie")
        try await collections.add([filed], to: "À lire")

        #expect(try await collections.collections(of: filed).sorted() == ["Typographie", "À lire"].sorted())
    }

    @Test("Taking an article out of a collection leaves the article where it is")
    func unfiled() async throws {
        let paper = try await feed("https://a.example.com/f.xml", title: "Le Quotidien")
        let filed = try await article("Les macros Swift", in: paper)

        _ = try await collections.create("Typographie")
        try await collections.add([filed], to: "Typographie")
        try await collections.remove([filed], from: "Typographie")

        #expect(try await collections.collections(of: filed).isEmpty)
        #expect(try await articles.summaries(.all, now: now).count == 1)
    }

    // MARK: - Described rather than filled

    @Test("A dynamic collection holds whatever answers it, and holds no list")
    func dynamic() async throws {
        let paper = try await feed("https://a.example.com/f.xml", title: "Le Quotidien")
        try await article("Une réforme du calendrier", in: paper)
        try await article("Les macros Swift", in: paper)

        #expect(try await collections.createDynamic("Calendrier", matching: "title:calendrier") == "Calendrier")

        let made = try #require(await collections.dynamic(now: now).first)
        #expect(made.kind == .dynamic("Calendrier"))
        // Counted by asking the articles, since a dynamic collection keeps no
        // list : a number written down would go stale the next time anything
        // arrived.
        #expect(made.count == 1)

        // And it follows what arrives, with nobody filing anything.
        try await article("Le calendrier scolaire", in: paper)
        #expect(try await collections.dynamic(now: now).first?.count == 2)
    }

    @Test("A description nothing can be made of is refused where it was written")
    func unusableDescription() async throws {
        #expect(try await collections.createDynamic("Vide", matching: "   ") == nil)
        #expect(try await collections.dynamic(now: now).isEmpty)
    }

    @Test("What a dynamic collection keeps is the description, and only that")
    func onlyTheDescription() async throws {
        let paper = try await feed("https://a.example.com/f.xml", title: "Le Quotidien")
        try await article("Une réforme", in: paper)

        _ = try await collections.createDynamic("Tout", matching: "title:réforme")

        // Nothing was bound to anything : this is the whole reason a dynamic
        // collection costs one small record however many articles answer it.
        let bindings = try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tag_binding") ?? 0
        }
        #expect(bindings == 0)
        #expect(try await collections.query(of: "Tout") == "title:réforme")
    }
}
