//
//  CollectionItemTests.swift
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

/// A collection read as one list : what the reader filed, what somebody else
/// filed, and what the owner has taken out of it.
@Suite("What is in a collection")
struct CollectionItemTests {
    private let zone = "shared-0199b0d0-0000-7000-8000-000000000010"

    /// An article of the reader's own, as a list reads one out of the store.
    ///
    /// Built from a row rather than field by field, since that is the only way
    /// one is ever made : the columns a list needs are what ``ArticleSummary``
    /// decodes, and a second way in would be a second thing to keep true.
    private func summary(_ title: String, at date: Date, id: UUID = UUID.v7()) -> ArticleSummary {
        ArticleSummary(
            row: [
                "id": id,
                "feed_title": "Le Monde",
                "title": title,
                "date": date,
                "published_at": date,
                "is_read": false,
                "is_starred": false,
                "has_media": false,
                "url": "https://lemonde.fr/\(title)",
                "site_url": "https://lemonde.fr",
                "feed_url": "https://lemonde.fr/rss",
            ]
        )
    }

    private func entry(_ guid: String, at date: Date?, received: Date? = nil) -> SharedEntry {
        SharedEntry(
            guid: guid,
            title: guid,
            url: "https://liberation.fr/\(guid)",
            publishedAt: date,
            receivedAt: received
        )
    }

    private let noon = Date(timeIntervalSince1970: 1_756_800_000)

    // MARK: - One list

    /// The whole point : a reader going back to something they saw yesterday
    /// does not remember which of them put it there.
    @Test("What the reader filed and what somebody else filed are one run of rows")
    func mergesIntoOneList() {
        let items = CollectionItem.merge(
            held: [summary("mine", at: noon)],
            sent: [entry("theirs", at: noon.addingTimeInterval(3600))],
            localCopies: [:],
            key: { _ in nil }
        )

        #expect(items.count == 2)
        #expect(items.first?.guid == "theirs")
        if case .held = items.last {} else { Issue.record("The reader's own article is the older of the two") }
    }

    /// Plenty of feeds date nothing, and an excerpt that arrived this morning
    /// does not belong under last year's pieces.
    @Test("An excerpt no feed dated sorts by when it arrived")
    func sortsAnUndatedExcerptByItsArrival() {
        let items = CollectionItem.merge(
            held: [summary("old", at: noon.addingTimeInterval(-86400))],
            sent: [entry("undated", at: nil, received: noon)],
            localCopies: [:],
            key: { _ in nil }
        )

        #expect(items.first?.guid == "undated")
    }

    /// Two pieces published in the same second must not swap places under the
    /// reader between one load and the next.
    @Test("A tie is broken the same way every time")
    func ordersTiesStably() {
        let sent = [entry("b", at: noon), entry("a", at: noon)]
        let once = CollectionItem.merge(held: [], sent: sent, localCopies: [:], key: { _ in nil })
        let again = CollectionItem.merge(held: [], sent: sent.reversed(), localCopies: [:], key: { _ in nil })

        #expect(once.map(\.id) == again.map(\.id))
    }

    // MARK: - The reader's own copy of a piece

    /// The specification asks for theirs to be the one shown : with its body,
    /// its read state and their marks, rather than three hundred characters.
    @Test("An excerpt gives way to the reader's own copy of the piece")
    func prefersTheReadersOwnCopy() {
        let mine = summary("shared", at: noon)
        let items = CollectionItem.merge(
            held: [],
            sent: [entry("theirs", at: noon)],
            localCopies: ["key": mine],
            key: { _ in "key" }
        )

        #expect(items.count == 1)
        if case .held(let article) = items.first {
            #expect(article.id == mine.id)
        } else {
            Issue.record("The reader's own article stands in for the excerpt")
        }
    }

    /// A piece the reader filed and somebody else filed too is one row, not the
    /// same headline twice.
    @Test("A piece both of them filed is one row")
    func doesNotShowTheSamePieceTwice() {
        let mine = summary("shared", at: noon)
        let items = CollectionItem.merge(
            held: [mine],
            sent: [entry("theirs", at: noon)],
            localCopies: ["key": mine],
            key: { _ in "key" }
        )

        #expect(items.count == 1)
        #expect(items.first?.id == "held-" + mine.id.uuidString)
    }

    // MARK: - What the owner took out

    @Test("A removal is only read off the owner's own record")
    func refusesSomebodyElsesRemovals() {
        let zoneID = CKRecordZone.ID(zoneName: zone, ownerName: "_owner")
        let record = SharedRemovals.record(for: ["a", "b"], by: CKRecord.ID(recordName: "_owner"), in: zoneID)

        // A record made here carries no creator, since the server sets it :
        // what a participant's would look like is a record whose author is not
        // the zone's owner, and that is what has to be refused.
        #expect(SharedRemovals.guids(from: record, ownedBy: nil) == ["a", "b"])
        #expect(SharedRemovals.guids(from: record, ownedBy: "_someone-else") == nil)
    }

    @Test("A record of another kind is not read as a list of removals")
    func refusesAnotherKindOfRecord() {
        let other = CKRecord(
            recordType: SyncRecords.RecordType.sharedList,
            recordID: CKRecord.ID(recordName: "list-abc-0", zoneID: CKRecordZone.ID(zoneName: zone))
        )

        #expect(SharedRemovals.guids(from: other, ownedBy: nil) == nil)
    }

    /// The filer's list still carries the article and their next edit sends it
    /// again : a removal has to survive that or it undoes itself.
    @Test("A removal outlives the list being written again")
    func survivesTheListBeingRewritten() async throws {
        let database = try AppDatabase.inMemory()
        let entries = SharedEntryStore(database)
        let removals = SharedRemovalStore(database)

        let filed = [entry("a", at: noon), entry("b", at: noon)]
        try await entries.replace(filed, inList: "list-x-", by: "_them", inZone: zone)
        try await removals.remove("a", inZone: zone)

        #expect(try await entries.entries(inZone: zone).map(\.guid) == ["b"])

        // The filer edits their list, which sends the whole of it again.
        try await entries.replace(filed, inList: "list-x-", by: "_them", inZone: zone)
        #expect(try await entries.entries(inZone: zone).map(\.guid) == ["b"])
    }

    @Test("Applying the same removal twice does nothing the first did not")
    func isIdempotent() async throws {
        let database = try AppDatabase.inMemory()
        let removals = SharedRemovalStore(database)

        try await removals.apply(["a", "b"], inZone: zone)
        try await removals.apply(["b", "a"], inZone: zone)

        #expect(try await removals.guids(inZone: zone).sorted() == ["a", "b"])
    }

    @Test("One collection's removals are not another's")
    func keepsCollectionsApart() async throws {
        let database = try AppDatabase.inMemory()
        let entries = SharedEntryStore(database)
        let removals = SharedRemovalStore(database)

        try await entries.replace([entry("a", at: noon)], inList: "list-x-", by: "_them", inZone: zone)
        try await entries.replace([entry("a", at: noon)], inList: "list-x-", by: "_them", inZone: "shared-other")
        try await removals.remove("a", inZone: zone)

        #expect(try await entries.entries(inZone: zone).isEmpty)
        #expect(try await entries.entries(inZone: "shared-other").count == 1)
    }

    // MARK: - Already in it, whoever put it there

    /// A third party filing a piece puts it in the collection for everybody :
    /// the reader opening their own copy has to be told so, or the menu offers
    /// to say a thing already said.
    @Test("A piece somebody else filed is found by the reader's own copy of it")
    func findsSomebodyElsesFiling() async throws {
        let database = try AppDatabase.inMemory()
        let entries = SharedEntryStore(database)

        try await entries.replace([entry("theirs", at: noon)], inList: "list-them-", by: "_them", inZone: zone)

        // The same page, under the name the reader's own feed gave it.
        let found = try await entries.filings(ofGUID: "mine", orURL: "https://liberation.fr/theirs")
        #expect(found.map(\.zone) == [zone])
        // Taking it down means naming it as *they* filed it, not as this
        // device knows it.
        #expect(found.map(\.guid) == ["theirs"])
        #expect(found.map(\.list) == ["list-them-"])
    }

    @Test("A piece nobody filed is found nowhere")
    func findsNothingForAPieceNobodyFiled() async throws {
        let database = try AppDatabase.inMemory()
        let entries = SharedEntryStore(database)

        try await entries.replace([entry("theirs", at: noon)], inList: "list-them-", by: "_them", inZone: zone)
        #expect(try await entries.filings(ofGUID: "other", orURL: "https://liberation.fr/other").isEmpty)
    }

    @Test("What the owner took out is not still in it")
    func doesNotFindWhatWasTakenOut() async throws {
        let database = try AppDatabase.inMemory()
        let entries = SharedEntryStore(database)
        let removals = SharedRemovalStore(database)

        try await entries.replace([entry("theirs", at: noon)], inList: "list-them-", by: "_them", inZone: zone)
        try await removals.remove("theirs", inZone: zone)

        #expect(try await entries.filings(ofGUID: "theirs", orURL: nil).isEmpty)
    }

    // MARK: - Opening a piece through the reader's own subscription

    /// The sender took their own token off the link, rightly. The recipient who
    /// follows the same feed has one of their own, sitting in the address of
    /// their own subscription.
    @Test("The reader's own parameters go back on the address")
    func putsTheReadersOwnParametersBack() throws {
        let article = try #require(URL(string: "https://paper.example.com/piece?page=2"))
        let feed = try #require(URL(string: "https://paper.example.com/rss?token=mine&format=rss"))

        let asked = SubscribedURL.of(article, likeFeedAt: feed, secret: SecretParameters(["token"]))
        #expect(asked?.absoluteString == "https://paper.example.com/piece?page=2&token=mine")
    }

    /// A parameter the publisher already put on the address is part of the
    /// address, whatever it is called.
    @Test("Nothing is written over what the address already carries")
    func doesNotOverwriteWhatIsThere() throws {
        let article = try #require(URL(string: "https://paper.example.com/piece?token=theirs"))
        let feed = try #require(URL(string: "https://paper.example.com/rss?token=mine"))

        #expect(SubscribedURL.of(article, likeFeedAt: feed, secret: SecretParameters(["token"])) == nil)
    }

    @Test("A reader who designated nothing asks for the address as it arrived")
    func addsNothingWithoutADesignation() throws {
        let article = try #require(URL(string: "https://paper.example.com/piece"))
        let feed = try #require(URL(string: "https://paper.example.com/rss?token=mine"))

        #expect(SubscribedURL.of(article, likeFeedAt: feed, secret: SecretParameters()) == nil)
        #expect(SubscribedURL.of(article, likeFeedAt: feed, secret: SecretParameters(["other"])) == nil)
    }

    /// What leaves is still stripped : this only puts back what the reader
    /// themselves designated, on the way in.
    @Test("What the sender took off is what the recipient puts back")
    func isTheInverseOfWhatTravels() throws {
        let mine = try #require(URL(string: "https://paper.example.com/piece?token=mine&utm_source=x"))
        let secret = SecretParameters(["token"])

        let sent = PublicURL.of(mine, without: secret)
        #expect(sent.absoluteString == "https://paper.example.com/piece")

        let asked = SubscribedURL.of(sent, likeFeedAt: mine, secret: secret)
        #expect(asked?.absoluteString == "https://paper.example.com/piece?token=mine")
    }

    /// It is never sent, and a record carrying it would be telling the recipient
    /// when the sender happened to be looking.
    @Test("When a device saw an excerpt never travels")
    func doesNotSendTheArrival() throws {
        let sent = entry("a", at: noon, received: noon)
        let payload = try JSONEncoder().encode(sent)

        #expect(!String(decoding: payload, as: UTF8.self).contains("receivedAt"))
        #expect(try JSONDecoder().decode(SharedEntry.self, from: payload).receivedAt == nil)
    }
}
