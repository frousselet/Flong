//
//  AuthorStoreTests.swift
//  FlongTests
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CloudKit
import Foundation
import GRDB
import Testing

@testable import Flong

@Suite("The writers, and the ones the reader singled out")
struct AuthorStoreTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let articles: ArticleStore
    private let collections: CollectionStore
    private let authors: AuthorStore
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
        articles = ArticleStore(database)
        collections = CollectionStore(database)
        authors = AuthorStore(database)
    }

    @discardableResult
    private func article(_ title: String, by author: String?, image: URL? = nil) async throws -> Entry {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.com/paper.xml", title: "Le Papier")
        ).feed

        var entry = Entry(
            feedID: feed.id,
            guid: "urn:\(title)",
            title: title,
            author: author,
            receivedAt: now,
            imageURL: image
        )
        entry.hasMedia = false
        try await database.writer.write { db in try entry.insert(db) }
        return entry
    }

    // MARK: - The spelling

    @Test("A byline is trimmed and its whitespace collapsed, and an empty one is nobody")
    func spelling() {
        #expect(Author.name(from: "  Jean Dupont  ") == "Jean Dupont")
        // What a pretty-printed feed hands over when the name sits on its own
        // line inside an `author` element.
        #expect(Author.name(from: "\n      Jean\n      Dupont\n   ") == "Jean Dupont")
        #expect(Author.name(from: "   ") == nil)
        #expect(Author.name(from: "") == nil)
        #expect(Author.name(from: nil) == nil)
    }

    @Test("The spelling is normalized on the way in, so one writer is one row")
    func normalizedOnTheWayIn() async throws {
        try await article("Un", by: "  Marie Curie ")
        try await article("Deux", by: "Marie\n  Curie")

        let found = try await authors.all()
        #expect(found.map(\.name) == ["Marie Curie"])
        #expect(found.first?.count == 2)
    }

    @Test("Two spellings are two writers, since nothing here guesses at a person")
    func nothingIsGuessed() async throws {
        try await article("Un", by: "Marie Curie")
        try await article("Deux", by: "M. Curie")

        #expect(try await authors.all().map(\.name) == ["M. Curie", "Marie Curie"])
    }

    @Test("An article nobody signed puts nobody in the list")
    func unsigned() async throws {
        try await article("Un", by: nil)
        try await article("Deux", by: "")

        #expect(try await authors.all().isEmpty)
    }

    @Test("The names come back in the reader's order and not in byte order")
    func ordering() async throws {
        try await article("Un", by: "Zola")
        try await article("Deux", by: "Éluard")

        // Byte order would put `Zola` first : a capital E with an acute accent
        // starts with a higher byte than a Z.
        #expect(try await authors.all().map(\.name) == ["Éluard", "Zola"])
    }

    // MARK: - The favourite

    @Test("Singling a writer out marks them and stars nothing")
    func favouriting() async throws {
        let entry = try await article("Un", by: "Marie Curie")
        try await authors.setFavourite("Marie Curie", true)

        #expect(try await authors.isFavourite("Marie Curie"))
        #expect(try await authors.all().first?.isFavourite == true)
        #expect(try await authors.favourites() == ["Marie Curie"])

        // A judgement about the person, and never about the piece : section 13
        // keeps the star a judgement about the article itself.
        let reread = try await database.writer.read { db in try Entry.fetchOne(db, key: entry.id) }
        #expect(reread?.isStarred == false)
    }

    @Test("Taking the favourite back leaves the writer in the list and nothing else behind")
    func unfavouriting() async throws {
        try await article("Un", by: "Marie Curie")
        try await authors.setFavourite("Marie Curie", true)
        try await authors.setFavourite("Marie Curie", false)

        #expect(try await authors.favourites().isEmpty)
        #expect(try await authors.all().map(\.name) == ["Marie Curie"])
        #expect(try await authors.all().first?.isFavourite == false)
    }

    @Test("Singling the same writer out twice is singling them out once")
    func idempotent() async throws {
        try await article("Un", by: "Marie Curie")
        try await authors.setFavourite("Marie Curie", true)
        try await authors.setFavourite("Marie Curie", true)

        #expect(try await authors.favourites() == ["Marie Curie"])
    }

    @Test("A favourite nothing is signed by is still in the list, with a count of nothing")
    func aFavouriteWithNothingToTheirName() async throws {
        try await article("Un", by: "Zola")
        // What a favourite arriving from another device before its articles
        // looks like, and what a purge leaves behind.
        try await authors.setFavourite("Marie Curie", true)

        let found = try await authors.all()
        #expect(found.map(\.name) == ["Marie Curie", "Zola"])
        #expect(found.first?.count == 0)
        #expect(found.first?.isFavourite == true)

        let one = try #require(try await authors.author(named: "Marie Curie"))
        #expect(one.count == 0)
        #expect(one.isFavourite)
    }

    @Test("A name nothing and nobody carries has no page")
    func nobody() async throws {
        try await article("Un", by: "Zola")
        #expect(try await authors.author(named: "Marie Curie") == nil)
    }

    // MARK: - The two squares

    @Test("The authors square counts people, and the favourites square counts articles")
    func squares() async throws {
        try await article("Un", by: "Marie Curie", image: URL(string: "https://example.com/1.jpg"))
        try await article("Deux", by: "Marie Curie")
        try await article("Trois", by: "Zola")
        try await authors.setFavourite("Marie Curie", true)

        let found = try await authors.collections()

        let people = try #require(found.first { $0.kind == .builtIn(.authors) })
        #expect(people.count == 2)
        #expect(people.cover == URL(string: "https://example.com/1.jpg"))

        let favourites = try #require(found.first { $0.kind == .builtIn(.favouriteAuthors) })
        #expect(favourites.count == 2)
    }

    @Test("Neither square is drawn when there is nothing in it")
    func emptySquares() async throws {
        try await article("Un", by: nil)
        #expect(try await authors.collections().isEmpty)

        try await article("Deux", by: "Zola")
        // The writers are there ; nobody has been singled out.
        #expect(try await authors.collections().map(\.kind) == [.builtIn(.authors)])
    }

    @Test("The favourite authors square holds what the favourites signed, and only that")
    func favouriteAuthorsCollection() async throws {
        try await article("Un", by: "Marie Curie")
        try await article("Deux", by: "Zola")
        try await authors.setFavourite("Marie Curie", true)

        let held = try await articles.summaries(in: .builtIn(.favouriteAuthors))
        #expect(held.map(\.title) == ["Un"])
    }

    @Test("The authors square answers no articles, since it opens on people")
    func theAuthorsSquareHoldsNoArticles() async throws {
        try await article("Un", by: "Marie Curie")
        #expect(try await articles.summaries(in: .builtIn(.authors)).isEmpty)
    }

    @Test("One writer's page holds what that writer signed")
    func oneWriter() async throws {
        try await article("Un", by: "Marie Curie")
        try await article("Deux", by: "Zola")

        #expect(try await articles.summaries(.author("Marie Curie")).map(\.title) == ["Un"])
        #expect(try await articles.summaries(.author("Personne")).isEmpty)
    }

    @Test("The squares reach the collections page in the order of the page")
    func theOrderOfThePage() async throws {
        let entry = try await article("Un", by: "Marie Curie")
        try await articles.setStarred([entry.id], to: true)
        try await authors.setFavourite("Marie Curie", true)

        let built = try await collections.builtIn().compactMap { collection -> ArticleCollection.BuiltIn? in
            if case .builtIn(let kind) = collection.kind { kind } else { nil }
        }
        #expect(built == [.starred, .favouriteAuthors, .authors])
    }
}

@Suite("A favourite author between two devices")
struct FavouriteAuthorSyncTests {
    private let zone = CKRecordZone.ID(zoneName: SyncRecords.zoneName, ownerName: CKCurrentUserDefaultName)

    private func device() throws -> (AppDatabase, AuthorStore, SyncPayload) {
        let database = try AppDatabase.inMemory()
        return (database, AuthorStore(database), SyncPayload(database, zone: zone))
    }

    @Test("A record is named after the writer, so two devices write one record between them")
    func namedAfterTheWriter() {
        #expect(
            SyncRecords.name(forFavouriteAuthor: "Marie Curie")
                == SyncRecords.name(forFavouriteAuthor: "Marie Curie")
        )
        #expect(SyncRecords.name(forFavouriteAuthor: "Marie Curie") != SyncRecords.name(forFavouriteAuthor: "Zola"))
        #expect(SyncRecords.name(forFavouriteAuthor: "Marie Curie").hasPrefix("author-"))
    }

    @Test("A favourite reaches the other device, writer unknown there or not")
    func itTravels() async throws {
        let (_, here, sending) = try device()
        let (_, there, receiving) = try device()

        try await here.setFavourite("Marie Curie", true)
        let records = try await sending.everything()
            .filter { $0.recordType == SyncRecords.RecordType.favouriteAuthor }
        #expect(records.count == 1)

        try await receiving.apply(records)
        #expect(try await there.favourites() == ["Marie Curie"])
    }

    @Test("The `no` travels too : a deleted record takes the favourite back")
    func theNoTravels() async throws {
        let (_, there, receiving) = try device()
        try await there.setFavourite("Marie Curie", true)

        try await receiving.apply(deletions: [SyncRecords.name(forFavouriteAuthor: "Marie Curie")])
        #expect(try await there.favourites().isEmpty)
    }

    @Test("A record the engine asks for by name is the one it gets")
    func askedForByName() async throws {
        let (_, here, payload) = try device()
        try await here.setFavourite("Zola", true)

        let name = SyncRecords.name(forFavouriteAuthor: "Zola")
        let records = try await payload.records(named: [name])
        #expect(SyncRecords.favouriteAuthor(from: try #require(records[name])) == "Zola")
    }
}
