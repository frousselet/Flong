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
    private let authors: AuthorStore
    private let newsmakers: NewsmakerStore
    private let readStates: ReadStateStore
    private let embedder: Embedder
    private let state: SyncState
    private let zone: CKRecordZone.ID

    init(_ database: AppDatabase, zone: CKRecordZone.ID) {
        self.database = database
        self.subscriptions = SubscriptionStore(database)
        self.marks = MarkStore(database)
        self.collections = CollectionStore(database)
        self.authors = AuthorStore(database)
        self.newsmakers = NewsmakerStore(database)
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
        for name in try await subscriptions.names() {
            records.append(SyncRecords.record(for: name, in: zone))
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
        for author in try await authors.favourites() {
            records.append(SyncRecords.record(forFavouriteAuthor: author, in: zone))
        }
        for author in try await authors.notified() {
            records.append(SyncRecords.record(forNotifiedAuthor: author, in: zone))
        }
        for person in try await newsmakers.favourites() {
            records.append(SyncRecords.record(forFavouriteNewsmaker: person, in: zone))
        }
        for person in try await newsmakers.notified() {
            records.append(SyncRecords.record(forNotifiedNewsmaker: person, in: zone))
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
        for written in try await subscriptions.names() {
            let name = SyncRecords.name(forSourceNamedDomain: written.domain)
            if names.contains(name) { records[name] = SyncRecords.record(for: written, in: zone) }
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
        for author in try await authors.favourites() {
            let name = SyncRecords.name(forFavouriteAuthor: author)
            if names.contains(name) { records[name] = SyncRecords.record(forFavouriteAuthor: author, in: zone) }
        }
        for author in try await authors.notified() {
            let name = SyncRecords.name(forNotifiedAuthor: author)
            if names.contains(name) { records[name] = SyncRecords.record(forNotifiedAuthor: author, in: zone) }
        }
        for person in try await newsmakers.favourites() {
            let name = SyncRecords.name(forFavouriteNewsmaker: person)
            if names.contains(name) {
                records[name] = SyncRecords.record(forFavouriteNewsmaker: person, in: zone)
            }
        }
        for person in try await newsmakers.notified() {
            let name = SyncRecords.name(forNotifiedNewsmaker: person)
            if names.contains(name) {
                records[name] = SyncRecords.record(forNotifiedNewsmaker: person, in: zone)
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

    /// Forgets which shared archives this device has already read.
    ///
    /// The ledger is what makes an exchange cheap to run often : a file whose
    /// modification date has not moved since it was last read is skipped. A
    /// resynchronization from nothing has to take them all in again, or the one
    /// thing the archives carry, the days the other devices wrote, is the one
    /// thing the repair leaves untouched.
    func forgetEveryArchiveRead() async throws {
        try await database.writer.write { db in try db.execute(sql: "DELETE FROM archive_ingest") }
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
        /// Publishers another device gave a name to.
        var sourceNames = 0
        /// Articles another device said something about : starred, wrote on,
        /// or filed.
        var markedArticles = 0
        var readArticles = 0
        /// Articles this device had missed while it was switched off.
        var caughtUp = 0
        var removed = 0

        var isEmpty: Bool {
            feeds == 0 && sourceNames == 0 && markedArticles == 0 && readArticles == 0 && caughtUp == 0
                && removed == 0
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

                // **A source that moved is moved here, not removed and added
                // again.** Every record is named after the address of its feed,
                // so an address the reader edited arrives as a record under a
                // name this device has never seen, followed by the deletion of
                // the one it knows. Taken at face value that pair deletes the
                // articles of a source that has not gone anywhere, and the
                // stars, the notes and the filings on them. The record says
                // where the source came from, and the row is moved to meet it.
                //
                // Before the upsert, so that the upsert finds the source where
                // the record says it is rather than opening a second one beside
                // it. Doing nothing is the ordinary answer : this device may
                // have followed the move already, or never have known the
                // source at all.
                if let previous = SyncRecords.previousURL(from: record) {
                    try await subscriptions.readdress(from: previous, to: subscription.url)
                }

                let followed = try await subscriptions.subscribe(to: subscription)
                if followed.isNew { applied.feeds += 1 }

                // The upsert completes a feed and never overwrites it, which is
                // right for an import and wrong here : a name the reader wrote,
                // a site they corrected, a source they singled out and a
                // source they asked to be told about on another device are the
                // later word on the matter, and a
                // decision that never travelled is one they made and then
                // watched disappear on the next device they picked up.
                try await subscriptions.adopt(
                    subscription,
                    isFavourite: SyncRecords.isFavourite(from: record),
                    notifies: SyncRecords.notifies(from: record),
                    at: followed.feed.id
                )

            case SyncRecords.RecordType.sourceName:
                guard let written = SyncRecords.sourceName(from: record) else { continue }
                try await subscriptions.rename(domain: written.domain, to: written.name)
                applied.sourceNames += 1

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

            case SyncRecords.RecordType.favouriteAuthor:
                guard let author = SyncRecords.favouriteAuthor(from: record) else { continue }
                // The writer may be one this device has never read. The
                // favourite is kept all the same : it is a decision, and the
                // articles that answer to it turn up whenever they turn up.
                try await authors.setFavourite(author, true)

            case SyncRecords.RecordType.notifiedAuthor:
                guard let author = SyncRecords.notifiedAuthor(from: record) else { continue }
                // Kept for the same reason, and it says nothing about when this
                // device will speak : what it announces is what arrives here
                // after it heard about the decision, which is its own watermark
                // and never one that travelled.
                try await authors.setNotifies(author, true)

            case SyncRecords.RecordType.favouriteNewsmaker:
                guard let person = SyncRecords.favouriteNewsmaker(from: record) else { continue }
                // The person may be one no article here has named yet, and the
                // favourite is kept all the same : it is a decision, and the
                // articles that answer to it turn up whenever they turn up.
                try await newsmakers.setFavourite(person, true)

            case SyncRecords.RecordType.notifiedNewsmaker:
                guard let person = SyncRecords.notifiedNewsmaker(from: record) else { continue }
                try await newsmakers.setNotifies(person, true)

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
            } else if name.hasPrefix("source-") {
                if try await forgetSourceName(named: name) { applied.removed += 1 }
            } else if name.hasPrefix("author-") {
                if try await forgetFavouriteAuthor(named: name) { applied.removed += 1 }
            } else if name.hasPrefix("told-") {
                if try await forgetNotifiedAuthor(named: name) { applied.removed += 1 }
            } else if name.hasPrefix("newsmaker-") {
                if try await forgetFavouriteNewsmaker(named: name) { applied.removed += 1 }
            } else if name.hasPrefix("about-") {
                if try await forgetNotifiedNewsmaker(named: name) { applied.removed += 1 }
            }
        }

        return applied
    }

    /// Takes back the name another device stopped calling a publisher by.
    ///
    /// Names are digests, so the domain is found by walking the handful of
    /// names the reader wrote rather than read back out of the record name.
    private func forgetSourceName(named name: String) async throws -> Bool {
        let written = try await subscriptions.names()
        guard let match = written.first(where: { SyncRecords.name(forSourceNamedDomain: $0.domain) == name })
        else { return false }

        try await subscriptions.rename(domain: match.domain, to: nil)
        return true
    }

    /// Takes back a favourite another device gave up.
    ///
    /// Names are digests, so the writer is found by walking the handful the
    /// reader singled out rather than read back out of the record name.
    private func forgetFavouriteAuthor(named name: String) async throws -> Bool {
        let favourites = try await authors.favourites()
        guard let match = favourites.first(where: { SyncRecords.name(forFavouriteAuthor: $0) == name })
        else { return false }

        try await authors.setFavourite(match, false)
        return true
    }

    /// Takes back a writer another device stopped asking about.
    ///
    /// Found the same way and for the same reason as the favourite above : the
    /// name is a digest, so it is matched against the handful the reader
    /// actually asked about rather than read back out.
    private func forgetNotifiedAuthor(named name: String) async throws -> Bool {
        let notified = try await authors.notified()
        guard let match = notified.first(where: { SyncRecords.name(forNotifiedAuthor: $0) == name })
        else { return false }

        try await authors.setNotifies(match, false)
        return true
    }

    /// Takes back a favourite another device gave up.
    ///
    /// Found the same way and for the same reason as the writers' : the name is
    /// a digest, so it is matched against the handful the reader singled out
    /// rather than read back out of the record name.
    private func forgetFavouriteNewsmaker(named name: String) async throws -> Bool {
        let favourites = try await newsmakers.favourites()
        guard let match = favourites.first(where: { SyncRecords.name(forFavouriteNewsmaker: $0) == name })
        else { return false }

        try await newsmakers.setFavourite(match, false)
        return true
    }

    /// Takes back somebody another device stopped asking about.
    private func forgetNotifiedNewsmaker(named name: String) async throws -> Bool {
        let notified = try await newsmakers.notified()
        guard let match = notified.first(where: { SyncRecords.name(forNotifiedNewsmaker: $0) == name })
        else { return false }

        try await newsmakers.setNotifies(match, false)
        return true
    }

    /// Stops following what another device stopped following.
    ///
    /// Through the store's own removal rather than a delete of the row, so a
    /// source that goes because another device said so goes exactly as one the
    /// reader removed here does : the filings, the waiting marks, the emptied
    /// stories and the name over a publisher whose last source this was. A
    /// device that only deleted the row would keep every one of those, for ever
    /// and invisibly, on the device that was not the one asked.
    ///
    /// Nothing is queued back to iCloud : the device that removed it has
    /// already deleted every record, and this end has only to catch up.
    private func unsubscribe(named name: String) async throws -> Bool {
        let feeds = try await subscriptions.feeds()
        guard let feed = feeds.first(where: { SyncRecords.name(forFeed: $0.url) == name }) else { return false }

        try await subscriptions.unsubscribe(feed.id)
        return true
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
