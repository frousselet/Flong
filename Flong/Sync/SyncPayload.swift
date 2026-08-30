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
    private let embedder: Embedder
    private let state: SyncState
    private let zone: CKRecordZone.ID

    init(_ database: AppDatabase, zone: CKRecordZone.ID) {
        self.database = database
        self.subscriptions = SubscriptionStore(database)
        self.library = LibraryStore(database)
        self.readStates = ReadStateStore(database)
        self.embedder = Embedder()
        self.state = SyncState(database)
        self.zone = zone
    }

    // MARK: - Sending

    /// Everything this device would say if it had never spoken.
    ///
    /// Feeds, kept articles, read states, and the stream itself : one record
    /// per feed and per day rather than one per article, which is what makes
    /// the last of those possible at all. Section 7 was amended to carry the
    /// whole stream, and the shape of the record is what keeps the count in
    /// the thousands where one per article would put it in the hundreds of
    /// thousands.
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
        records += try await CatchUpHeaders.records(in: database, zone: zone)

        return records
    }

    /// The records the engine asked for, by name.
    ///
    /// Names are digests, so they cannot be read backwards : the store is walked
    /// once per batch and the matches are picked out. A batch is a few hundred
    /// records at most, and there are a few thousand rows in total, so one pass
    /// is cheaper than keeping an index of names in step.
    func records(named names: Set<String>) async throws -> [String: CKRecord] {
        guard !names.isEmpty else { return [:] }
        var records: [String: CKRecord] = [:]

        for feed in try await subscriptions.feeds() {
            let name = SyncRecords.name(forFeed: feed.url)
            if names.contains(name) { records[name] = SyncRecords.record(for: feed, in: zone) }
        }
        for item in try await library.allItems() {
            let name = SyncRecords.name(forLibraryItemWithGUID: item.guid, feedURL: item.feedURL)
            if names.contains(name) { records[name] = SyncRecords.record(for: item, in: zone) }
        }
        for block in try await readStates.blocks() {
            let name = SyncRecords.name(forReadStatePeriod: block.period, kind: block.kind)
            if names.contains(name) { records[name] = SyncRecords.record(for: block, in: zone) }
        }

        // Each one starts from what the server last said about it, or the
        // server refuses every save after the first.
        let tags = try await state.systemFields(for: Set(records.keys))
        return records.mapValues { SyncRecords.rebased($0, onto: tags[$0.recordID.recordName]) }
    }

    /// The names of everything this device would send, for the engine to queue.
    func everyRecordName() async throws -> [String] {
        try await everything().map(\.recordID.recordName)
    }

    /// Folds a record the server already had into what is here.
    ///
    /// Only read states can genuinely conflict, two devices adding to the same
    /// month at once, and their merge is a union. Everything else is either
    /// written once or owned by the reader, where the later write is the one
    /// they meant.
    func reconciled(_ server: CKRecord, with attempted: CKRecord) -> CKRecord? {
        guard server.recordType == SyncRecords.RecordType.readState,
            let serverBlock = SyncRecords.readStateBlock(from: server),
            let localBlock = SyncRecords.readStateBlock(from: attempted)
        else { return nil }

        let merged = serverBlock.merged(with: localBlock)
        server["fingerprints"] = merged.encoded()
        return server
    }

    /// The days this device has touched lately, filled whole.
    ///
    /// A recent window, and only for deciding which days are worth rewriting :
    /// a day nothing arrived in since the last push is a day whose record is
    /// already right. The whole history goes out once, through ``everything()``.
    static let recent: TimeInterval = 3 * 24 * 60 * 60

    func catchUpChanges(now: Date = Date()) async throws -> (records: [CKRecord], expired: [String]) {
        let since = now.addingTimeInterval(-Self.recent)
        return (
            try await CatchUpHeaders.records(in: database, since: since, zone: zone),
            try await CatchUpHeaders.expiredNames(in: database, now: now)
        )
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
        /// Articles this device had missed while it was switched off.
        var caughtUp = 0
        var removed = 0

        var isEmpty: Bool {
            feeds == 0 && libraryItems == 0 && readArticles == 0 && caughtUp == 0 && removed == 0
        }
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

            case SyncRecords.RecordType.catchUp:
                let read = try await readStates.fingerprints()
                applied.caughtUp += try await CatchUpHeaders.apply(record, into: database, read: read)

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
    ///
    /// A vector that arrives is kept only when this device runs the same model
    /// at the same revision. Otherwise it is dropped and computed again here :
    /// comparing vectors from two revisions does not fail loudly, it quietly
    /// returns nonsense, and the device that recomputes republishes its version.
    private func keep(_ item: LibraryItem) async throws -> Bool {
        let arriving = Self.vetted(item, with: embedder)

        return try await database.writer.write { db in
            let existing =
                try LibraryItem
                .filter(LibraryItem.Columns.guid == item.guid && LibraryItem.Columns.feedURL == item.feedURL)
                .fetchOne(db)

            // The article may be in this device's stream, in which case its star
            // has to agree with the library.
            let entryID = try Self.entryID(forGUID: arriving.guid, feedURL: arriving.feedURL, in: db)
            if let entryID {
                _ = try Entry.filter(key: entryID).updateAll(db, Column("is_starred").set(to: true))
            }

            if var existing {
                var changed = false

                // The article may have reached this device's stream after the
                // record did, in which case the link is made now.
                if existing.entryID == nil, entryID != nil {
                    existing.entryID = entryID
                    changed = true
                }
                // A vector computed elsewhere spares this device the work.
                if existing.vector == nil, arriving.vector != nil {
                    existing.vector = arriving.vector
                    existing.vectorModel = arriving.vectorModel
                    existing.vectorRevision = arriving.vectorRevision
                    changed = true
                }

                if changed { try existing.update(db) }
                return false
            }

            var item = arriving
            item.entryID = entryID
            try item.insert(db)
            return true
        }
    }

    /// The item as this device may keep it.
    ///
    /// A vector made by another model, or another revision of this one, is
    /// dropped rather than stored : comparing across revisions does not fail
    /// loudly, it quietly returns nonsense. This device computes its own and
    /// republishes it.
    private static func vetted(_ item: LibraryItem, with embedder: Embedder) -> LibraryItem {
        guard let model = item.vectorModel, let revision = item.vectorRevision.flatMap(Int.init),
            !embedder.isCurrent(model: model, revision: revision)
        else { return item }

        var item = item
        item.vector = nil
        item.vectorModel = nil
        item.vectorRevision = nil
        return item
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
