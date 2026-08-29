//
//  SubscriptionStoreTests.swift
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

@Suite("Subscriptions")
struct SubscriptionStoreTests {
    private let database: AppDatabase
    private let store: SubscriptionStore

    init() throws {
        database = try AppDatabase.inMemory()
        store = SubscriptionStore(database)
    }

    // MARK: - Subscribing

    @Test("Subscribing keeps the address, the title and the folder")
    func subscribing() async throws {
        let result = try await store.subscribe(
            to: Subscription(
                address: "feeds.example.com/atom.xml",
                title: "Example",
                siteURL: URL(string: "https://example.com"),
                folder: "/Tech/iOS/"
            )
        )

        #expect(result.isNew)
        #expect(result.feed.url.absoluteString == "https://feeds.example.com/atom.xml")
        #expect(result.feed.title == "Example")
        #expect(result.feed.folder == "Tech/iOS")
        let actual = try await store.count()
        #expect(actual == 1)
    }

    @Test("A feed with no title is called after its host")
    func titleFallsBackToTheHost() async throws {
        let result = try await store.subscribe(to: Subscription(address: "https://www.example.com/feed"))
        #expect(result.feed.title == "example.com")
    }

    @Test("Two spellings of one address are one subscription")
    func duplicatesCollapse() async throws {
        let first = try await store.subscribe(to: Subscription(address: "feed://Feeds.Example.com/atom.xml"))
        let second = try await store.subscribe(to: Subscription(address: "https://feeds.example.com:443/atom.xml"))

        #expect(first.isNew)
        #expect(!second.isNew)
        #expect(first.feed.id == second.feed.id)
        let actual = try await store.count()
        #expect(actual == 1)
    }

    @Test("Subscribing again completes a feed without overwriting it")
    func resubscribingDoesNotOverwrite() async throws {
        let address = "https://feeds.example.com/atom.xml"
        let feed = try await store.subscribe(to: Subscription(address: address, title: "Example")).feed

        try await store.rename(feed.id, to: "My own name")
        try await store.move(feed.id, toFolder: "Veille")

        let again = try await store.subscribe(
            to: Subscription(
                address: address,
                title: "Example",
                siteURL: URL(string: "https://example.com"),
                folder: "Tech"
            )
        )

        // The reader's own naming and filing outrank a re-import, but a field
        // still empty is worth filling.
        #expect(!again.isNew)
        #expect(again.feed.title == "My own name")
        #expect(again.feed.folder == "Veille")
        #expect(again.feed.siteURL?.absoluteString == "https://example.com")
    }

    @Test("A batch of subscriptions lands in one transaction")
    func batchSubscribing() async throws {
        let subscriptions = try (0..<50).map { index in
            try Subscription(address: "https://feeds.example.com/\(index).xml", title: "Feed \(index)")
        }

        let results = try await store.subscribe(to: subscriptions)

        // `allSatisfy` is rethrowing, which the expectation macro cannot see
        // through, so the answer is computed first.
        let allNew = results.allSatisfy(\.isNew)

        #expect(results.count == 50)
        #expect(allNew)
        #expect(results.map(\.feed.url) == subscriptions.map(\.url))
        let actual = try await store.count()
        #expect(actual == 50)
    }

    @Test("A batch that fails leaves nothing behind")
    func aFailedBatchRollsBack() async throws {
        try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml"))

        // A duplicate identifier inside the batch is refused by SQLite, and the
        // whole transaction goes with it.
        let clash = UUID.v7()
        await #expect(throws: DatabaseError.self) {
            try await database.writer.write { db in
                try Feed(id: clash, url: URL(string: "https://feeds.example.com/2.xml")!, title: "Two").insert(db)
                try Feed(id: clash, url: URL(string: "https://feeds.example.com/3.xml")!, title: "Three").insert(db)
            }
        }

        let actual = try await store.count()
        #expect(actual == 1)
    }

    // MARK: - Reading

    @Test("Feeds come back sorted the way the reader's locale sorts")
    func feedsAreSortedLocally() async throws {
        for title in ["zeta", "Écrans", "alpha", "Beta"] {
            try await store.subscribe(to: Subscription(address: "https://feeds.example.com/\(title).xml", title: title))
        }

        let titles = try await store.feeds().map(\.title)
        #expect(titles == ["alpha", "Beta", "Écrans", "zeta"])
    }

    @Test("A folder holds the feeds filed in it, and only those")
    func feedsByFolder() async throws {
        try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml", folder: "Tech"))
        try await store.subscribe(to: Subscription(address: "https://feeds.example.com/2.xml", folder: "Tech/iOS"))
        try await store.subscribe(to: Subscription(address: "https://feeds.example.com/3.xml"))

        let inTech = try await store.feeds(inFolder: "Tech")
        let inIOS = try await store.feeds(inFolder: "/Tech/iOS")
        let unfiled = try await store.feeds(inFolder: nil)

        #expect(inTech.map(\.url.lastPathComponent) == ["1.xml"])
        #expect(inIOS.map(\.url.lastPathComponent) == ["2.xml"])
        #expect(unfiled.map(\.url.lastPathComponent) == ["3.xml"])
    }

    @Test("The folder list carries the levels no feed sits in")
    func foldersIncludeTheirAncestors() async throws {
        try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml", folder: "Tech/iOS"))
        try await store.subscribe(to: Subscription(address: "https://feeds.example.com/2.xml", folder: "Tech/iOS"))
        try await store.subscribe(to: Subscription(address: "https://feeds.example.com/3.xml", folder: "Presse"))

        let folders = try await store.folders()

        #expect(folders.map(\.path) == ["Presse", "Tech", "Tech/iOS"])
        #expect(folders.first { $0.path == "Tech" }?.feedCount == 0)
        #expect(folders.first { $0.path == "Tech/iOS" }?.feedCount == 2)
        #expect(folders.first { $0.path == "Tech/iOS" }?.name == "iOS")
    }

    @Test("A feed is found back from any spelling of its address")
    func lookupByAddress() async throws {
        try await store.subscribe(to: Subscription(address: "https://feeds.example.com/atom.xml"))

        let sameFeed = try await store.feed(at: "FEEDS.example.com/atom.xml")
        let otherFeed = try await store.feed(at: "https://feeds.example.com/other.xml")

        #expect(sameFeed != nil)
        #expect(otherFeed == nil)
    }

    // MARK: - Editing

    @Test("Renaming with nothing falls back to the host")
    func renamingWithAnEmptyTitle() async throws {
        let feed = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml")).feed

        try await store.rename(feed.id, to: "   ")

        let actual = try await store.feed(id: feed.id)?.title
        #expect(actual == "feeds.example.com")
    }

    @Test("Editing a feed that is not followed is an error")
    func editingAnUnknownFeed() async throws {
        let id = UUID.v7()
        await #expect(throws: SubscriptionError.unknownFeed(id)) { try await store.rename(id, to: "Nothing") }
        await #expect(throws: SubscriptionError.unknownFeed(id)) { try await store.unsubscribe(id) }
    }

    @Test("Unsubscribing takes the articles with it")
    func unsubscribingCascades() async throws {
        let feed = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml")).feed
        try await database.writer.write { db in
            try Entry(feedID: feed.id, guid: "urn:example:1", title: "First").insert(db)
        }

        try await store.unsubscribe(feed.id)

        let remaining = try await database.writer.read { db in try Entry.fetchCount(db) }
        #expect(remaining == 0)
        let actual = try await store.count()
        #expect(actual == 0)
    }

    // MARK: - Folders

    @Test("Renaming a folder carries its subfolders along")
    func renamingAFolder() async throws {
        try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml", folder: "Tech"))
        try await store.subscribe(to: Subscription(address: "https://feeds.example.com/2.xml", folder: "Tech/iOS"))
        try await store.subscribe(to: Subscription(address: "https://feeds.example.com/3.xml", folder: "Presse"))

        let moved = try await store.renameFolder("Tech", to: "Veille")

        #expect(moved == 2)
        let folders = try await store.folders().map(\.path)
        #expect(folders == ["Presse", "Veille", "Veille/iOS"])
    }

    @Test("Removing a folder keeps its feeds")
    func removingAFolder() async throws {
        try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml", folder: "Tech"))
        try await store.subscribe(to: Subscription(address: "https://feeds.example.com/2.xml", folder: "Tech/iOS"))

        let moved = try await store.removeFolder("Tech")

        #expect(moved == 2)
        let count = try await store.count()
        let unfiled = try await store.feeds(inFolder: nil)
        let folders = try await store.folders()

        #expect(count == 2)
        #expect(unfiled.count == 1)
        #expect(folders.map(\.path) == ["iOS"])
    }
}
