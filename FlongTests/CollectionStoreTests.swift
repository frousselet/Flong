//
//  CollectionStoreTests.swift
//  FlongTests
//
//  Created by François Rousselet on 30/08/2026.
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

@Suite("Collections the reader makes")
struct CollectionStoreTests {
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

    private func article(_ title: String) async throws -> Entry {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://a.example.com/\(title).xml", title: "A")
        ).feed
        var entry = Entry(feedID: feed.id, guid: "urn:\(title)", title: title, receivedAt: now)
        entry.hasMedia = false
        try await database.writer.write { db in try entry.insert(db) }
        return entry
    }

    // MARK: - Naming

    @Test("A name is trimmed, and a name that would invent a level is refused")
    func naming() async throws {
        #expect(CollectionStore.name(from: "  À lire  ") == "À lire")
        // The namespace is built on the separator, so a name carrying one would
        // make a collection inside a collection nobody asked for.
        #expect(CollectionStore.name(from: "veille/ios") == nil)
        #expect(CollectionStore.name(from: "   ") == nil)

        #expect(try await collections.create("veille/ios") == nil)
        #expect(try await collections.made().isEmpty)
    }

    @Test("A collection lives under its own root, so a tag of the same name is not it")
    func namespaced() async throws {
        _ = try await collections.create("Typographie", at: now)

        // Tags will be used for other things. A tag `Typographie` and a
        // collection `Typographie` are two different things with one name.
        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO tag (id, path, created_at) VALUES (?, ?, ?)",
                arguments: [UUID.v7(), "Typographie", now]
            )
        }
        #expect(try await collections.made().map(\.kind) == [.made("Typographie")])
    }

    @Test("Making the same collection twice makes one")
    func creationIsIdempotent() async throws {
        _ = try await collections.create("À lire", at: now)
        _ = try await collections.create("À lire", at: now)

        #expect(try await collections.made().count == 1)
    }

    // MARK: - Filling

    @Test("An article goes in, comes out, and the collection survives being emptied")
    func filling() async throws {
        let article = try await self.article("un")
        _ = try await collections.create("À lire", at: now)

        try await collections.add([article.id], to: "À lire", at: now)
        #expect(try await collections.collections(of: article.id) == ["À lire"])
        #expect(try await collections.made().first?.count == 1)
        #expect(try await articles.summaries(in: .made("À lire")).map(\.title) == ["un"])

        try await collections.remove([article.id], from: "À lire")
        #expect(try await collections.collections(of: article.id).isEmpty)
        // Empty, and still there : the reader made it, and emptying it is not
        // unmaking it.
        #expect(try await collections.made().map(\.kind) == [.made("À lire")])
        #expect(try await collections.made().first?.count == 0)
    }

    @Test("One article can be in several, and each of them knows")
    func several() async throws {
        let article = try await self.article("un")
        try await collections.add([article.id], to: "À lire", at: now)
        try await collections.add([article.id], to: "Thèse", at: now)

        #expect(try await collections.collections(of: article.id) == ["À lire", "Thèse"])
        #expect(try await collections.made().map(\.count) == [1, 1])
    }

    @Test("Renaming keeps what is in it, and throwing one away keeps the articles")
    func renamingAndDeleting() async throws {
        let article = try await self.article("un")
        try await collections.add([article.id], to: "À lire", at: now)

        _ = try await collections.rename("À lire", to: "Lu")
        #expect(try await collections.collections(of: article.id) == ["Lu"])

        try await collections.delete("Lu")
        #expect(try await collections.made().isEmpty)
        // A collection is a way of looking at articles. Putting the way of
        // looking away does not throw anything out.
        #expect(try await articles.summaries(.all, now: now).count == 1)
    }

    @Test("What another device says is the whole truth about an article")
    func settingReplaces() async throws {
        let article = try await self.article("un")
        try await collections.add([article.id], to: "À lire", at: now)
        try await collections.add([article.id], to: "Thèse", at: now)

        try await collections.set(["Thèse", "Presse"], of: article.id, at: now)

        // Out of one, into another, still in the third : a name missing from
        // what arrived is a name it was taken out of.
        #expect(try await collections.collections(of: article.id) == ["Presse", "Thèse"])
    }

    @Test("A collection says what it holds, and holds what it says")
    func theCountAgreesWithTheContents() async throws {
        let entry = try await self.article("un")

        // Starred, filed, then unstarred. The reader has said the article is
        // not a favourite ; they have not said it is out of the collection.
        try await articles.setStarred([entry.id], to: true)
        try await collections.add([entry.id], to: "Thèse", at: now)
        try await articles.setStarred([entry.id], to: false)

        let shelf = try #require(await collections.made().first)
        let inside = try await articles.summaries(in: .made("Thèse"))

        // A count is a promise about what is inside, and a square saying two
        // over a page showing one is the promise broken.
        #expect(shelf.count == inside.count)
        #expect(inside.count == 1)
    }

    @Test("Unstarring an article does not empty its collections")
    func unstarringKeepsTheFilings() async throws {
        let article = try await self.article("un")
        try await collections.add([article.id], to: "Thèse", at: now)
        try await collections.add([article.id], to: "Presse", at: now)
        try await articles.setStarred([article.id], to: true)

        // What the star in an article's own bar does. There used to be a
        // second copy of the article behind the star, and unstarring threw the
        // copy away and every filing with it.
        try await articles.setStarred([article.id], to: false)

        #expect(try await collections.collections(of: article.id) == ["Presse", "Thèse"])
        #expect(try await articles.summaries(in: .builtIn(.starred)).isEmpty)
        #expect(try await articles.summaries(in: .made("Thèse")).count == 1)
    }

    @Test("The star goes both ways on an article that was never starred")
    func starringGoesBothWays() async throws {
        // Filed and never starred, which is what the star in its own bar could
        // not do anything about.
        let article = try await self.article("un")
        try await collections.add([article.id], to: "Thèse", at: now)
        #expect(try await articles.summaries(in: .builtIn(.starred)).isEmpty)

        try await articles.setStarred([article.id], to: true)
        #expect(try await articles.summaries(in: .builtIn(.starred)).count == 1)

        try await articles.setStarred([article.id], to: false)
        #expect(try await articles.summaries(in: .builtIn(.starred)).isEmpty)
        // And it is still filed, through both.
        #expect(try await collections.collections(of: article.id) == ["Thèse"])
    }

    // MARK: - Between devices

    @Test("A filing travels on the article's own mark, not on a record of its own")
    func membershipTravels() async throws {
        let zone = CKRecordZone.ID(zoneName: SyncRecords.zoneName, ownerName: CKCurrentUserDefaultName)
        let article = try await self.article("un")
        try await collections.add([article.id], to: "À lire", at: now)

        let mark = try #require(await MarkStore(database).all().first)
        #expect(mark.collections == ["À lire"])
        // Filed and not starred is something to say, and is sent.
        #expect(!mark.isEmpty)

        // A marked article has a record already. A filing is one more field on
        // it and never one more record, which is the whole budget.
        let record = SyncRecords.record(for: mark, in: zone)
        #expect(record.recordType == SyncRecords.RecordType.mark)
        #expect(SyncRecords.mark(from: record) == mark)
    }

    @Test("An empty collection travels on its own record, since nothing else carries it")
    func theEmptyOneTravels() async throws {
        let zone = CKRecordZone.ID(zoneName: SyncRecords.zoneName, ownerName: CKCurrentUserDefaultName)
        _ = try await collections.create("Vide", at: now)

        let record = SyncRecords.record(forCollections: try await collections.names(), in: zone)
        #expect(SyncRecords.collectionNames(from: record) == ["Vide"])
        // One record for every collection there is, and only because of this
        // one : anything with an article in it would arrive on the article.
        #expect(record.recordID.recordName == "collections")
    }
}
