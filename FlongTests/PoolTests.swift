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

    /// The anchor this suite walks from.
    ///
    /// Handed to the store rather than read off ``PoolTrust/root``, which ships
    /// empty : a closed pool with no anchor has no members, so a suite that
    /// could not state one could not test the counting at all.
    private let root = "the-author"

    init() throws {
        database = try AppDatabase.inMemory()
        store = PoolStore(database, root: root)
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

    @Test("Nothing the author did not write is believed")
    func believesNoAuthorityWithoutTheAnchor() {
        // Anybody may create a record of that type in a public database, so an
        // authority record is worth nothing for existing.
        let record = CKRecord(recordType: PoolRecords.RecordType.authority)
        record[PoolRecords.Field.trusted] = ["someone"]

        #expect(PoolAuthority.read(record, root: root) == nil)
        #expect(PoolAuthority.read(record, root: nil) == nil)
        #expect(!PoolTrust.isRoot("someone"))
    }

    @Test("With no anchor, nobody is in at all")
    func aClosedPoolWithNoAnchorIsEmpty() {
        // The shipped value until the author's identity is filled in. A closed
        // pool with no root has no members, which is the safe way round : the
        // page shows nothing rather than showing what nobody vouched for.
        #expect(PoolTrust.root == nil)
        #expect(PoolTrust.authorised(from: nil, vouches: ["a": ["b"]], banned: []).isEmpty)
    }

    // MARK: - Who was let in

    @Test("The walk reaches whoever was brought in, however deep")
    func sponsorshipIsTransitive() {
        let reached = PoolTrust.authorised(
            from: root,
            vouches: [root: ["anne"], "anne": ["bo"], "bo": ["cy"], "nobody": ["dee"]],
            banned: []
        )
        #expect(reached == [root, "anne", "bo", "cy"])
    }

    @Test("Cutting somebody out cuts everybody they brought in")
    func banTakesTheBranch() {
        let vouches: [String: Set<String>] = [root: ["anne", "zoe"], "anne": ["bo"], "bo": ["cy"]]

        #expect(PoolTrust.authorised(from: root, vouches: vouches, banned: []).count == 5)

        // The whole point : a person about to be cut out would otherwise
        // sponsor ten accounts first and lose nothing.
        let after = PoolTrust.authorised(from: root, vouches: vouches, banned: ["anne"])
        #expect(after == [root, "zoe"])
    }

    @Test("Somebody reachable another way survives the ban of one sponsor")
    func keepsASecondPath() {
        let vouches: [String: Set<String>] = [root: ["anne", "zoe"], "anne": ["bo"], "zoe": ["bo"]]
        let after = PoolTrust.authorised(from: root, vouches: vouches, banned: ["anne"])
        #expect(after == [root, "zoe", "bo"])
    }

    @Test("A ring of sponsorships that never reaches the root lets nobody in")
    func ignoresAnUnreachableRing() {
        let reached = PoolTrust.authorised(from: root, vouches: ["a": ["b"], "b": ["a"]], banned: [])
        #expect(reached == [root])
    }

    @Test("A cycle inside the pool is walked once and does not hang")
    func walksACycle() {
        let reached = PoolTrust.authorised(
            from: root,
            vouches: [root: ["anne"], "anne": ["bo"], "bo": ["anne", "cy"]],
            banned: []
        )
        #expect(reached == [root, "anne", "bo", "cy"])
    }

    @Test("One person may only bring in so many")
    func capsASponsorship() throws {
        let record = PoolVouch.record(
            sponsoring: (0..<(PoolTrust.sponsorLimit + 10)).map { "reader-\($0)" },
            by: UUID()
        )
        let received = try #require(PoolVouch.received(record))
        #expect(received.sponsored.count == PoolTrust.sponsorLimit)
    }

    @Test("The author cannot be cut out by anybody, including a stray ban")
    func theRootStands() {
        #expect(PoolTrust.authorised(from: root, vouches: [:], banned: [root]).isEmpty)
        #expect(PoolTrust.authorised(from: root, vouches: [:], banned: []) == [root])
    }

    // MARK: - What it adds up to

    /// Brings people into the pool, the shortest way : the author sponsors
    /// them directly. Everything under this depends on it, because a closed
    /// pool stores nothing from anybody it has not been told about.
    ///
    /// Additive, since one vouch record holds everybody one person brought in
    /// and rewriting it with a single name would un-sponsor the rest.
    private func letIn(_ creators: [String]) async throws {
        let already = try await store.sponsored(by: root)
        try await store.absorb([
            PoolVouch.Received(creator: root, sponsored: already.union(creators), modifiedAt: Date())
        ])
    }

    private func offer(_ creator: String, _ urls: [String], title: String = "Example", at date: Date = Date())
        async throws
    {
        try await letIn([creator])
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
        try await letIn(["the-same-reader"])

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

        try await store.setAuthority(PoolAuthority(trusted: ["the-author"]))
        let popular = try await store.popular()
        #expect(popular.count == 1)
        #expect(popular[0].isEndorsed)

        // Taken off the roster, and it stops counting at once.
        try await store.setAuthority(PoolAuthority())
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

        try await store.setAuthority(PoolAuthority(trusted: ["reader"]))
        let popular = try await store.popular()
        #expect(popular.map(\.url.absoluteString) == ["https://feeds.example.org/rss"])
    }

    @Test("The oldest lists are the ones dropped when the pool held here is too large")
    func prunesTheOldest() async throws {
        let old = Date(timeIntervalSince1970: 1)
        try await offer("stopped-reading", ["https://feeds.example.org/rss"], at: old)
        try await offer("still-reading", ["https://feeds.example.com/atom.xml"])

        try await store.prune(to: 1)

        try await store.setAuthority(PoolAuthority(trusted: ["stopped-reading", "still-reading"]))
        let popular = try await store.popular()
        #expect(popular.map(\.url.absoluteString) == ["https://feeds.example.com/atom.xml"])
    }

    @Test("Everything the pool left here goes when everything goes")
    func forgetsEverything() async throws {
        try await offered(by: PoolStore.threshold, of: "https://feeds.example.com/atom.xml")
        try await store.setAuthority(PoolAuthority(trusted: ["somebody"]))

        try await store.forgetEverything()

        #expect(try await store.contributors() == 0)
        #expect(try await store.trusted().isEmpty)
        #expect(try await store.popular().isEmpty)
    }

    @Test("A stranger's list is not even stored")
    func refusesAStrangersList() async throws {
        try await store.absorb([
            PoolList.Received(
                recordName: "pool-stranger-0",
                creator: "stranger",
                modifiedAt: Date(),
                feeds: [PooledFeed(url: "https://feeds.example.com/atom.xml", title: "Example", siteURL: nil)]
            )
        ])

        // Not merely uncounted : absent, so an unsponsored writer costs every
        // other reader's device nothing at all.
        let rows = try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pool_entry") ?? 0
        }
        #expect(rows == 0)
        #expect(try await store.contributors() == 0)
    }

    @Test("Cutting somebody out takes their rows with it")
    func banRemovesWhatTheyOffered() async throws {
        let url = "https://feeds.example.com/atom.xml"
        try await offered(by: PoolStore.threshold, of: url)
        #expect(try await store.popular().count == 1)

        try await store.setAuthority(PoolAuthority(banned: ["reader-0"]))

        #expect(try await store.popular().isEmpty)
        let contributors = try await store.contributors()
        #expect(contributors == PoolStore.threshold - 1)
    }

    @Test("Somebody being let in is reported, so the lists can be asked for again")
    func reportsThatTheGraphGrew() async throws {
        let grew = try await store.absorb([
            PoolVouch.Received(creator: root, sponsored: ["anne"], modifiedAt: Date())
        ])
        #expect(grew)

        // The same sponsorship again reaches nobody new, so nothing has to be
        // fetched a second time.
        let again = try await store.absorb([
            PoolVouch.Received(creator: root, sponsored: ["anne"], modifiedAt: Date())
        ])
        #expect(!again)
    }

    @Test("A withheld address is never suggested, whoever follows it")
    func withholdsAnAddress() async throws {
        let url = "https://feeds.example.com/atom.xml"
        try await offered(by: PoolStore.threshold, of: url)
        #expect(try await store.popular().count == 1)

        try await store.setAuthority(PoolAuthority(blocked: [PoolAuthority.digest(of: url)]))
        #expect(try await store.popular().isEmpty)

        // And it comes back when the decision is taken back.
        try await store.setAuthority(PoolAuthority())
        #expect(try await store.popular().count == 1)
    }

    @Test("What travels about a withheld address says nothing about it")
    func withholdsWithoutPublishing() throws {
        let secret = "https://feeds.example.com/private/2f8a9c/atom.xml"
        let authority = PoolAuthority(blocked: [PoolAuthority.digest(of: secret)])
        let record = PoolAuthority.record(authority, by: UUID())

        // The reason it is a digest : one reason to withhold an address is
        // that it should never have been public, and a list of forbidden
        // addresses would publish it to everybody.
        let published = (record[PoolRecords.Field.blocked] as? [String] ?? []).joined()
        #expect(!published.contains("example.com"))
        #expect(!published.contains("2f8a9c"))
        #expect(published == PoolAuthority.digest(of: secret))
    }

    @Test("The author's own device remembers what it withheld")
    func remembersTheAddressItWithheld() async throws {
        let address = "https://feeds.example.com/atom.xml"
        try await store.remember(address)
        try await store.setAuthority(PoolAuthority(blocked: [PoolAuthority.digest(of: address)]))

        let blocked = try await store.blocked()
        #expect(blocked.count == 1)
        #expect(blocked[0].url == address)

        // A device that only heard the digest has nothing to show but the
        // digest, which is the whole point.
        let other = PoolStore(try AppDatabase.inMemory(), root: root)
        try await other.setAuthority(PoolAuthority(blocked: [PoolAuthority.digest(of: address)]))
        let elsewhere = try await other.blocked()
        #expect(elsewhere.count == 1)
        #expect(elsewhere[0].url == nil)
    }

    @Test("Who offered an address is answerable, so a ban can be aimed")
    func saysWhoOfferedIt() async throws {
        let url = "https://feeds.example.com/atom.xml"
        try await offered(by: 3, of: url)

        let offerers = try await store.offerers(of: URL(string: url)!)
        #expect(offerers.sorted() == ["reader-0", "reader-1", "reader-2"])
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
