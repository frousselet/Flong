//
//  PoolTests.swift
//  FlongTests
//
//  Created by François Rousselet on 02/09/2026.
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

/// What the common pool offers, what it refuses to offer, and what it counts.
///
/// ``PoolExchange`` is the one part of this that cannot be tested : it needs a
/// container, an account and a network. Everything either side of it is here,
/// which is where the rules that matter live : nothing of the reader's leaves
/// except an address, nothing a stranger wrote is believed, and ten people are
/// ten people rather than ten records.
@Suite("The common pool")
struct PoolTests {
    private let database: AppDatabase
    private let store: PoolStore

    init() throws {
        database = try AppDatabase.inMemory()
        store = PoolStore(database)
    }

    // MARK: - What may be offered

    private func source(
        _ address: String,
        title: String = "Example",
        site: String? = nil,
        worked: Bool = true,
        shared: Bool = true
    ) throws -> Feed {
        Feed(
            url: try FeedURL.canonical(address),
            siteURL: site.flatMap { URL(string: $0) },
            title: title,
            lastSuccessAt: worked ? Date() : nil,
            isShared: shared
        )
    }

    @Test("A public source that works is offered, with its name and its site")
    func offersAPublicSource() throws {
        let feed = try source("https://feeds.example.com/atom.xml", title: "Example", site: "https://example.com")
        let offered = try #require(PooledFeed.offered(feed, secret: nil, hasCredential: false))

        #expect(offered.url == "https://feeds.example.com/atom.xml")
        #expect(offered.title == "Example")
        #expect(offered.siteURL == "https://example.com")
    }

    @Test("A source whose address is itself the subscription is never offered")
    func refusesAMaskedAddress() throws {
        let real = URL(string: "https://feeds.example.com/atom.xml?token=abcdef")!
        let masked = try #require(MaskedURL.mask(real))
        let feed = Feed(url: masked, title: "Example", lastSuccessAt: Date())

        #expect(PooledFeed.offered(feed, secret: nil, hasCredential: false) == nil)
    }

    @Test("A source behind a credential is never offered")
    func refusesACredential() throws {
        let feed = try source("https://feeds.example.com/atom.xml")
        #expect(PooledFeed.offered(feed, secret: nil, hasCredential: true) == nil)
    }

    @Test("A source carrying a parameter the reader designated is held back whole")
    func refusesADesignatedParameter() throws {
        let feed = try source("https://feeds.example.com/atom.xml?token=abcdef&format=rss")
        let secret = SecretParameters(["token"])

        // Not trimmed and offered anyway : what is left of that address is a
        // different address, and frequently not a feed at all.
        #expect(PooledFeed.offered(feed, secret: secret, hasCredential: false) == nil)
        #expect(PooledFeed.offered(feed, secret: nil, hasCredential: false) != nil)
    }

    @Test("A source carrying a parameter that only says who sent it is held back")
    func refusesATrackingParameter() throws {
        let feed = try source("https://feeds.example.com/atom.xml?utm_source=newsletter")
        #expect(PooledFeed.offered(feed, secret: nil, hasCredential: false) == nil)
    }

    @Test("A source that has never once been fetched is not recommended")
    func refusesASourceThatHasNeverWorked() throws {
        let feed = try source("https://feeds.example.com/atom.xml", worked: false)
        #expect(PooledFeed.offered(feed, secret: nil, hasCredential: false) == nil)
    }

    @Test("A source the reader took out of what they offer is not offered")
    func refusesWhatTheReaderHeldBack() throws {
        let feed = try source("https://feeds.example.com/atom.xml", shared: false)
        #expect(PooledFeed.offered(feed, secret: nil, hasCredential: false) == nil)
    }

    @Test(
        "A host nobody else could reach is never offered",
        arguments: [
            "http://localhost:1200/feed",
            "http://nas.local/rss",
            "http://192.168.1.4/feed.xml",
            "http://box.home.arpa/feed",
            "http://example.test/feed",
        ]
    )
    func refusesAPrivateHost(address: String) throws {
        let feed = try source(address)
        #expect(PooledFeed.offered(feed, secret: nil, hasCredential: false) == nil)
    }

    @Test("A site nobody else could reach is dropped, and the source still offered")
    func dropsAPrivateSite() throws {
        let feed = try source("https://feeds.example.com/atom.xml", site: "http://192.168.1.4")
        let offered = try #require(PooledFeed.offered(feed, secret: nil, hasCredential: false))
        #expect(offered.siteURL == nil)
    }

    @Test("A source with no name of its own is offered under its host")
    func namesASourceAfterItsHost() throws {
        let feed = try source("https://feeds.example.com/atom.xml", title: "   ")
        let offered = try #require(PooledFeed.offered(feed, secret: nil, hasCredential: false))
        #expect(offered.title == "feeds.example.com")
    }

    // MARK: - What arrives is not believed

    @Test("An address a stranger wrote is canonicalized rather than believed")
    func canonicalizesWhatArrives() throws {
        let arrived = PooledFeed(url: "HTTPS://Feeds.Example.COM:443/atom.xml", title: "Example", siteURL: nil)
        let received = try #require(arrived.received)
        #expect(received.url == "https://feeds.example.com/atom.xml")
    }

    @Test(
        "An address nobody should be asked to open is dropped",
        arguments: [
            "javascript:alert(1)",
            "file:///etc/passwd",
            "https://reader:hunter2@feeds.example.com/atom.xml",
            "http://127.0.0.1/feed",
            "not an address at all",
        ]
    )
    func dropsAnAddressThatIsNotOne(address: String) {
        #expect(PooledFeed(url: address, title: "Example", siteURL: nil).received == nil)
    }

    @Test("A name that arrives is stripped of what belongs to a renderer, and cut")
    func cutsAName() throws {
        let long = String(repeating: "a", count: PooledFeed.titleLimit + 40)
        let arrived = PooledFeed(url: "https://feeds.example.com/atom.xml", title: "Ex\u{0}am\nple", siteURL: nil)
        #expect(arrived.received?.title == "Example")

        let shouted = PooledFeed(url: "https://feeds.example.com/atom.xml", title: long, siteURL: nil)
        #expect(shouted.received?.title.count == PooledFeed.titleLimit)
    }

    @Test("A list that arrives empty of anything usable is a list of nothing")
    func dropsAnUnusableList() throws {
        let record = CKRecord(recordType: PoolRecords.RecordType.list)
        let payload = try JSONEncoder().encode([PooledFeed(url: "javascript:alert(1)", title: "x", siteURL: nil)])
        record[PoolRecords.Field.feeds] = SyncRecords.compressed(String(decoding: payload, as: UTF8.self))

        let received = try #require(PoolList.received(record))
        #expect(received.feeds.isEmpty)
    }

    // MARK: - What travels

    @Test("A list makes at least one record, even when it offers nothing")
    func alwaysWritesARecord() {
        let records = PoolList.records(for: [], by: UUID())
        #expect(records.count == 1)
    }

    @Test("A list goes out and comes back the same list")
    func roundTrip() throws {
        // The site is spelled canonically here, since that is the spelling a
        // record comes back as : what arrives is put through
        // ``FeedURL/canonical(_:)`` rather than believed.
        let feeds = [
            PooledFeed(url: "https://feeds.example.com/atom.xml", title: "Example", siteURL: "https://example.com/"),
            PooledFeed(url: "https://feeds.example.org/rss", title: "Other", siteURL: nil),
        ]

        let records = PoolList.records(for: feeds, by: UUID())
        #expect(records.count == 1)

        let received = try #require(PoolList.received(records[0]))
        #expect(received.feeds == feeds)
    }

    @Test("Two devices of one reader write the same record names")
    func oneReaderIsOneList() {
        let contributor = UUID()
        let phone = PoolList.records(for: [], by: contributor)[0].recordID.recordName
        let pad = PoolList.records(for: [], by: contributor)[0].recordID.recordName
        #expect(phone == pad)
    }

    @Test("Nobody is believed on their own while the anchor is unset")
    func believesNoRosterWithoutAnAnchor() {
        // ``PoolTrust/root`` ships empty until the author's own identity is
        // filled in, and an unanchored roster is not a roster : anybody may
        // write one into a public database.
        let record = CKRecord(recordType: PoolRecords.RecordType.roster)
        record[PoolRecords.Field.trusted] = ["_somebody"]

        #expect(PoolTrust.root == nil)
        #expect(PoolTrust.trusted(in: record) == nil)
        #expect(!PoolTrust.isRoot("_somebody"))
    }

    // MARK: - What it adds up to

    private func offer(_ creator: String, _ urls: [String], title: String = "Example", at date: Date = Date())
        async throws
    {
        try await store.absorb([
            PoolList.Received(
                recordName: "pool-\(creator)-0",
                creator: creator,
                modifiedAt: date,
                feeds: urls.map { PooledFeed(url: $0, title: title, siteURL: nil) }
            )
        ])
    }

    private func offered(by count: Int, of url: String) async throws {
        for number in 0..<count { try await offer("reader-\(number)", [url]) }
    }

    @Test("Nine readers are not enough, and ten are")
    func theThreshold() async throws {
        let url = "https://feeds.example.com/atom.xml"

        try await offered(by: PoolStore.threshold - 1, of: url)
        #expect(try await store.popular().isEmpty)

        try await offer("reader-late", [url])
        let popular = try await store.popular()
        #expect(popular.count == 1)
        #expect(popular[0].subscribers == PoolStore.threshold)
        #expect(!popular[0].isEndorsed)
    }

    @Test("One reader with several records is one reader")
    func countsPeopleAndNotRecords() async throws {
        let url = "https://feeds.example.com/atom.xml"

        for chunk in 0..<PoolStore.threshold {
            try await store.absorb([
                PoolList.Received(
                    recordName: "pool-one-\(chunk)",
                    creator: "the-same-reader",
                    modifiedAt: Date(),
                    feeds: [PooledFeed(url: url, title: "Example", siteURL: nil)]
                )
            ])
        }

        #expect(try await store.popular().isEmpty)
        let contributors = try await store.contributors()
        #expect(contributors == 1)
    }

    @Test("Somebody on the roster is enough on their own")
    func aVouchedForReaderIsEnough() async throws {
        let url = "https://feeds.example.com/atom.xml"
        try await offer("the-author", [url])
        #expect(try await store.popular().isEmpty)

        try await store.setTrusted(["the-author"])
        let popular = try await store.popular()
        #expect(popular.count == 1)
        #expect(popular[0].isEndorsed)

        // Taken off the roster, and it stops counting at once.
        try await store.setTrusted([])
        #expect(try await store.popular().isEmpty)
    }

    @Test("What the reader already follows is not a suggestion")
    func hidesWhatIsAlreadyFollowed() async throws {
        let url = "https://feeds.example.com/atom.xml"
        try await offered(by: PoolStore.threshold, of: url)
        #expect(try await store.popular().count == 1)

        let subscriptions = SubscriptionStore(database)
        _ = try await subscriptions.subscribe(to: Subscription(address: url))
        #expect(try await store.popular().isEmpty)
    }

    @Test("A source is called what most of the pool calls it")
    func takesTheMajorityName() async throws {
        let url = "https://feeds.example.com/atom.xml"
        for number in 0..<PoolStore.threshold {
            try await offer("reader-\(number)", [url], title: "Example")
        }
        try await offer("the-loud-one", [url], title: "BUY GOLD")

        let popular = try await store.popular()
        #expect(popular.count == 1)
        #expect(popular[0].title == "Example")
    }

    @Test("A list taken back out stops counting")
    func forgetsAWithdrawnList() async throws {
        let url = "https://feeds.example.com/atom.xml"
        try await offered(by: PoolStore.threshold, of: url)
        #expect(try await store.popular().count == 1)

        try await store.forget(recordNames: ["pool-reader-0-0"])
        #expect(try await store.popular().isEmpty)
    }

    @Test("A list rewritten replaces the one before it")
    func replacesAList() async throws {
        try await offer("reader", ["https://feeds.example.com/atom.xml", "https://feeds.example.org/rss"])
        try await offer("reader", ["https://feeds.example.org/rss"])

        try await store.setTrusted(["reader"])
        let popular = try await store.popular()
        #expect(popular.map(\.url.absoluteString) == ["https://feeds.example.org/rss"])
    }

    @Test("The oldest lists are the ones dropped when the pool held here is too large")
    func prunesTheOldest() async throws {
        let old = Date(timeIntervalSince1970: 1)
        try await offer("stopped-reading", ["https://feeds.example.org/rss"], at: old)
        try await offer("still-reading", ["https://feeds.example.com/atom.xml"])

        try await store.prune(to: 1)

        try await store.setTrusted(["stopped-reading", "still-reading"])
        let popular = try await store.popular()
        #expect(popular.map(\.url.absoluteString) == ["https://feeds.example.com/atom.xml"])
    }

    @Test("Everything the pool left here goes when everything goes")
    func forgetsEverything() async throws {
        try await offered(by: PoolStore.threshold, of: "https://feeds.example.com/atom.xml")
        try await store.setTrusted(["somebody"])

        try await store.forgetEverything()

        #expect(try await store.contributors() == 0)
        #expect(try await store.trusted().isEmpty)
        #expect(try await store.popular().isEmpty)
    }

    // MARK: - What this device offers

    @Test("What is offered is read off the sources, minus everything held back")
    func buildsTheOffer() async throws {
        let subscriptions = SubscriptionStore(database)
        let open = try await subscriptions.subscribe(to: Subscription(address: "https://feeds.example.com/atom.xml"))
        let designated = try await subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.org/rss?token=abcdef")
        )
        let paid = try await subscriptions.subscribe(to: Subscription(address: "https://feeds.example.net/feed"))

        // A source is only offered once it has been fetched successfully.
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE feed SET last_success_at = ?", arguments: [Date()])
        }

        let offer = try await store.offering(
            secrets: [designated.feed.id: SecretParameters(["token"])],
            credentialed: [paid.feed.id]
        )

        #expect(offer.map(\.url) == [open.feed.url.absoluteString])
    }
}
