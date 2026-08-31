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

    @Test("Subscribing keeps the address, the title and the site")
    func subscribing() async throws {
        let result = try await store.subscribe(
            to: Subscription(
                address: "feeds.example.com/atom.xml",
                title: "Example",
                siteURL: URL(string: "https://example.com")
            )
        )

        #expect(result.isNew)
        #expect(result.feed.url.absoluteString == "https://feeds.example.com/atom.xml")
        #expect(result.feed.title == "Example")
        #expect(!result.feed.isFavourite)
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
        try await store.setFavourite(feed.id, true)

        let again = try await store.subscribe(
            to: Subscription(
                address: address,
                title: "Example",
                siteURL: URL(string: "https://example.com")
            )
        )

        // The reader's own naming outranks a re-import, and so does what they
        // singled out, but a field still empty is worth filling.
        #expect(!again.isNew)
        #expect(again.feed.title == "My own name")
        #expect(again.feed.isFavourite)
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

    @Test("Every source sits under the publisher serving it")
    func groupsFallOutOfTheAddresses() async throws {
        try await store.subscribe(
            to: Subscription(address: "https://www.leparisien.fr/societe/rss.xml", title: "Société"))
        try await store.subscribe(
            to: Subscription(address: "https://leparisien.fr/politique/rss.xml", title: "Politique"))
        try await store.subscribe(to: Subscription(address: "https://blog.example.com/feed", title: "Un blog"))

        let groups = try await store.groups()

        // A paper with a feed per desk is one publisher, and a blog on a host
        // of its own is another : the same rule the digest counts rooms by.
        #expect(groups.map(\.domain) == ["blog.example.com", "leparisien.fr"])
        #expect(groups.first { $0.domain == "leparisien.fr" }?.feeds.map(\.title) == ["Politique", "Société"])
        #expect(groups.allSatisfy { $0.name == nil })
    }

    @Test("A group is named by the site, not by the address the feed is served at")
    func groupsFollowTheSite() async throws {
        try await store.subscribe(
            to: Subscription(
                address: "https://feedpress.example/lemonde.xml",
                title: "Le Monde",
                siteURL: URL(string: "https://www.lemonde.fr")
            )
        )

        let groups = try await store.groups()
        #expect(groups.map(\.domain) == ["lemonde.fr"])
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

    // MARK: - Groups and favourites

    @Test("Naming a publisher writes a row, and only the ones named have one")
    func namingAGroup() async throws {
        try await store.subscribe(to: Subscription(address: "https://www.lemonde.fr/rss/une.xml"))
        try await store.subscribe(to: Subscription(address: "https://blog.example.com/feed"))

        let kept = try await store.rename(domain: "lemonde.fr", to: "  Le Monde  ")

        #expect(kept == "Le Monde")
        let names = try await store.names()
        #expect(names.map(\.domain) == ["lemonde.fr"])

        let groups = try await store.groups()
        // Named, so it files under L rather than under the address it wears.
        #expect(groups.map(\.title) == ["blog.example.com", "Le Monde"])
        #expect(groups.first { $0.domain == "lemonde.fr" }?.name == "Le Monde")
    }

    @Test("Naming a publisher again replaces the name rather than adding one")
    func renamingAGroupTwice() async throws {
        try await store.subscribe(to: Subscription(address: "https://www.lemonde.fr/rss/une.xml"))

        try await store.rename(domain: "lemonde.fr", to: "Le Monde")
        try await store.rename(domain: "lemonde.fr", to: "Le Monde diplomatique")

        let names = try await store.names()
        #expect(names.count == 1)
        #expect(names.first?.name == "Le Monde diplomatique")
    }

    @Test("A name taken back leaves the group called by its address")
    func clearingAName() async throws {
        try await store.subscribe(to: Subscription(address: "https://www.lemonde.fr/rss/une.xml"))
        try await store.rename(domain: "lemonde.fr", to: "Le Monde")

        // Emptied, blank, or written out as the address again : three ways of
        // saying the same thing, and none of them is a name.
        for raw in [nil, "", "   ", "lemonde.fr"] {
            let kept = try await store.rename(domain: "lemonde.fr", to: raw)
            #expect(kept == nil)
            let names = try await store.names()
            #expect(names.isEmpty)
            try await store.rename(domain: "lemonde.fr", to: "Le Monde")
        }

        let groups = try await store.groups()
        #expect(groups.map(\.title) == ["Le Monde"])
    }

    @Test("Naming a publisher moves nothing")
    func namingMovesNothing() async throws {
        let feed = try await store.subscribe(to: Subscription(address: "https://www.lemonde.fr/rss/une.xml")).feed

        try await store.rename(domain: "lemonde.fr", to: "Le Monde")

        let stored = try #require(try await store.feed(id: feed.id))
        #expect(stored.domain == "lemonde.fr")
    }

    @Test("A favourite source stars nothing")
    func favouritingASource() async throws {
        let feed = try await store.subscribe(to: Subscription(address: "https://www.lemonde.fr/rss/une.xml")).feed
        try await database.writer.write { db in
            try Entry(feedID: feed.id, guid: "urn:example:1", title: "Une réforme").insert(db)
        }

        try await store.setFavourite(feed.id, true)

        #expect(try await store.feed(id: feed.id)?.isFavourite == true)
        let starred = try await database.writer.read { db in
            try Entry.fetchAll(db).filter(\.isStarred).count
        }
        #expect(starred == 0)

        try await store.setFavourite(feed.id, false)
        #expect(try await store.feed(id: feed.id)?.isFavourite == false)
    }

    @Test("A publisher's mark is one identity, whatever desk an article arrived through")
    func identitiesAreOnePerPublisher() async throws {
        try await store.subscribe(
            to: Subscription(
                address: "https://www.lemonde.fr/rss/une.xml",
                title: "À la une",
                siteURL: URL(string: "https://www.lemonde.fr")
            )
        )
        try await store.subscribe(
            to: Subscription(
                address: "https://www.lemonde.fr/sport/rss.xml",
                title: "Sport",
                siteURL: URL(string: "https://www.lemonde.fr"),
                iconURL: URL(string: "/img/logo.png")
            )
        )
        try await store.subscribe(to: Subscription(address: "https://blog.example.com/feed"))
        try await store.rename(domain: "lemonde.fr", to: "Le Monde")

        let identities = try await store.identities()

        // Two desks of one paper are one identity, so the favicon behind them
        // is one address and one request rather than two of each.
        #expect(identities.count == 2)

        let paper = try #require(identities["lemonde.fr"])
        #expect(paper.name == "Le Monde")
        // Stated by whichever of its feeds states one.
        #expect(paper.iconURL?.absoluteString == "/img/logo.png")
        #expect(paper.siteURL?.absoluteString == "https://www.lemonde.fr")

        // A publisher nobody renamed is called by its address, which is a name.
        #expect(identities["blog.example.com"]?.name == "blog.example.com")
    }

    @Test("A group knows whether the reader singled any of its sources out")
    func groupsCarryTheFavourites() async throws {
        let feed = try await store.subscribe(to: Subscription(address: "https://www.lemonde.fr/rss/une.xml")).feed
        try await store.subscribe(to: Subscription(address: "https://blog.example.com/feed"))

        try await store.setFavourite(feed.id, true)

        let groups = try await store.groups()
        #expect(groups.first { $0.domain == "lemonde.fr" }?.hasFavourite == true)
        #expect(groups.first { $0.domain == "blog.example.com" }?.hasFavourite == false)
    }
}
