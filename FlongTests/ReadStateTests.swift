//
//  ReadStateTests.swift
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

@Suite("Read state blocks")
struct ReadStateBlockTests {
    private let feedURL = URL(string: "https://feeds.example.com/f.xml")!

    private func fingerprints(_ count: Int) -> Set<ArticleFingerprint> {
        Set((0..<count).map { ArticleFingerprint(value: UInt64.random(in: .min ... .max) ^ UInt64($0)) })
    }

    @Test("Two devices work out the same fingerprint without speaking")
    func fingerprintIsDeterministic() {
        let first = ArticleFingerprint(feedURL: feedURL, guid: "urn:example:1")
        let second = ArticleFingerprint(feedURL: feedURL, guid: "urn:example:1")

        #expect(first == second)
        #expect(first != ArticleFingerprint(feedURL: feedURL, guid: "urn:example:2"))
        #expect(
            first != ArticleFingerprint(feedURL: URL(string: "https://other.example/f.xml")!, guid: "urn:example:1"))
    }

    @Test("A block survives the wire")
    func roundTrip() {
        let block = ReadStateBlock(period: "2026-08", fingerprints: fingerprints(500))
        let decoded = ReadStateBlock.decode(block.encoded(), period: "2026-08")

        #expect(decoded == block)
        #expect(decoded.fingerprints.count == 500)
    }

    @Test("An empty block is empty on the wire too")
    func emptyRoundTrip() {
        let block = ReadStateBlock(period: "2026-08")

        #expect(block.encoded().isEmpty)
        #expect(ReadStateBlock.decode(Data(), period: "2026-08").isEmpty)
    }

    @Test("The same set always writes the same bytes")
    func encodingIsStable() {
        let values = fingerprints(200)
        let first = ReadStateBlock(period: "2026-08", fingerprints: values)
        let second = ReadStateBlock(period: "2026-08", fingerprints: Set(values.shuffled()))

        #expect(first.encoded() == second.encoded())
    }

    @Test("Merging is a union, so order and repetition change nothing")
    func mergingIsCommutativeAndIdempotent() {
        let left = ReadStateBlock(period: "2026-08", fingerprints: fingerprints(120))
        let right = ReadStateBlock(period: "2026-08", fingerprints: fingerprints(80))

        #expect(left.merged(with: right) == right.merged(with: left))
        #expect(left.merged(with: right).merged(with: right) == left.merged(with: right))
        #expect(left.merged(with: left) == left)
        #expect(left.merged(with: right).fingerprints.count == 200)
    }

    @Test("A month of a heavy reader still fits in one record")
    func size() {
        // Three thousand articles read in a month is more than anybody reads.
        let block = ReadStateBlock(period: "2026-08", fingerprints: fingerprints(3000))

        #expect(block.encoded().count < 32 * 1024)
    }

    @Test("The period is the month of publication, alike on every device")
    func periods() {
        let date = Date(timeIntervalSince1970: 1_787_646_600)

        #expect(ReadStateBlock.period(for: date) == "2026-08")
        #expect(ReadStateBlock.period(for: nil) == "undated")
    }
}

@Suite("Read states in the store")
struct ReadStateStoreTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let articles: ArticleStore
    private let readStates: ReadStateStore
    private let feed: Feed
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() async throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
        articles = ArticleStore(database)
        readStates = ReadStateStore(database)
        feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "A Feed")
        ).feed
    }

    @discardableResult
    private func add(_ guid: String, published: Date?, isRead: Bool = false) async throws -> Entry {
        var entry = Entry(
            feedID: feed.id,
            guid: guid,
            title: "Article \(guid)",
            publishedAt: published,
            receivedAt: now,
            isRead: isRead
        )
        entry.hasMedia = false
        try await database.writer.write { db in try entry.insert(db) }
        return entry
    }

    @Test("Compacting turns what was read into blocks, by month")
    func compacting() async throws {
        try await add("a", published: now, isRead: true)
        try await add("b", published: now.addingTimeInterval(-40 * 86400), isRead: true)
        try await add("c", published: now, isRead: false)
        try await add("d", published: nil, isRead: true)

        let blocks = try await readStates.compact(at: now)

        #expect(Set(blocks.map(\.period)) == ["2026-08", "2026-07", "undated"])
        #expect(blocks.reduce(0) { $0 + $1.fingerprints.count } == 3)
    }

    @Test("Compacting twice sends nothing the second time")
    func compactingIsQuietWhenNothingChanged() async throws {
        try await add("a", published: now, isRead: true)

        #expect(try await readStates.compact(at: now).count == 1)
        #expect(try await readStates.compact(at: now).isEmpty)
    }

    @Test("A block from elsewhere marks the articles it names")
    func applyingABlock() async throws {
        let read = try await add("a", published: now)
        try await add("b", published: now)

        let block = ReadStateBlock(
            period: "2026-08",
            fingerprints: [ArticleFingerprint(feedURL: feed.url, guid: read.guid)]
        )
        let marked = try await readStates.merge(block, at: now)

        #expect(marked == 1)
        #expect(try await articles.count(.unread, now: now) == 1)
    }

    @Test("A block is remembered, so an article that arrives later arrives read")
    func rememberingForLater() async throws {
        let block = ReadStateBlock(
            period: "2026-08",
            fingerprints: [ArticleFingerprint(feedURL: feed.url, guid: "urn:not-here-yet")]
        )
        #expect(try await readStates.merge(block, at: now) == 0)

        // The article turns up on the next refresh.
        let fingerprints = try await readStates.fingerprints()
        #expect(fingerprints.contains(ArticleFingerprint(feedURL: feed.url, guid: "urn:not-here-yet")))
        #expect(try await readStates.block(period: "2026-08").fingerprints.count == 1)
    }

    @Test("Two devices reading different articles end up agreeing")
    func twoDevices() async throws {
        // What this device read.
        let here = try await add("a", published: now, isRead: true)
        let there = try await add("b", published: now)
        try await add("c", published: now)

        let mine = try await readStates.compact(at: now)

        // What the other device read, arriving as a block.
        let theirs = ReadStateBlock(
            period: "2026-08",
            fingerprints: [ArticleFingerprint(feedURL: feed.url, guid: there.guid)]
        )
        try await readStates.merge(theirs, at: now)

        let merged = try await readStates.block(period: "2026-08")
        #expect(merged.fingerprints.count == 2)
        #expect(merged.contains(ArticleFingerprint(feedURL: feed.url, guid: here.guid)))
        #expect(try await articles.count(.unread, now: now) == 1)

        // And what this device would send now holds both, whichever way round
        // the exchange happened.
        _ = mine
        #expect(try await readStates.compact(at: now).isEmpty)
    }
}
