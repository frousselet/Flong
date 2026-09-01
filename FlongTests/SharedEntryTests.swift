//
//  SharedEntryTests.swift
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

/// What crosses between two people, and what is done to it on arrival.
@Suite("Shared entries")
struct SharedEntryTests {

    // MARK: - What arrives from somebody else

    @Test("A run of text where a headline was expected is cut to a headline")
    func boundsALongTitle() {
        let entry = SharedEntry(guid: "a", title: String(repeating: "x", count: 100_000)).received
        #expect(entry.title.count == 500)
    }

    @Test("An excerpt far longer than an excerpt is cut down")
    func boundsALongExcerpt() {
        let entry = SharedEntry(guid: "a", title: "A", excerpt: String(repeating: "y", count: 500_000)).received
        #expect(entry.excerpt?.count == 1000)
    }

    /// A run of these rewrites the text around it, so a headline could reorder
    /// the headlines above and below it on the page.
    @Test("Direction overrides and control characters are taken out")
    func removesOverrides() {
        let entry = SharedEntry(guid: "a", title: "Hello\u{202E}dlrow\u{202C}\u{0007}").received
        #expect(entry.title == "Hellodlrow")
    }

    @Test("A title left with nothing in it is a title the entry cannot be kept by")
    func refusesAnEmptyTitle() {
        let entry = SharedEntry(guid: "a", title: "\u{202E}\u{202C}").received
        #expect(entry.title.isEmpty)
        #expect(!entry.isUsable)
    }

    @Test("An entry with no identity is not usable")
    func refusesAMissingGUID() {
        #expect(!SharedEntry(guid: "", title: "A headline").received.isUsable)
        #expect(SharedEntry(guid: "a", title: "A headline").received.isUsable)
    }

    /// An address to run rather than to read, arriving from another person.
    @Test("An address that is not http or https is dropped")
    func refusesAnExecutableAddress() {
        for address in ["javascript:alert(1)", "data:text/html,<script>x</script>", "file:///etc/passwd"] {
            let entry = SharedEntry(guid: "a", title: "A", url: address, imageURL: address).received
            #expect(entry.url == nil, "kept \(address)")
            #expect(entry.imageURL == nil, "kept \(address)")
        }
    }

    @Test("An ordinary address survives arrival")
    func keepsAPlainAddress() {
        let entry = SharedEntry(guid: "a", title: "A", url: "https://example.com/article/1").received
        #expect(entry.url == "https://example.com/article/1")
    }

    @Test("An address with no host is not an address")
    func refusesAHostlessAddress() {
        #expect(SharedEntry(guid: "a", title: "A", url: "https:///nothing").received.url == nil)
    }

    @Test("Whitespace around a field is not part of it")
    func trimsFields() {
        let entry = SharedEntry(guid: "a", title: "  A headline  ", author: "  Somebody  ").received
        #expect(entry.title == "A headline")
        #expect(entry.author == "Somebody")
    }

    // MARK: - The wire

    @Test("A list goes out and comes back as what went in")
    func survivesTheWire() throws {
        let entries = [
            SharedEntry(
                guid: "one", title: "First", url: "https://example.com/1", excerpt: "An excerpt",
                author: "Somebody", publishedAt: nil, imageURL: "https://example.com/1.jpg",
                feedURL: "https://example.com/feed", sourceTitle: "Example"
            ),
            SharedEntry(guid: "two", title: "Second"),
        ]
        let zone = CKRecordZone.ID(zoneName: "shared-1", ownerName: CKCurrentUserDefaultName)
        let records = SharedList.records(for: entries, by: CKRecord.ID(recordName: "_someone"), in: zone)

        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.recordType == SyncRecords.RecordType.sharedList)
        #expect(SharedList.entries(from: record) == entries)
    }

    /// Emptying a list is a change that has to travel, so the record is still
    /// written : one that stopped being written would leave every other
    /// participant showing what was taken out.
    @Test("A list emptied is still a record")
    func writesAnEmptyList() {
        let zone = CKRecordZone.ID(zoneName: "shared-1", ownerName: CKCurrentUserDefaultName)
        let records = SharedList.records(for: [], by: CKRecord.ID(recordName: "_someone"), in: zone)

        #expect(records.count == 1)
        #expect(SharedList.entries(from: records[0]).isEmpty)
    }

    @Test("A list too big for one record is cut into several, and loses nothing")
    func chunksALongList() {
        let entries = (0..<4000).map {
            SharedEntry(guid: "guid-\($0)", title: "Headline \($0)", excerpt: String(repeating: "e", count: 300))
        }
        let zone = CKRecordZone.ID(zoneName: "shared-1", ownerName: CKCurrentUserDefaultName)
        let records = SharedList.records(for: entries, by: CKRecord.ID(recordName: "_someone"), in: zone)

        #expect(records.count > 1)
        #expect(Set(records.map(\.recordID.recordName)).count == records.count)
        #expect(records.flatMap(SharedList.entries(from:)) == entries)
    }

    @Test("Two devices of one person write one list between them")
    func namesAListAfterThePerson() {
        let participant = CKRecord.ID(recordName: "_abc123")
        let other = CKRecord.ID(recordName: "_def456")

        #expect(
            SyncRecords.name(forSharedListBy: participant) == SyncRecords.name(forSharedListBy: participant)
        )
        #expect(SyncRecords.name(forSharedListBy: participant) != SyncRecords.name(forSharedListBy: other))
    }

    /// The record name is a digest, so the participant's own identifier is not
    /// readable from what is written down.
    @Test("A list is not named in a way that gives the person away")
    func doesNotSpellThePersonOut() {
        let name = SyncRecords.name(forSharedListBy: CKRecord.ID(recordName: "_abc123"))
        #expect(!name.contains("_abc123"))
    }

    /// The one thing a modification and a deletion of a list have in common :
    /// a record that is deleted arrives as an identifier and nothing else.
    @Test("Every chunk of one person's list answers to the same key")
    func keysEveryChunkTheSame() {
        let participant = CKRecord.ID(recordName: "_abc123")
        let keys = (0..<3).map {
            SyncRecords.listKey(ofRecordNamed: SyncRecords.name(forSharedListBy: participant, chunk: $0))
        }

        #expect(Set(keys).count == 1)
        #expect(keys[0] == SyncRecords.namePrefix(forSharedListBy: participant))
    }

    @Test("Two people's lists do not answer to the same key")
    func keysTwoPeopleApart() {
        let one = SyncRecords.listKey(ofRecordNamed: SyncRecords.name(forSharedListBy: CKRecord.ID(recordName: "_a")))
        let other = SyncRecords.listKey(ofRecordNamed: SyncRecords.name(forSharedListBy: CKRecord.ID(recordName: "_b")))

        #expect(one != nil)
        #expect(one != other)
    }

    /// Nothing else in a shared zone is a list, and reading one as an emptied
    /// list would delete somebody's articles on a record that is not theirs.
    @Test("A record that is not a list has no list key")
    func keysNothingElse() {
        #expect(SyncRecords.listKey(ofRecordNamed: SyncRecords.sharedCollectionName) == nil)
        #expect(SyncRecords.listKey(ofRecordNamed: CKRecordNameZoneWideShare) == nil)
        #expect(SyncRecords.listKey(ofRecordNamed: "list-") == nil)
        #expect(SyncRecords.listKey(ofRecordNamed: "") == nil)
    }

    @Test("A record another kind of record is not read as a list")
    func refusesAnotherRecordType() {
        let zone = CKRecordZone.ID(zoneName: "shared-1", ownerName: CKCurrentUserDefaultName)
        let record = CKRecord(
            recordType: SyncRecords.RecordType.feed,
            recordID: CKRecord.ID(recordName: "list-x-0", zoneID: zone)
        )
        #expect(SharedList.entries(from: record).isEmpty)
    }

    @Test("Nonsense in the field is no entries rather than a crash")
    func refusesRubbish() {
        let zone = CKRecordZone.ID(zoneName: "shared-1", ownerName: CKCurrentUserDefaultName)
        let record = CKRecord(
            recordType: SyncRecords.RecordType.sharedList,
            recordID: CKRecord.ID(recordName: "list-x-0", zoneID: zone)
        )
        record["entries"] = Data("not json at all".utf8)
        #expect(SharedList.entries(from: record).isEmpty)
    }

    /// Everything on the wire came off somebody else's device, so nothing is
    /// trusted for having been written by a copy of this application.
    @Test("What arrives on the wire is bounded, not taken as sent")
    func boundsWhatArrives() throws {
        let hostile = SharedEntry(
            guid: "one",
            title: String(repeating: "x", count: 50_000),
            url: "javascript:alert(1)",
            excerpt: "fine"
        )
        let zone = CKRecordZone.ID(zoneName: "shared-1", ownerName: CKCurrentUserDefaultName)
        let records = SharedList.records(for: [hostile], by: CKRecord.ID(recordName: "_someone"), in: zone)

        let received = try #require(SharedList.entries(from: records[0]).first)
        #expect(received.title.count == 500)
        #expect(received.url == nil)
    }
}

// MARK: - What goes out of the store

@Suite("Sharing what was filed")
struct SharedEntryStoreTests {

    private func database() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    @Test("A filed article goes out with its excerpt and never a body")
    func sendsTheExcerpt() async throws {
        let database = try database()
        let feed = try await feed(in: database, url: "https://feeds.example.com/rss")
        try await article(
            in: database, feed: feed, guid: "one", title: "A headline",
            url: "https://example.com/1", excerpt: "What the feed sent", body: "<p>The whole article</p>"
        )
        try await file(in: database, guid: "one", into: "Typography")

        let entries = try await SharedEntry.entries(
            in: database, collectionNamed: "Typography", credentials: MemoryCredentials()
        )

        #expect(entries.count == 1)
        #expect(entries[0].title == "A headline")
        #expect(entries[0].excerpt == "What the feed sent")
        #expect(entries[0].sourceTitle == "Example")
        // There is nowhere in the shape to put one, which is the guarantee.
        #expect(!"\(entries[0])".contains("The whole article"))
    }

    @Test("An article nobody filed does not go out")
    func sendsOnlyWhatWasFiled() async throws {
        let database = try database()
        let feed = try await feed(in: database, url: "https://feeds.example.com/rss")
        try await article(in: database, feed: feed, guid: "one", title: "Filed")
        try await article(in: database, feed: feed, guid: "two", title: "Not filed")
        try await file(in: database, guid: "one", into: "Typography")

        let entries = try await SharedEntry.entries(
            in: database, collectionNamed: "Typography", credentials: MemoryCredentials()
        )
        #expect(entries.map(\.title) == ["Filed"])
    }

    /// The rule of `SecretParameters`, applied by the device that writes.
    @Test("The parameters this reader designated come off on the way out")
    func truncatesOnTheWayOut() async throws {
        let database = try database()
        let feed = try await feed(in: database, url: "https://feeds.example.com/rss")
        try await article(
            in: database, feed: feed, guid: "one", title: "A headline",
            url: "https://example.com/1?token=s3cr3t&page=2&utm_source=x"
        )
        try await file(in: database, guid: "one", into: "Typography")

        let credentials = MemoryCredentials()
        try credentials.setSecretParameters(SecretParameters(["token"]), for: feed)

        let entries = try await SharedEntry.entries(
            in: database, collectionNamed: "Typography", credentials: credentials
        )
        #expect(entries[0].url == "https://example.com/1?page=2")
    }

    @Test("A feed whose address is itself the secret sends no address at all")
    func sendsNoMaskedAddress() async throws {
        let database = try database()
        let real = try #require(URL(string: "https://feeds.example.com/rss?key=s3cr3t"))
        let masked = try #require(MaskedURL.mask(real))
        let feed = try await feed(in: database, url: masked.absoluteString)
        try await article(in: database, feed: feed, guid: "one", title: "A headline")
        try await file(in: database, guid: "one", into: "Typography")

        let entries = try await SharedEntry.entries(
            in: database, collectionNamed: "Typography", credentials: MemoryCredentials()
        )
        #expect(entries[0].feedURL == nil)
        #expect(entries[0].sourceTitle == "Example")
    }

    // MARK: - Keeping what arrived

    @Test("What one person filed replaces what that person had filed before")
    func replacesOnePersonsList() async throws {
        let database = try database()
        let store = SharedEntryStore(database)

        try await store.replace(
            [SharedEntry(guid: "one", title: "First"), SharedEntry(guid: "two", title: "Second")],
            inList: "list-alice-", by: "_alice", inZone: "shared-1"
        )
        try await store.replace(
            [SharedEntry(guid: "one", title: "First")], inList: "list-alice-", by: "_alice", inZone: "shared-1")

        let entries = try await store.entries(inZone: "shared-1")
        #expect(entries.map(\.guid) == ["one"])
    }

    /// One person's removal must not delete everybody's.
    @Test("What one person filed leaves what another person filed alone")
    func leavesTheOthersAlone() async throws {
        let database = try database()
        let store = SharedEntryStore(database)

        try await store.replace(
            [SharedEntry(guid: "one", title: "Alice's")], inList: "list-alice-", by: "_alice", inZone: "shared-1")
        try await store.replace(
            [SharedEntry(guid: "two", title: "Bob's")], inList: "list-bob-", by: "_bob", inZone: "shared-1")
        try await store.replace([], inList: "list-alice-", by: "_alice", inZone: "shared-1")

        let entries = try await store.entries(inZone: "shared-1")
        #expect(entries.map(\.guid) == ["two"])
    }

    @Test("A collection's articles are its own and not another collection's")
    func keepsZonesApart() async throws {
        let database = try database()
        let store = SharedEntryStore(database)

        try await store.replace(
            [SharedEntry(guid: "one", title: "Here")], inList: "list-alice-", by: "_alice", inZone: "shared-1")
        try await store.replace(
            [SharedEntry(guid: "two", title: "There")], inList: "list-alice-", by: "_alice", inZone: "shared-2")

        #expect(try await store.entries(inZone: "shared-1").map(\.guid) == ["one"])
        #expect(try await store.entries(inZone: "shared-2").map(\.guid) == ["two"])
    }

    @Test("A share that has gone takes its articles with it")
    func forgetsAZone() async throws {
        let database = try database()
        let store = SharedEntryStore(database)

        try await store.replace(
            [SharedEntry(guid: "one", title: "Here")], inList: "list-alice-", by: "_alice", inZone: "shared-1")
        try await store.forget(zoneName: "shared-1")

        #expect(try await store.entries(inZone: "shared-1").isEmpty)
    }

    // MARK: - Building a store to read from

    private func feed(in database: AppDatabase, url: String) async throws -> UUID {
        let id = UUID.v7()
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO feed (id, url, title, fetch_count, not_modified_count, failure_count,
                                      reader_mode_enabled, loads_images, is_favourite, created_at)
                    VALUES (?, ?, 'Example', 0, 0, 0, 0, 1, 0, ?)
                    """,
                arguments: [id, url, Date()]
            )
        }
        return id
    }

    private func article(
        in database: AppDatabase,
        feed: UUID,
        guid: String,
        title: String,
        url: String? = nil,
        excerpt: String? = nil,
        body: String? = nil
    ) async throws {
        let id = UUID.v7()
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO entry (id, feed_id, guid, title, url, excerpt, received_at,
                                       is_read, is_starred, is_hidden, has_media)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 0)
                    """,
                arguments: [id, feed, guid, title, url, excerpt, Date()]
            )
            if let body {
                try db.execute(
                    sql: "INSERT INTO entry_body (entry_id, sanitized_html) VALUES (?, ?)",
                    arguments: [id, body]
                )
            }
        }
    }

    private func file(in database: AppDatabase, guid: String, into collection: String) async throws {
        let collections = CollectionStore(database)
        _ = try await collections.create(collection)

        let id: UUID = try await database.writer.read { db in
            try UUID.fetchOne(db, sql: "SELECT id FROM entry WHERE guid = ?", arguments: [guid])!
        }
        try await collections.set([collection], of: id)
    }
}
