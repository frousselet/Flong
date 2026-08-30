//
//  SyncPayloadTests.swift
//  FlongTests
//
//  Created by François Rousselet on 29/08/2026.
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

/// One device, as far as these tests are concerned.
///
/// CloudKit itself is not exercised : an account, a container and a network are
/// none of them things a test can rely on. What is exercised is everything on
/// either side of it, which is where the behaviour lives, with records carried
/// between two stores by hand.
private struct Device {
    let database: AppDatabase
    let subscriptions: SubscriptionStore
    let articles: ArticleStore
    let marks: MarkStore
    let collections: CollectionStore
    let readStates: ReadStateStore
    let payload: SyncPayload

    init(zone: CKRecordZone.ID) throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
        articles = ArticleStore(database)
        marks = MarkStore(database)
        collections = CollectionStore(database)
        readStates = ReadStateStore(database)
        payload = SyncPayload(database, zone: zone)
    }

    @discardableResult
    func add(_ guid: String, to feed: Feed, title: String, published: Date, body: String = "Un corps.") async throws
        -> Entry
    {
        var entry = Entry(
            feedID: feed.id,
            guid: guid,
            url: URL(string: "https://example.com/\(guid)"),
            title: title,
            excerpt: body,
            publishedAt: published,
            receivedAt: published
        )
        entry.hasMedia = false

        try await database.writer.write { db in
            try entry.insert(db)
            try EntryBody(entryID: entry.id, sanitizedHTML: "<p>\(body)</p>", plainText: body).insert(db)
        }
        return entry
    }
}

@Suite("Synchronization records")
struct SyncRecordsTests {
    private let zone = CKRecordZone.ID(zoneName: SyncRecords.zoneName, ownerName: CKCurrentUserDefaultName)
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    @Test("A record is named after what it is about, not after where it was made")
    func namesAreDerived() throws {
        let url = URL(string: "https://feeds.example.com/f.xml")!

        #expect(SyncRecords.name(forFeed: url) == SyncRecords.name(forFeed: url))
        #expect(SyncRecords.name(forFeed: url) != SyncRecords.name(forFeed: URL(string: "https://other.example/f")!))
        #expect(
            SyncRecords.name(forMarkWithGUID: "urn:1", feedURL: url)
                == SyncRecords.name(forMarkWithGUID: "urn:1", feedURL: url)
        )
        #expect(
            SyncRecords.name(forMarkWithGUID: "urn:1", feedURL: url)
                != SyncRecords.name(forMarkWithGUID: "urn:2", feedURL: url)
        )
        #expect(SyncRecords.name(forReadStatePeriod: "2026-08", kind: .read) == "read-read-2026-08")
    }

    @Test("A subscription survives the wire")
    func feedRoundTrip() throws {
        let feed = Feed(
            url: URL(string: "https://feeds.example.com/f.xml")!,
            siteURL: URL(string: "https://example.com"),
            title: "Le Quotidien",
            folder: "Presse",
            createdAt: now
        )

        let record = SyncRecords.record(for: feed, in: zone)
        let subscription = try #require(SyncRecords.subscription(from: record))

        #expect(subscription.url == feed.url)
        #expect(subscription.title == "Le Quotidien")
        #expect(subscription.folder == "Presse")
        #expect(subscription.siteURL == feed.siteURL)
    }

    @Test("What a feed knows about its own fetching stays at home")
    func healthDoesNotTravel() throws {
        var feed = Feed(url: URL(string: "https://feeds.example.com/f.xml")!, title: "A")
        feed.etag = "\"v1\""
        feed.failureCount = 3
        feed.quarantinedAt = now
        feed.observedInterval = 3600

        let record = SyncRecords.record(for: feed, in: zone)

        #expect(record["etag"] == nil)
        #expect(record["failureCount"] == nil)
        #expect(record["quarantinedAt"] == nil)
        #expect(record["observedInterval"] == nil)
    }

    @Test("A mark survives the wire, filings and all")
    func markRoundTrip() throws {
        let mark = Mark(
            feedURL: "https://feeds.example.com/f.xml",
            guid: "urn:example:1",
            isStarred: true,
            annotation: "À relire",
            collections: ["Thèse", "Presse"],
            vector: Data(repeating: 128, count: 512),
            vectorModel: "nl.sentence.fr",
            vectorRevision: "1"
        )

        let restored = try #require(SyncRecords.mark(from: SyncRecords.record(for: mark, in: zone)))

        #expect(restored == mark)
        // A filing rides on the article's own record and never costs one of
        // its own, which is the whole of the collections budget.
        #expect(restored.collections == ["Thèse", "Presse"])
    }

    @Test("An article filed but not starred does not arrive starred")
    func filedWithoutTheStar() throws {
        let mark = Mark(
            feedURL: "https://feeds.example.com/f.xml",
            guid: "urn:example:2",
            isStarred: false,
            annotation: nil,
            collections: ["Thèse"]
        )

        let restored = try #require(SyncRecords.mark(from: SyncRecords.record(for: mark, in: zone)))
        #expect(restored.isStarred == false)
        #expect(restored.collections == ["Thèse"])
        // And it is not silence : a filing is something to say.
        #expect(!restored.isEmpty)
    }

    @Test("A mark filed nowhere carries something CloudKit can make a field of")
    func filedNowhere() throws {
        let mark = Mark(
            feedURL: "https://feeds.example.com/f.xml",
            guid: "urn:example:3",
            isStarred: true,
            annotation: nil,
            collections: []
        )
        let record = SyncRecords.record(for: mark, in: zone)

        // The server infers a field's type from the first record carrying it,
        // and refuses an empty list outright : `cannot use an empty list to
        // initialize a new field`. Starring without filing is the ordinary
        // case, so this is the first record most readers ever send.
        #expect(record["filedIn"] is Data)
        #expect(!(record["filedIn"] is [String]))

        #expect(try #require(SyncRecords.mark(from: record)).collections.isEmpty)
    }

    @Test("A reader with no collections at all still has a record to send")
    func noCollectionsAtAll() throws {
        let record = SyncRecords.record(forCollections: [], in: zone)

        #expect(record["made"] is Data)
        #expect(SyncRecords.collectionNames(from: record) == [])
    }

    @Test("What an earlier version wrote as a list is still the reader's")
    func theOldShape() throws {
        // Written before the field moved to data, still on the server, and
        // still a filing the reader made.
        let record = CKRecord(
            recordType: SyncRecords.RecordType.mark,
            recordID: CKRecord.ID(recordName: "mark-old", zoneID: zone)
        )
        record["feedURL"] = "https://feeds.example.com/f.xml"
        record["guid"] = "urn:example:4"
        record["collections"] = ["Thèse"]

        #expect(try #require(SyncRecords.mark(from: record)).collections == ["Thèse"])
    }

    @Test("A block of read states survives the wire")
    func readStateRoundTrip() throws {
        let fingerprints = Set((0..<400).map { ArticleFingerprint(value: UInt64($0) &* 2_654_435_761) })
        let block = ReadStateBlock(period: "2026-08", fingerprints: fingerprints)

        let record = SyncRecords.record(for: block, in: zone)
        #expect(SyncRecords.readStateBlock(from: record) == block)
    }
}

@Suite("Two devices")
struct SyncPayloadTests {
    private let zone = CKRecordZone.ID(zoneName: SyncRecords.zoneName, ownerName: CKCurrentUserDefaultName)
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    @Test("A second device is set up from records alone, with no bulk transfer")
    func settingUpASecondDevice() async throws {
        let first = try Device(zone: zone)
        let second = try Device(zone: zone)

        let feed = try await first.subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "Le Quotidien", folder: "Presse")
        ).feed
        let kept = try await first.add("urn:1", to: feed, title: "Une réforme", published: now)
        try await first.add("urn:2", to: feed, title: "Autre chose", published: now)
        try await first.articles.setStarred([kept.id], to: true)
        try await first.articles.setRead([kept.id], to: true)
        _ = try await first.readStates.compact(at: now)

        let records = try await first.payload.everything()
        let applied = try await second.payload.apply(records)

        // A feed, a marked article, one block of read states, and one block of
        // the stream : two articles of one feed on one day travel as a single
        // record, not as two. That is the budget, and it is what lets the whole
        // stream travel at all.
        #expect(records.count == 4)
        #expect(records.filter { $0.recordType == SyncRecords.RecordType.catchUp }.count == 1)
        #expect(applied.feeds == 1)
        #expect(applied.markedArticles == 1)

        #expect(try await second.subscriptions.feeds().map(\.title) == ["Le Quotidien"])
        #expect(try await second.subscriptions.feeds().first?.folder == "Presse")
        // And the stream arrives with it, whole : the reader keeps everything
        // on every device, which is what section 7 was amended to say.
        #expect(try await second.articles.count(.all, now: now) == 2)
        #expect(try await second.articles.summaries(in: .builtIn(.starred)).map(\.title) == ["Une réforme"])
        let arrived = try #require(await second.articles.summaries(.all, now: now).first)
        #expect(try await second.articles.article(id: arrived.id)?.bodyHTML == "<p>Un corps.</p>")
    }

    @Test("The stream is sent, but never one record per article")
    func theStreamTravelsCompacted() async throws {
        let first = try Device(zone: zone)
        let feed = try await first.subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "A")
        ).feed
        for index in 0..<50 {
            try await first.add("urn:\(index)", to: feed, title: "Article \(index)", published: now)
        }

        let records = try await first.payload.everything()
        let blocks = records.filter { $0.recordType == SyncRecords.RecordType.catchUp }

        // Fifty articles of one feed on one day : one record. The specification
        // is blunt about the alternative, and this is the whole reason the
        // stream can travel without the count going to a hundred thousand.
        #expect(records.count == 2)
        #expect(blocks.count == 1)
    }

    @Test("A day too big for one record is cut into as many as it needs")
    func aBusyDayIsChunked() async throws {
        let first = try Device(zone: zone)
        let feed = try await first.subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "A")
        ).feed
        // Bodies that do not compress, so the cut is by bytes and not by luck.
        for index in 0..<60 {
            try await first.add(
                "urn:\(index)",
                to: feed,
                title: "Article \(index)",
                published: now,
                body: String((0..<20_000).map { _ in "abcdefghijklmnopqrstuvwxyz".randomElement()! })
            )
        }

        let blocks = try await first.payload.everything()
            .filter { $0.recordType == SyncRecords.RecordType.catchUp }

        #expect(blocks.count > 1)
        // Every one of them inside what CloudKit takes, which is what the cut
        // is for.
        for block in blocks {
            #expect((block["headers"] as? Data)?.count ?? 0 <= CatchUpHeaders.chunkLimit)
        }
        // And no article is lost in the cutting.
        let second = try Device(zone: zone)
        _ = try await second.payload.apply(try await first.payload.everything())
        #expect(try await second.articles.count(.all, now: now) == 60)
    }

    @Test("An article read on one device arrives read on the other, whenever it arrives")
    func readStatesTravel() async throws {
        let first = try Device(zone: zone)
        let second = try Device(zone: zone)

        let feed = try await first.subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "A")
        ).feed
        let read = try await first.add("urn:1", to: feed, title: "Lu ici", published: now)
        try await first.add("urn:2", to: feed, title: "Pas lu", published: now)
        try await first.articles.setRead([read.id], to: true)

        // The second device follows the same feed and already has one article.
        let sameFeed = try await second.subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "A")
        ).feed
        try await second.add("urn:1", to: sameFeed, title: "Lu ici", published: now)

        let records = try await first.payload.readStateChanges(at: now)
        try await second.payload.apply(records)

        #expect(try await second.articles.count(.unread, now: now) == 0)

        // And the article it had not fetched yet arrives read when it does.
        let fingerprints = try await second.readStates.fingerprints()
        #expect(fingerprints.count == 1)
    }

    @Test("Applying the same records twice changes nothing the second time")
    func applyingIsIdempotent() async throws {
        let first = try Device(zone: zone)
        let second = try Device(zone: zone)

        let feed = try await first.subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "A")
        ).feed
        let kept = try await first.add("urn:1", to: feed, title: "Gardé", published: now)
        try await first.articles.setStarred([kept.id], to: true)

        let records = try await first.payload.everything()
        try await second.payload.apply(records)
        let again = try await second.payload.apply(records)

        #expect(again.isEmpty)
        #expect(try await second.subscriptions.count() == 1)
        #expect(try await second.articles.summaries(in: .builtIn(.starred)).count == 1)
    }

    @Test("What one device lets go of, the other lets go of too")
    func deletionsTravel() async throws {
        let first = try Device(zone: zone)
        let second = try Device(zone: zone)

        let feed = try await first.subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "A")
        ).feed
        let kept = try await first.add("urn:1", to: feed, title: "Gardé", published: now)
        try await first.articles.setStarred([kept.id], to: true)
        try await first.collections.add([kept.id], to: "Thèse", at: now)
        try await second.payload.apply(try await first.payload.everything())

        // The article is already in the second device's stream, since the
        // stream travels now, and starred by the record that arrived with it.
        #expect(try await second.articles.summaries(.starred, now: now).count == 1)
        #expect(try await second.collections.made().first?.count == 1)

        // Unmarking an article deletes its record, and the deletion is what
        // carries the `no` : there is nothing left to send that would say it.
        let markName = SyncRecords.name(forMarkWithGUID: "urn:1", feedURL: feed.url)
        let removed = try await second.payload.apply(deletions: [markName])

        #expect(removed.removed == 1)
        #expect(try await second.articles.summaries(.starred, now: now).isEmpty)
        // The article itself stays. It was never the mark.
        #expect(try await second.articles.count(.all, now: now) == 1)
        #expect(try await second.collections.made().first?.count == 0)
    }

    @Test("A device that was switched off learns what it missed")
    func catchUp() async throws {
        let first = try Device(zone: zone)
        let second = try Device(zone: zone)

        let feed = try await first.subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "A")
        ).feed
        try await first.add("urn:1", to: feed, title: "Pendant l'absence", published: now)
        try await first.add("urn:2", to: feed, title: "Aussi", published: now)

        // The other device follows the feed and holds none of it, which is
        // what a device switched off for a week comes back to.
        let records = try await first.payload.everything()
        try await second.payload.apply(records.filter { $0.recordType == SyncRecords.RecordType.feed })

        let changes = try await first.payload.catchUpChanges(now: now)
        let applied = try await second.payload.apply(changes.records)

        #expect(changes.records.count == 1)
        #expect(applied.caughtUp == 2)

        let summaries = try await second.articles.summaries(.all, now: now)
        #expect(summaries.map(\.title).sorted() == ["Aussi", "Pendant l'absence"])
        // And readable on arrival. The body travels with the article now, so a
        // caught-up piece is not a title waiting on a fetch that may find the
        // article gone from its feed.
        let newest = try #require(summaries.first)
        let article = try #require(await second.articles.article(id: newest.id))
        #expect(article.bodyHTML == "<p>Un corps.</p>")
    }

    @Test("A header for a feed nobody follows is not an invitation to follow it")
    func catchUpStaysWithinTheSubscriptions() async throws {
        let first = try Device(zone: zone)
        let second = try Device(zone: zone)

        let feed = try await first.subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "A")
        ).feed
        try await first.add("urn:1", to: feed, title: "Un article", published: now)

        let changes = try await first.payload.catchUpChanges(now: now)
        let applied = try await second.payload.apply(changes.records)

        #expect(applied.caughtUp == 0)
        #expect(try await second.articles.count(.all, now: now) == 0)
    }

    @Test("An article caught up on arrives read when it was read elsewhere")
    func catchUpRespectsReadStates() async throws {
        let first = try Device(zone: zone)
        let second = try Device(zone: zone)

        let feed = try await first.subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "A")
        ).feed
        let read = try await first.add("urn:1", to: feed, title: "Déjà lu ailleurs", published: now)
        try await first.articles.setRead([read.id], to: true)
        _ = try await first.readStates.compact(at: now)

        try await second.payload.apply(try await first.payload.everything())
        let changes = try await first.payload.catchUpChanges(now: now)
        try await second.payload.apply(changes.records)

        #expect(try await second.articles.count(.all, now: now) == 1)
        #expect(try await second.articles.count(.unread, now: now) == 0)
    }

    @Test("Two devices marking the same article write one record")
    func concurrentMarking() async throws {
        let first = try Device(zone: zone)
        let second = try Device(zone: zone)

        for device in [first, second] {
            let feed = try await device.subscriptions.subscribe(
                to: Subscription(address: "https://feeds.example.com/f.xml", title: "A")
            ).feed
            let entry = try await device.add("urn:1", to: feed, title: "Gardé des deux côtés", published: now)
            try await device.articles.setStarred([entry.id], to: true)
        }

        // Both wrote a record ; both computed the same name for it, so CloudKit
        // saw one record and not two.
        let fromFirst = try await first.payload.everything()
        let fromSecond = try await second.payload.everything()
        #expect(fromFirst.map(\.recordID.recordName).sorted() == fromSecond.map(\.recordID.recordName).sorted())

        try await second.payload.apply(fromFirst)
        #expect(try await second.articles.summaries(in: .builtIn(.starred)).count == 1)
    }

    // MARK: - What the server said

    @Test("A record to save carries the tag the server gave it")
    func rebasing() throws {
        let zone = CKRecordZone.ID(zoneName: "Flong", ownerName: CKCurrentUserDefaultName)
        let id = CKRecord.ID(recordName: "read-read-2026-08", zoneID: zone)

        // The record as the server handed it back, kept the way the store keeps it.
        let fromServer = CKRecord(recordType: "ReadState", recordID: id)
        fromServer["period"] = "2026-08"
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        fromServer.encodeSystemFields(with: coder)
        coder.finishEncoding()

        // The record as this device builds it, which knows nothing of the server.
        let built = CKRecord(recordType: "ReadState", recordID: id)
        built["period"] = "2026-08"
        built["fingerprints"] = Data([1, 2, 3])

        let rebased = SyncRecords.rebased(built, onto: coder.encodedData)

        #expect(rebased.recordID == id)
        #expect(rebased["fingerprints"] as? Data == Data([1, 2, 3]))
        // The system fields came from the server's copy, not from the built one.
        #expect(rebased !== built)
    }

    @Test("A record the server has never mentioned is sent as it is")
    func rebasingWithoutATag() {
        let zone = CKRecordZone.ID(zoneName: "Flong", ownerName: CKCurrentUserDefaultName)
        let built = CKRecord(recordType: "Feed", recordID: CKRecord.ID(recordName: "feed-1", zoneID: zone))

        #expect(SyncRecords.rebased(built, onto: nil) === built)
        #expect(SyncRecords.rebased(built, onto: Data([0, 1, 2])) === built)
    }

    @Test("An archive for another record is not used for this one")
    func rebasingOntoTheWrongRecord() throws {
        let zone = CKRecordZone.ID(zoneName: "Flong", ownerName: CKCurrentUserDefaultName)
        let other = CKRecord(recordType: "Feed", recordID: CKRecord.ID(recordName: "feed-2", zoneID: zone))
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        other.encodeSystemFields(with: coder)
        coder.finishEncoding()

        let built = CKRecord(recordType: "Feed", recordID: CKRecord.ID(recordName: "feed-1", zoneID: zone))

        #expect(SyncRecords.rebased(built, onto: coder.encodedData) === built)
    }

    @Test("What the server said is kept, given back and forgotten")
    func rememberingTags() async throws {
        let database = try AppDatabase.inMemory()
        let state = SyncState(database)
        let zone = CKRecordZone.ID(zoneName: "Flong", ownerName: CKCurrentUserDefaultName)

        let records = ["feed-1", "read-read-2026-08"].map {
            CKRecord(recordType: "Feed", recordID: CKRecord.ID(recordName: $0, zoneID: zone))
        }

        try await state.remember(records)
        let kept = try await state.systemFields(for: ["feed-1", "read-read-2026-08", "never-seen"])

        #expect(kept.count == 2)
        #expect(kept["feed-1"] != nil)
        #expect(kept["never-seen"] == nil)

        try await state.forget(["feed-1"])
        let remaining = try await state.systemFields(for: ["feed-1", "read-read-2026-08"])
        #expect(remaining.keys.sorted() == ["read-read-2026-08"])

        try await state.forgetEveryRecord()
        let none = try await state.systemFields(for: ["read-read-2026-08"])
        #expect(none.isEmpty)
    }
}
