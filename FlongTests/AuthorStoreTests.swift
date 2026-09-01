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
    private func article(
        _ title: String,
        by author: String?,
        image: URL? = nil,
        from source: String = "https://feeds.papier.example.com/une.xml"
    ) async throws -> Entry {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: source, title: "Le Papier")
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
        try await database.writer.write { db in
            try entry.insert(db)
            // What every path that stores an article does : see
            // ``AuthorStore/index(_:byline:in:)``.
            try AuthorStore.index(entry.id, byline: entry.author, in: db)
        }
        return entry
    }

    // MARK: - The spelling

    @Test("A byline is trimmed and its whitespace collapsed, and an empty one is nobody")
    func spelling() {
        #expect(Author.name(from: "  Jean Dupont  ") == "Jean Dupont")
        // What a pretty-printed feed hands over when the name sits on its own
        // line inside an `author` element.
        #expect(Author.name(from: "\n      Jean\n      Dupont\n   ") == "Jean Dupont")
        #expect(Author.name(from: "Jean&nbsp;Dupont") == "Jean Dupont")
        #expect(Author.name(from: "   ") == nil)
        #expect(Author.name(from: "") == nil)
        #expect(Author.name(from: nil) == nil)
    }

    @Test("The person is taken out of the address RSS says the field holds")
    func addresses() {
        // The spelling of RSS 2.0's own example.
        #expect(Author.name(from: "lawyer@boyer.net (Lawyer Boyer)") == "Lawyer Boyer")
        #expect(Author.name(from: "\"Lawyer Boyer\" <lawyer@boyer.net>") == "Lawyer Boyer")
        #expect(Author.name(from: "Lawyer Boyer <lawyer@boyer.net>") == "Lawyer Boyer")

        // An inbox with nobody's name on it names nobody, which is the truth
        // about that article rather than a writer called `noreply`.
        #expect(Author.name(from: "noreply@example.com") == nil)
        #expect(Author.name(from: "<lawyer@boyer.net>") == nil)

        // Brackets are not stripped in general : there is no address here, and
        // what is in them may well be the thing the reader recognizes.
        #expect(Author.name(from: "Jean Dupont (Le Monde)") == "Jean Dupont (Le Monde)")
    }

    @Test("The word a publisher writes in front of every credit is not part of a name")
    func credits() {
        #expect(Author.name(from: "By Jean Dupont") == "Jean Dupont")
        #expect(Author.name(from: "by Jean Dupont") == "Jean Dupont")
        #expect(Author.name(from: "Par Marie Curie") == "Marie Curie")
        #expect(Author.name(from: "Written by Marie Curie") == "Marie Curie")
        #expect(Author.name(from: "Posted by Marie Curie") == "Marie Curie")
        #expect(Author.name(from: "Auteur : Marie Curie") == "Marie Curie")
        #expect(Author.name(from: "Author: Marie Curie") == "Marie Curie")

        // The word has to be the word, and not the first letters of a name.
        #expect(Author.name(from: "Byron Smith") == "Byron Smith")
        #expect(Author.name(from: "Parker Lewis") == "Parker Lewis")
        // Nothing follows it, so there is nobody to uncover.
        #expect(Author.name(from: "By") == "By")
    }

    @Test("A masthead stapled to a byline is not part of the byline")
    func mastheads() {
        #expect(Author.name(from: "Jean Dupont | Le Monde") == "Jean Dupont")
        #expect(Author.name(from: "By Jean Dupont | Le Monde") == "Jean Dupont")

        // A dash is left alone : it can be part of a name, and a bar cannot.
        #expect(Author.name(from: "Jean Dupont - BBC News") == "Jean Dupont - BBC News")
        #expect(Author.name(from: "Jean-Pierre Dupont") == "Jean-Pierre Dupont")
    }

    @Test("What is not somebody is nobody, and what is somebody is left alone")
    func nobodyAndEverybody() {
        #expect(Author.name(from: "-") == nil)
        #expect(Author.name(from: "--") == nil)
        #expect(Author.name(from: "https://example.com/author/jean") == nil)

        // A newsroom is what the publisher said, and deciding it is not a
        // person is a judgement rather than a fact about the spelling. The
        // capitals are left alone for the same reason : `JEAN DUPONT` and
        // `Jean Dupont` are two spellings of one person, which is a merge.
        #expect(Author.name(from: "Rédaction") == "Rédaction")
        #expect(Author.name(from: "admin") == "admin")
        #expect(Author.name(from: "JEAN DUPONT") == "JEAN DUPONT")
        #expect(Author.name(from: "J. R. R. Tolkien") == "J. R. R. Tolkien")
    }

    /// The migrations lean on this : v24 and v25 both ask the column to be
    /// whatever the current rule says, and they are only interchangeable
    /// because asking twice is asking once.
    @Test("Cleaning a byline twice cleans it once")
    func idempotentCleaning() throws {
        for raw in ["By Jean Dupont | Le Monde", "lawyer@boyer.net (Lawyer Boyer)", "  Marie  Curie "] {
            let once = try #require(Author.name(from: raw))
            #expect(Author.name(from: once) == once)
        }
    }

    @Test("The spelling is cleaned on the way in, so one writer is one row")
    func cleanedOnTheWayIn() async throws {
        try await article("Un", by: "  Marie Curie ")
        try await article("Deux", by: "Marie\n  Curie")
        try await article("Trois", by: "By Marie Curie")
        try await article("Quatre", by: "curie@example.com (Marie Curie)")
        try await article("Cinq", by: "Marie Curie | Le Papier")
        // Not a name at all : the article is signed by nobody this can name.
        try await article("Six", by: "noreply@example.com")

        let found = try await authors.all()
        #expect(found.map(\.name) == ["Marie Curie"])
        #expect(found.first?.count == 5)
    }

    // MARK: - Everybody a byline names

    @Test("One field holds a whole newsroom, and every separator publishers use is one")
    func severalPeople() {
        #expect(Author.people(in: "Claire Ancelin") == ["Claire Ancelin"])
        #expect(Author.people(in: "Claire Ancelin, Paul Rey") == ["Claire Ancelin", "Paul Rey"])
        #expect(Author.people(in: "Claire Ancelin & Paul Rey") == ["Claire Ancelin", "Paul Rey"])
        #expect(Author.people(in: "Claire Ancelin and Paul Rey") == ["Claire Ancelin", "Paul Rey"])
        #expect(Author.people(in: "Claire Ancelin AND Paul Rey") == ["Claire Ancelin", "Paul Rey"])
        #expect(Author.people(in: "Claire Ancelin et Paul Rey") == ["Claire Ancelin", "Paul Rey"])
        #expect(Author.people(in: "Ancelin; Rey; Sobral") == ["Ancelin", "Rey", "Sobral"])
        #expect(
            Author.people(in: "Claire Ancelin, Paul Rey et Yann Sobral")
                == ["Claire Ancelin", "Paul Rey", "Yann Sobral"]
        )
    }

    @Test("A comma is not a separator on its own, and the rule is applied piece by piece")
    func namesWrittenBackwards() {
        // One person written the way a directory writes them : neither half
        // holds a space, and splitting would make two halves of somebody.
        #expect(Author.people(in: "Dupont, Jean") == ["Dupont, Jean"])
        // The same rule, applied to each piece rather than to the line. Cut on
        // the semicolon first, this is two people written backwards ; cut on
        // the commas, it is four written wrong.
        #expect(Author.people(in: "Dupont, Jean; Curie, Marie") == ["Dupont, Jean", "Curie, Marie"])
    }

    @Test("The line is cleaned before it is cut, and each name after")
    func cleanedThenCut() {
        #expect(Author.people(in: "By Claire Ancelin and Paul Rey") == ["Claire Ancelin", "Paul Rey"])
        #expect(Author.people(in: "Claire Ancelin and Paul Rey | Le Monde") == ["Claire Ancelin", "Paul Rey"])
        // Two people inside one address : cutting first would leave half an
        // address on one of them.
        #expect(
            Author.people(in: "desk@example.com (Claire Ancelin and Paul Rey)")
                == ["Claire Ancelin", "Paul Rey"]
        )
        // A byline that names somebody twice names them once.
        #expect(Author.people(in: "Paul Rey et Paul Rey") == ["Paul Rey"])
        #expect(Author.people(in: " , ").isEmpty)
        #expect(Author.people(in: nil).isEmpty)
    }

    @Test("Two people who signed together are two rows, and each keeps the article")
    func twoPeopleAreTwoWriters() async throws {
        try await article("Un", by: "Claire Ancelin et Paul Rey")
        try await article("Deux", by: "Claire Ancelin")

        let found = try await authors.all()
        #expect(found.map(\.name) == ["Claire Ancelin", "Paul Rey"])
        #expect(found.first?.count == 2)
        #expect(found.last?.count == 1)

        // The byline itself is untouched : it is what the article is headed
        // with, what the index holds and what travels between devices.
        #expect(try await articles.summaries(.author("Paul Rey")).map(\.author) == ["Claire Ancelin et Paul Rey"])
    }

    @Test("A piece two favourites wrote together is one article, not two")
    func countedOnce() async throws {
        try await article("Un", by: "Claire Ancelin et Paul Rey")
        try await authors.setFavourite("Claire Ancelin", true)
        try await authors.setFavourite("Paul Rey", true)

        #expect(try await articles.summaries(in: .builtIn(.favouriteAuthors)).map(\.title) == ["Un"])

        let squares = try await authors.collections()
        #expect(squares.first { $0.kind == .builtIn(.authors) }?.count == 2)
        #expect(squares.first { $0.kind == .builtIn(.favouriteAuthors) }?.count == 1)
    }

    @Test("A byline a publisher rewrote leaves nobody behind")
    func rewrittenByline() async throws {
        let entry = try await article("Un", by: "Claire Ancelin et Paul Rey")

        try await database.writer.write { db in
            try AuthorStore.index(entry.id, byline: "Claire Ancelin", in: db)
        }
        #expect(try await authors.all().map(\.name) == ["Claire Ancelin"])
    }

    // MARK: - Where they write

    @Test("A row names the publishers a writer appears in, the ones they write most for first")
    func whereTheyWrite() async throws {
        try await article("Un", by: "Paul Rey", from: "https://feeds.papier.example.com/une.xml")
        try await article("Deux", by: "Paul Rey", from: "https://feeds.papier.example.com/monde.xml")
        try await article("Trois", by: "Paul Rey", from: "https://feeds.revue.example.com/rss.xml")

        let rey = try #require(try await authors.all().first)
        #expect(rey.count == 3)
        // The publisher and never the desk : two feeds served from one address
        // are one mark, exactly as they are one heading in the sources list.
        // The host is taken as it stands, `feeds.` included : folding a
        // subdomain into its parent would need the public suffix list, and the
        // sources list has always refused that for the same reason.
        #expect(rey.publishers == ["feeds.papier.example.com", "feeds.revue.example.com"])

        // The page about them answers the same thing, since it is asked from
        // somewhere the list has not been loaded.
        #expect(try await authors.author(named: "Paul Rey")?.publishers == rey.publishers)
    }

    @Test("A favourite with nothing to their name writes nowhere, and says so")
    func nowhereToWrite() async throws {
        try await authors.setFavourite("Paul Rey", true)
        #expect(try await authors.all().first?.publishers.isEmpty == true)
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
