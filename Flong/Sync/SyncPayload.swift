//
//  SyncPayload.swift
//  Flong
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
import OSLog

/// Reads the store for what is worth sending, and writes back what arrives.
///
/// The engine of section 7 owns the scheduling, the batching and the retries.
/// This owns the only two questions the engine cannot answer : what a device has
/// to say, and what it should do with what it hears.
///
/// **What never travels**, as the specification sets out : the articles of the
/// stream, the indexes, the fetching health of a feed, and anything secret. The
/// stream is a cache each device fills for itself, and a copy of it would be
/// both enormous and worthless.
nonisolated struct SyncPayload: Sendable {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let library: LibraryStore
    private let readStates: ReadStateStore
    private let zone: CKRecordZone.ID

    init(_ database: AppDatabase, zone: CKRecordZone.ID) {
        self.database = database
        self.subscriptions = SubscriptionStore(database)
        self.library = LibraryStore(database)
        self.readStates = ReadStateStore(database)
        self.zone = zone
    }

    // MARK: - Sending

    /// Everything this device would say if it had never spoken.
    ///
    /// Around three thousand records for three years of reading : a few hundred
    /// feeds, a couple of thousand kept articles, and a few dozen blocks of read
    /// states. Never one record per article, which is the whole design.
    func everything() async throws -> [CKRecord] {
        var records: [CKRecord] = []

        for feed in try await subscriptions.feeds() {
            records.append(SyncRecords.record(for: feed, in: zone))
        }
        for item in try await library.allItems() {
            records.append(SyncRecords.record(for: item, in: zone))
        }
        for block in try await readStates.blocks() {
            records.append(SyncRecords.record(for: block, in: zone))
        }

        return records
    }

    /// The read states that have changed since they were last compacted.
    func readStateChanges(at date: Date = Date()) async throws -> [CKRecord] {
        try await readStates.compact(at: date).map { SyncRecords.record(for: $0, in: zone) }
    }

    // MARK: - Receiving

    /// What applying a batch came to.
    nonisolated struct Applied: Hashable, Sendable {
        var feeds = 0
        var libraryItems = 0
        var readArticles = 0
        var removed = 0

        var isEmpty: Bool { feeds == 0 && libraryItems == 0 && readArticles == 0 && removed == 0 }
    }

    /// Writes records from elsewhere into this device's store.
    ///
    /// Everything here is idempotent. A record that arrives twice, or that this
    /// device wrote itself, changes nothing the second time, which is what lets
    /// the engine replay a batch after a failure without a second thought.
    @discardableResult
    func apply(_ records: [CKRecord]) async throws -> Applied {
        var applied = Applied()

        for record in records {
            switch record.recordType {
            case SyncRecords.RecordType.feed:
                guard let subscription = SyncRecords.subscription(from: record) else { continue }
                if try await subscriptions.subscribe(to: subscription).isNew { applied.feeds += 1 }

            case SyncRecords.RecordType.libraryItem:
                guard let item = SyncRecords.libraryItem(from: record) else { continue }
                if try await keep(item) { applied.libraryItems += 1 }

            case SyncRecords.RecordType.readState:
                guard let block = SyncRecords.readStateBlock(from: record) else { continue }
                applied.readArticles += try await readStates.merge(block)

            default:
                continue
            }
        }

        return applied
    }

    /// Removes what another device deleted.
    @discardableResult
    func apply(deletions names: [String]) async throws -> Applied {
        var applied = Applied()

        for name in names {
            if name.hasPrefix("feed-") {
                if try await unsubscribe(named: name) { applied.removed += 1 }
            } else if name.hasPrefix("item-") {
                if try await release(named: name) { applied.removed += 1 }
            }
        }

        return applied
    }

    /// Keeps an article another device kept, and stars it here if it is here.
    private func keep(_ item: LibraryItem) async throws -> Bool {
        try await database.writer.write { db in
            let existing =
                try LibraryItem
                .filter(LibraryItem.Columns.guid == item.guid && LibraryItem.Columns.feedURL == item.feedURL)
                .fetchOne(db)

            // The article may be in this device's stream, in which case its star
            // has to agree with the library.
            let entryID = try Self.entryID(forGUID: item.guid, feedURL: item.feedURL, in: db)
            if let entryID {
                _ = try Entry.filter(key: entryID).updateAll(db, Column("is_starred").set(to: true))
            }

            if var existing {
                // The article may have reached this device's stream after the
                // record did, in which case the link is made now.
                guard existing.entryID == nil, entryID != nil else { return false }
                existing.entryID = entryID
                try existing.update(db)
                return false
            }

            var item = item
            item.entryID = entryID
            try item.insert(db)
            return true
        }
    }

    private func unsubscribe(named name: String) async throws -> Bool {
        try await database.writer.write { db in
            let feeds = try Feed.fetchAll(db)
            guard let feed = feeds.first(where: { SyncRecords.name(forFeed: $0.url) == name }) else { return false }
            return try Feed.deleteOne(db, key: feed.id)
        }
    }

    private func release(named name: String) async throws -> Bool {
        try await database.writer.write { db in
            let items = try LibraryItem.fetchAll(db)
            let match = items.first {
                SyncRecords.name(forLibraryItemWithGUID: $0.guid, feedURL: $0.feedURL) == name
            }
            guard let match else { return false }

            // The star follows the library, whether or not the copy remembers
            // which stream row it came from.
            let entryID = try match.entryID ?? Self.entryID(forGUID: match.guid, feedURL: match.feedURL, in: db)
            if let entryID {
                _ = try Entry.filter(key: entryID).updateAll(db, Column("is_starred").set(to: false))
            }
            return try LibraryItem.deleteOne(db, key: match.id)
        }
    }

    private static func entryID(forGUID guid: String, feedURL: URL?, in db: Database) throws -> UUID? {
        guard let feedURL else { return nil }
        return try UUID.fetchOne(
            db,
            sql: """
                SELECT e.id FROM entry e JOIN feed f ON f.id = e.feed_id
                WHERE e.guid = ? AND f.url = ?
                """,
            arguments: [guid, feedURL.absoluteString]
        )
    }
}
