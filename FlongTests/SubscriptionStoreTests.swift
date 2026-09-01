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

    // MARK: - Editing a source

    @Test("Editing renames a source without moving it")
    func editingRenames() async throws {
        let feed = try await store.subscribe(
            to: Subscription(address: "https://feeds.example.com/1.xml", title: "Example")
        ).feed

        let change = try await store.edit(
            feed.id,
            to: SourceEdit(title: "My own name", address: feed.url.absoluteString, isFavourite: true)
        )

        #expect(!change.movedAddress)
        #expect(change.feed.url == feed.url)
        #expect(change.feed.title == "My own name")
        #expect(change.feed.isFavourite)
        #expect(change.marked.isEmpty)
    }

    @Test("An edited name with nothing in it falls back to the host it now has")
    func editingWithNoName() async throws {
        let feed = try await store.subscribe(
            to: Subscription(address: "https://feeds.example.com/1.xml", title: "Example")
        ).feed

        let change = try await store.edit(feed.id, to: SourceEdit(address: "https://news.example.org/2.xml"))

        #expect(change.feed.title == "news.example.org")
    }

    @Test("A source that moves keeps its articles and says where it came from")
    func movingKeepsTheArticles() async throws {
        let feed = try await store.subscribe(
            to: Subscription(address: "https://feeds.example.com/1.xml", title: "Example")
        ).feed
        try await database.writer.write { db in
            try Entry(feedID: feed.id, guid: "urn:example:1", title: "First", isStarred: true).insert(db)
        }

        let change = try await store.edit(
            feed.id,
            to: SourceEdit(title: "Example", address: "https://feeds.example.com/2.xml")
        )

        #expect(change.previousURL == feed.url)
        #expect(change.feed.previousURL == feed.url)
        #expect(change.feed.url.absoluteString == "https://feeds.example.com/2.xml")
        #expect(change.feed.id == feed.id)
        // The marked ones come back, since every record naming them is named
        // after the address they arrived at.
        #expect(change.marked.map(\.guid) == ["urn:example:1"])

        let remaining = try await database.writer.read { db in try Entry.fetchCount(db) }
        #expect(remaining == 1)
        let actual = try await store.count()
        #expect(actual == 1)
    }

    @Test("A source cannot be moved onto an address already followed")
    func movingOntoAnotherSource() async throws {
        let first = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml")).feed
        let second = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/2.xml")).feed

        await #expect(throws: SubscriptionError.addressAlreadyFollowed(second.id)) {
            try await store.edit(first.id, to: SourceEdit(address: "https://feeds.example.com/2.xml"))
        }

        let stored = try await store.feed(id: first.id)
        #expect(stored?.url == first.url)
        let actual = try await store.count()
        #expect(actual == 2)
    }

    @Test("An address that is not one Flong can follow is refused")
    func movingToAnImpossibleAddress() async throws {
        let feed = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml")).feed

        await #expect(throws: FeedURLError.embeddedCredentials) {
            try await store.edit(feed.id, to: SourceEdit(address: "https://user:secret@feeds.example.com/1.xml"))
        }
    }

    @Test("A source that moves forgets what the server it left had said")
    func movingForgetsTheConditionalState() async throws {
        let feed = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml")).feed
        try await database.writer.write { db in
            var stored = feed
            stored.etag = "\"abc\""
            stored.lastModified = "Mon, 01 Sep 2026 00:00:00 GMT"
            stored.fetchCount = 10
            stored.notModifiedCount = 9
            stored.failureCount = 3
            stored.lastFailureReason = "gone (410)"
            stored.quarantinedAt = Date()
            try stored.update(db)
        }

        let change = try await store.edit(feed.id, to: SourceEdit(address: "https://feeds.example.com/2.xml"))

        #expect(change.feed.etag == nil)
        #expect(change.feed.lastModified == nil)
        #expect(change.feed.fetchCount == 0)
        #expect(change.feed.notModifiedCount == 0)
        // The quarantine is exactly what a reader editing a broken address is
        // undoing, so it does not survive the move either.
        #expect(change.feed.failureCount == 0)
        #expect(change.feed.lastFailureReason == nil)
        #expect(change.feed.quarantinedAt == nil)
    }

    @Test("A mark still waiting for its article follows the source that moves")
    func movingTakesTheWaitingMarks() async throws {
        let feed = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml")).feed
        let other = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/other.xml")).feed
        try await database.writer.write { db in
            for url in [feed.url, other.url] {
                try db.execute(
                    sql: """
                        INSERT INTO pending_mark (feed_url, guid, payload, received_at)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [url.absoluteString, "urn:example:1", Data(), Date()]
                )
            }
        }

        try await store.edit(feed.id, to: SourceEdit(address: "https://feeds.example.com/2.xml"))

        let waiting = try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT feed_url FROM pending_mark ORDER BY feed_url")
        }
        #expect(waiting == ["https://feeds.example.com/2.xml", "https://feeds.example.com/other.xml"])
    }

    @Test("A source that leaves its publisher takes the name written over it")
    func movingEmptiesAPublisher() async throws {
        let feed = try await store.subscribe(to: Subscription(address: "https://www.lemonde.fr/rss/une.xml")).feed
        try await store.rename(domain: "lemonde.fr", to: "Le Monde")

        let change = try await store.edit(feed.id, to: SourceEdit(address: "https://feeds.example.com/1.xml"))

        #expect(change.forgottenName == "lemonde.fr")
        let written = try await store.names()
        #expect(written.isEmpty)
    }

    @Test("A publisher another source still serves keeps its name")
    func movingOneOfSeveralDesks() async throws {
        let feed = try await store.subscribe(to: Subscription(address: "https://www.lemonde.fr/rss/une.xml")).feed
        try await store.subscribe(to: Subscription(address: "https://www.lemonde.fr/rss/sport.xml"))
        try await store.rename(domain: "lemonde.fr", to: "Le Monde")

        let change = try await store.edit(feed.id, to: SourceEdit(address: "https://feeds.example.com/1.xml"))

        #expect(change.forgottenName == nil)
        let written = try await store.names().map(\.name)
        #expect(written == ["Le Monde"])
    }

    @Test("The site is what a source is grouped under")
    func editingTheSiteRegroups() async throws {
        let feed = try await store.subscribe(
            to: Subscription(address: "https://feeds.feedburner.com/lemonde", title: "Le Monde")
        ).feed

        let change = try await store.edit(
            feed.id,
            to: SourceEdit(title: "Le Monde", siteAddress: "https://www.lemonde.fr")
        )

        #expect(change.feed.domain == "lemonde.fr")
        let groups = try await store.groups().map(\.domain)
        #expect(groups == ["lemonde.fr"])
    }

    @Test("A manual interval is held inside the bounds of section 8")
    func theIntervalIsBounded() async throws {
        let feed = try await store.subscribe(
            to: Subscription(address: "https://feeds.example.com/1.xml", title: "Example")
        ).feed

        let hurried = try await store.edit(feed.id, to: SourceEdit(title: "Example", refreshInterval: 5))
        #expect(hurried.feed.refreshInterval == RefreshSchedule.minimumInterval)

        let idle = try await store.edit(feed.id, to: SourceEdit(title: "Example", refreshInterval: 7 * 24 * 60 * 60))
        #expect(idle.feed.refreshInterval == RefreshSchedule.maximumInterval)

        let automatic = try await store.edit(feed.id, to: SourceEdit(title: "Example"))
        #expect(automatic.feed.refreshInterval == nil)
    }

    @Test("A move arriving from another device moves the row rather than adding one")
    func readdressingFromAnotherDevice() async throws {
        let feed = try await store.subscribe(
            to: Subscription(address: "https://feeds.example.com/1.xml", title: "Example")
        ).feed
        let url = try #require(URL(string: "https://feeds.example.com/2.xml"))
        let moved = try await store.readdress(from: feed.url, to: url)

        #expect(moved?.previousURL == feed.url)
        #expect(moved?.feed.id == feed.id)
        let actual = try await store.count()
        #expect(actual == 1)
    }

    @Test("A move that arrives twice changes nothing the second time")
    func readdressingIsIdempotent() async throws {
        let feed = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml")).feed
        let url = try #require(URL(string: "https://feeds.example.com/2.xml"))

        try await store.readdress(from: feed.url, to: url)
        let again = try await store.readdress(from: feed.url, to: url)

        #expect(again == nil)
        let actual = try await store.count()
        #expect(actual == 1)
    }

    @Test("A move onto an address this device already follows is left alone")
    func readdressingOntoAnotherSource() async throws {
        let first = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml")).feed
        let second = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/2.xml")).feed

        let moved = try await store.readdress(from: first.url, to: second.url)

        #expect(moved == nil)
        let stored = try await store.feed(id: first.id)
        #expect(stored?.url == first.url)
    }

    @Test("What another device decided about a source outranks what is stored")
    func adoptingWhatAnotherDeviceDecided() async throws {
        let feed = try await store.subscribe(
            to: Subscription(address: "https://feeds.example.com/1.xml", title: "Example")
        ).feed

        let changed = try await store.adopt(
            Subscription(
                address: "https://feeds.example.com/1.xml",
                title: "My own name",
                siteURL: URL(string: "https://example.com")
            ),
            isFavourite: true,
            at: feed.id
        )

        #expect(changed)
        let stored = try await store.feed(id: feed.id)
        #expect(stored?.title == "My own name")
        #expect(stored?.siteURL?.absoluteString == "https://example.com")
        #expect(stored?.isFavourite == true)
    }

    @Test("A record that says nothing about a favourite does not take one back")
    func adoptingSaysNothingAboutAFavourite() async throws {
        let feed = try await store.subscribe(
            to: Subscription(address: "https://feeds.example.com/1.xml", title: "Example")
        ).feed
        try await store.setFavourite(feed.id, true)

        let changed = try await store.adopt(
            Subscription(address: "https://feeds.example.com/1.xml", title: "Example"),
            isFavourite: nil,
            at: feed.id
        )

        #expect(!changed)
        let stored = try await store.feed(id: feed.id)
        #expect(stored?.isFavourite == true)
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

    @Test("Unsubscribing takes the filings of its articles, which no key reaches")
    func unsubscribingTakesTheFilings() async throws {
        let collections = CollectionStore(database)
        let feed = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml")).feed
        let other = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/2.xml")).feed

        let kept = Entry(feedID: feed.id, guid: "urn:example:1", title: "Filed")
        let spared = Entry(feedID: other.id, guid: "urn:example:2", title: "Filed too")
        try await database.writer.write { db in
            try kept.insert(db)
            try spared.insert(db)
        }
        _ = try await collections.create("À lire")
        try await collections.add([kept.id, spared.id], to: "À lire")

        try await store.unsubscribe(feed.id)

        // The article of the other source keeps its place : a filing is removed
        // because the article it names has gone, not because the collection was.
        let bindings = try await database.writer.read { db in
            try UUID.fetchAll(db, sql: "SELECT target_id FROM tag_binding WHERE target_kind = 'entry'")
        }
        #expect(bindings == [spared.id])
        let made = try await collections.made()
        #expect(made.first { $0.name == "À lire" }?.count == 1)
    }

    @Test("Unsubscribing says which of its articles the reader had marked")
    func unsubscribingReportsWhatWasMarked() async throws {
        let feed = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml")).feed

        var starred = Entry(feedID: feed.id, guid: "urn:example:starred", title: "Starred")
        starred.isStarred = true
        var written = Entry(feedID: feed.id, guid: "urn:example:written", title: "Written on")
        written.annotation = "A note"
        let plain = Entry(feedID: feed.id, guid: "urn:example:plain", title: "Nothing said")
        try await database.writer.write { db in
            try starred.insert(db)
            try written.insert(db)
            try plain.insert(db)
        }

        let gone = try await store.unsubscribe(feed.id)

        // What Spotlight held and what iCloud has a record of, which is the
        // marked ones and never the whole stream of the feed.
        #expect(Set(gone.marked.map(\.id)) == [starred.id, written.id])
        #expect(Set(gone.marked.map(\.guid)) == ["urn:example:starred", "urn:example:written"])
        #expect(gone.feed.url == feed.url)
    }

    @Test("Unsubscribing drops the marks that were waiting for its articles")
    func unsubscribingDropsWaitingMarks() async throws {
        let feed = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml")).feed
        let other = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/2.xml")).feed

        for url in [feed.url, other.url] {
            try await database.writer.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO pending_mark (feed_url, guid, payload, received_at)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [url.absoluteString, "urn:example:1", Data(), Date()]
                )
            }
        }

        try await store.unsubscribe(feed.id)

        let waiting = try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT feed_url FROM pending_mark")
        }
        #expect(waiting == [other.url.absoluteString])
    }

    @Test("Unsubscribing leaves no story standing over nothing")
    func unsubscribingEmptiesStories() async throws {
        let feed = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/1.xml")).feed
        let other = try await store.subscribe(to: Subscription(address: "https://feeds.example.com/2.xml")).feed

        let covered = Entry(feedID: feed.id, guid: "urn:example:1", title: "One room")
        let alsoCovered = Entry(feedID: other.id, guid: "urn:example:2", title: "The other")
        let now = Date()
        let story = Story(title: "Something happened", articleCount: 2, feedCount: 2, firstAt: now, lastAt: now)
        try await database.writer.write { db in
            try covered.insert(db)
            try alsoCovered.insert(db)
            try story.insert(db)
            try StoryMember(storyID: story.id, entryID: covered.id, similarity: 1).insert(db)
            try StoryMember(storyID: story.id, entryID: alsoCovered.id, similarity: 1).insert(db)
        }

        try await store.unsubscribe(feed.id)

        // One room left covering it is not a story, so the headline goes rather
        // than standing over a single article.
        let stories = try await database.writer.read { db in try Story.fetchCount(db) }
        #expect(stories == 0)
    }

    @Test("The name over a publisher goes with the last of its sources")
    func unsubscribingForgetsTheName() async throws {
        let une = try await store.subscribe(to: Subscription(address: "https://www.lemonde.fr/rss/une.xml")).feed
        let sport = try await store.subscribe(to: Subscription(address: "https://lemonde.fr/rss/sport.xml")).feed
        try await store.rename(domain: "lemonde.fr", to: "Le Monde")

        let first = try await store.unsubscribe(une.id)
        #expect(!first.forgotName)
        let stillNamed = try await store.names()
        #expect(stillNamed.map(\.name) == ["Le Monde"])

        let last = try await store.unsubscribe(sport.id)
        #expect(last.forgotName)
        let forgotten = try await store.names()
        #expect(forgotten.isEmpty)
    }

    @Test("Removing a publisher removes every source under it and nothing else")
    func unsubscribingFromAPublisher() async throws {
        try await store.subscribe(to: Subscription(address: "https://www.lemonde.fr/rss/une.xml"))
        try await store.subscribe(to: Subscription(address: "https://lemonde.fr/rss/sport.xml"))
        let blog = try await store.subscribe(to: Subscription(address: "https://blog.example.com/feed")).feed
        try await store.rename(domain: "lemonde.fr", to: "Le Monde")

        let gone = try await store.unsubscribe(fromPublisher: "lemonde.fr")

        #expect(gone.count == 2)
        // The name is forgotten once, by whichever of them turned out to be last.
        #expect(gone.filter(\.forgotName).count == 1)
        let names = try await store.names()
        #expect(names.isEmpty)
        let left = try await store.feeds()
        #expect(left.map(\.id) == [blog.id])
    }

    @Test("Removing a publisher nobody follows removes nothing")
    func unsubscribingFromAnUnknownPublisher() async throws {
        try await store.subscribe(to: Subscription(address: "https://blog.example.com/feed"))

        let gone = try await store.unsubscribe(fromPublisher: "lemonde.fr")

        #expect(gone.isEmpty)
        let left = try await store.count()
        #expect(left == 1)
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
