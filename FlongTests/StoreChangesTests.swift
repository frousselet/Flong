//
//  StoreChangesTests.swift
//  FlongTests
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import Testing

@testable import Flong

/// The window following the store rather than being told by whoever wrote.
///
/// What this buys is everything the window does not do itself : a background
/// refresh, a change arriving from another device, an archive read in, a job
/// finishing. All of those write through the same writer, and none of them used
/// to reach the interface.
@Suite("Following the store")
struct StoreChangesTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore

    init() throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
    }

    /// The next tick, or nothing if none arrives in time.
    private func nextTick(from ticks: AsyncStream<Void>.Iterator) async -> Bool {
        var iterator = ticks
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await iterator.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    @Test("A write nobody asked the window about still reaches it")
    func aWriteTicks() async throws {
        var ticks = StoreChanges.ticks(in: database).makeAsyncIterator()

        // Exactly the shape of a background refresh or a change arriving from
        // iCloud : written through the store, with no interface involved.
        _ = try await subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "A")
        )

        #expect(await ticks.next() != nil)
    }

    @Test("An article arriving ticks, and so does one being changed")
    func articles() async throws {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "A")
        ).feed

        var ticks = StoreChanges.ticks(in: database).makeAsyncIterator()

        var entry = Entry(feedID: feed.id, guid: "urn:1", title: "Un article")
        entry.hasMedia = false
        try await database.writer.write { db in try entry.insert(db) }
        #expect(await ticks.next() != nil)

        // Not only insertions : a star or a read state set by another device is
        // a change the window has to show too.
        try await ArticleStore(database).setStarred([entry.id], to: true)
        #expect(await ticks.next() != nil)
    }

    @Test("The machinery writing down where it got to does not tick")
    func machinery() async throws {
        var ticks = StoreChanges.ticks(in: database).makeAsyncIterator()

        // A change token moving says nothing a reader can see, and a window
        // that reloaded for it would reload constantly and show the same page.
        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO archive_ingest (name, modified_at, ingested_at) VALUES (?, ?, ?)",
                arguments: ["device/2026-08-30.json", Date(), Date()]
            )
        }

        #expect(!StoreChanges.watched.contains("archive_ingest"))
        #expect(!StoreChanges.watched.contains("sync_state"))
        _ = ticks
    }

    @Test("A burst collapses into one tick rather than one per transaction")
    func burst() async throws {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "A")
        ).feed

        let stream = StoreChanges.ticks(in: database)
        var ticks = stream.makeAsyncIterator()

        // Three hundred feeds refreshing is three hundred transactions, and the
        // window needs one reload. The stream keeps only the most recent tick.
        for index in 0..<40 {
            var entry = Entry(feedID: feed.id, guid: "urn:\(index)", title: "Article \(index)")
            entry.hasMedia = false
            try await database.writer.write { db in try entry.insert(db) }
        }

        #expect(await ticks.next() != nil)
        // Only what the buffer kept, which is one, is waiting.
        #expect(await nextTick(from: ticks) == false)
    }
}
