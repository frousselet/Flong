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
    private let marks: MarkStore
    private let collections: CollectionStore
    private let readStates: ReadStateStore
    private let embedder: Embedder
    private let state: SyncState
    private let zone: CKRecordZone.ID

    init(_ database: AppDatabase, zone: CKRecordZone.ID) {
        self.database = database
        self.subscriptions = SubscriptionStore(database)
        self.marks = MarkStore(database)
        self.collections = CollectionStore(database)
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
        for mark in try await marks.all() where !mark.isEmpty {
            records.append(SyncRecords.record(for: mark, in: zone))
        }
        for block in try await readStates.blocks() {
            records.append(SyncRecords.record(for: block, in: zone))
        }
        // Only when there are any. A reader who has made none has nothing to
        // say about them, and an empty record is a record spent on silence.
        let names = try await collections.names()
        let described = try await collections.descriptions()
        if !names.isEmpty || !described.isEmpty {
            records.append(SyncRecords.record(forCollections: names, dynamic: described, in: zone))
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
        for mark in try await marks.all() {
            let name = SyncRecords.name(forMarkWithGUID: mark.guid, feedURL: URL(string: mark.feedURL))
            if names.contains(name) { records[name] = SyncRecords.record(for: mark, in: zone) }
        }
        if names.contains("collections") {
            let made = try await collections.names()
            let described = try await collections.descriptions()
            if !made.isEmpty || !described.isEmpty {
                records["collections"] = SyncRecords.record(forCollections: made, dynamic: described, in: zone)
            }
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
        /// Articles another device said something about : starred, wrote on,
        /// or filed.
        var markedArticles = 0
        var readArticles = 0
        /// Articles this device had missed while it was switched off.
        var caughtUp = 0
        var removed = 0

        var isEmpty: Bool {
            feeds == 0 && markedArticles == 0 && readArticles == 0 && caughtUp == 0 && removed == 0
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

            case SyncRecords.RecordType.mark:
                guard let mark = SyncRecords.mark(from: record) else { continue }
                if try await marks.merge(mark) { applied.markedArticles += 1 }

            case SyncRecords.RecordType.collections:
                guard let names = SyncRecords.collectionNames(from: record) else { continue }
                // Made, never unmade. A name here and not on this device is a
                // collection another device made ; a name on this device and
                // not here is one this device made and has not sent yet, and
                // deleting it would be losing a decision to a race.
                for name in names { _ = try await collections.create(name) }
                for (name, query) in SyncRecords.dynamicCollections(from: record) {
                    _ = try await collections.createDynamic(name, matching: query)
                }

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

        // A mark may have arrived before the article it is about, and the
        // articles of this very batch may be the ones it was waiting for.
        applied.markedArticles += try await marks.drain()

        return applied
    }

    /// Removes what another device deleted.
    @discardableResult
    func apply(deletions names: [String]) async throws -> Applied {
        var applied = Applied()

        for name in names {
            if name.hasPrefix("feed-") {
                if try await unsubscribe(named: name) { applied.removed += 1 }
            } else if name.hasPrefix("mark-") {
                if try await unmark(named: name) { applied.removed += 1 }
            }
        }

        return applied
    }

    private func unsubscribe(named name: String) async throws -> Bool {
        try await database.writer.write { db in
            let feeds = try Feed.fetchAll(db)
            guard let feed = feeds.first(where: { SyncRecords.name(forFeed: $0.url) == name }) else { return false }
            return try Feed.deleteOne(db, key: feed.id)
        }
    }

    /// Takes back the marks of an article another device unmarked entirely.
    ///
    /// A name is a digest and cannot be read backwards, so the marks are walked
    /// and the one that names itself this way is the one. There are a few
    /// thousand of them at most, and a deletion is rare.
    private func unmark(named name: String) async throws -> Bool {
        let marks = try await self.marks.all()
        guard
            let mark = marks.first(where: {
                SyncRecords.name(forMarkWithGUID: $0.guid, feedURL: URL(string: $0.feedURL)) == name
            }), let feedURL = URL(string: mark.feedURL)
        else { return false }

        return try await self.marks.unmark(feedURL, guid: mark.guid)
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
