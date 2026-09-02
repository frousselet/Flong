//
//  PoolExchange.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CloudKit
import CryptoKit
import Foundation
import OSLog

/// The common pool, on the public side of the container.
///
/// **The only place in Flong that touches a database belonging to everybody.**
/// Section 7 gives the private database to the reader's own devices and a zone
/// per collection to the people they invited ; this is the third database
/// CloudKit offers, it holds addresses and nothing else, and the reader is
/// asked once before a byte of theirs goes into it.
///
/// **No `CKSyncEngine` here, and there could not be one.** The engine is built
/// for a database whose changes are all the reader's own : it holds a token,
/// asks what has changed in a zone it owns, and sends what it owes. A public
/// database has no zone to hold a token against and no notion of *what has
/// changed for you*, so the exchange is written by hand, which is why it is as
/// small as it is : one query out, one save in, and a date to resume from.
///
/// **It is the one file of this module that cannot be tested from the outside**,
/// for the reasons ``CloudSync`` gives : it needs a container and a network.
/// Everything either side of it is tested instead : what may be offered, what a
/// record carries, what a stranger's record is allowed to become, and what the
/// counting makes of it.
///
/// ### What the container needs
///
/// The public schema carries two record types, `PoolList` and `PoolRoster`,
/// with the default security roles : the world may read, an iCloud account may
/// create, and only a record's creator may change it. The system field
/// `modifiedTimestamp` must be marked queryable and sortable on `PoolList`,
/// since resuming a pull is a question about it. `docs/technical/popular-feeds.md`
/// carries the whole of it, including what has to be deployed to production.
actor PoolExchange {
    /// How many lists one pass brings back.
    ///
    /// A pass is bounded and the next one resumes where it stopped, which is
    /// the rule section 15 states for every long task : a reader on a train
    /// does not download the whole pool to see six suggestions.
    static let pageLimit = 50

    /// How many passes one refresh runs before leaving the rest for later.
    static let passLimit = 4

    /// How far past the last chunk a withdrawal reaches.
    ///
    /// A list is one record for any reader inside the target of section 21, so
    /// this is nearly always deleting nothing. It exists for the reader who
    /// shortened a very long list : the chunks that are no longer written have
    /// to stop being read, and a record nobody rewrites is a record that stays.
    private static let staleChunks = 3

    private let container: CKContainer
    private let store: PoolStore
    private let state: SyncState

    init(database: AppDatabase, container: CKContainer = CKContainer(identifier: CloudSync.containerIdentifier)) {
        self.container = container
        self.store = PoolStore(database)
        self.state = SyncState(database)
    }

    private var database: CKDatabase { container.publicCloudDatabase }
    private static let cursorKey = "pool.pulled-through"
    private static let offeredKey = "pool.offered"

    // MARK: - Who this device is

    /// This reader's identity in the pool, or nothing without an account.
    ///
    /// The same value CloudKit stamps on everything they write, which is what
    /// makes it the thing a roster names. It is opaque, it is particular to
    /// this container, and it is not an Apple account identifier : it says
    /// *the same person wrote these two records* and nothing else about them.
    func identity() async -> String? {
        guard let status = try? await container.accountStatus(), status == .available else { return nil }
        return try? await container.userRecordID().recordName
    }

    // MARK: - Offering

    /// Publishes what this reader offers, replacing what they offered before.
    @discardableResult
    func publish(_ feeds: [PooledFeed], as contributor: UUID) async -> Bool {
        let records = PoolList.records(for: feeds, by: contributor)

        do {
            _ = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
            await deleteChunks(from: records.count, of: contributor)
            Log.sync.notice("Offered \(feeds.count) sources to the pool")
            return true
        } catch {
            Log.sync.error("The pool refused this offer : \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Publishes the offer only when it is not the one already published.
    ///
    /// **A write to a database everybody reads is not free**, and the offer is
    /// a slow-moving thing : a reader adds a source now and then and rewrites
    /// nothing else about themselves. What is kept is a digest of what was last
    /// published, so a launch that changed nothing writes nothing, which is the
    /// politeness of section 8 pointed at CloudKit rather than at a publisher.
    func offerIfChanged(_ feeds: [PooledFeed], as contributor: UUID) async {
        let digest = Self.digest(of: feeds)
        guard digest != (try? await state.value(for: Self.offeredKey)) else { return }
        guard await publish(feeds, as: contributor) else { return }
        try? await state.setValue(digest, for: Self.offeredKey)
    }

    /// Forgets what was last offered, so the next offer is written whatever it
    /// holds. What withdrawing has to do, or the next launch would think the
    /// pool still had a list this device has just taken out of it.
    private func forgetOffer() async {
        try? await state.setValue(nil, for: Self.offeredKey)
    }

    private static func digest(of feeds: [PooledFeed]) -> Data {
        let spelled = feeds.map { "\($0.url)\t\($0.title)\t\($0.siteURL ?? "")" }.sorted().joined(separator: "\n")
        return Data(SHA256.hash(data: Data(spelled.utf8)))
    }

    /// Takes this reader's offer back out of the pool.
    ///
    /// **What turning the switch off has to mean.** A reader who stops
    /// contributing is not a reader whose list stays where it was and stops
    /// being updated : the records go, and the pass everybody else runs
    /// tomorrow stops counting them.
    func withdraw(as contributor: UUID) async {
        await deleteChunks(from: 0, of: contributor)
        await forgetOffer()
    }

    private func deleteChunks(from first: Int, of contributor: UUID) async {
        let names = (first..<(first + Self.staleChunks)).map {
            CKRecord.ID(recordName: PoolRecords.name(forListBy: contributor, chunk: $0))
        }
        // A chunk that was never written is not an error worth reporting : the
        // whole point of the window is that it mostly deletes nothing.
        _ = try? await database.modifyRecords(saving: [], deleting: names)
    }

    // MARK: - Reading

    /// Brings the pool up to date, and says whether anything changed.
    ///
    /// **Resumed from a date rather than from a token**, since a public
    /// database offers none. What is stored is the modification date of the
    /// most recent list already folded in, and the query asks for that date and
    /// after it : a record written in the same second as the last one seen is
    /// fetched twice rather than missed, and folding a list in twice is the
    /// same as folding it in once.
    @discardableResult
    func refresh() async -> Bool {
        await readRoster()

        var since = await cursor()
        var absorbed = 0

        for _ in 0..<Self.passLimit {
            guard let page = await fetch(since: since) else { break }
            guard !page.lists.isEmpty else { break }

            do {
                try await store.absorb(page.lists)
            } catch {
                Log.sync.error("The pool could not be stored : \(error.localizedDescription, privacy: .public)")
                break
            }

            absorbed += page.lists.count
            let newest = page.lists.map(\.modifiedAt).max() ?? since
            // No progress in time means every record of this page was written
            // in the same instant as the last one seen, and asking again would
            // fetch the same page for ever.
            guard newest > since else { break }
            since = newest
            await setCursor(newest)

            guard page.hasMore else { break }
        }

        if absorbed > 0 {
            try? await store.prune()
            Log.sync.notice("The pool grew by \(absorbed) lists")
        }
        return absorbed > 0
    }

    private struct Page {
        var lists: [PoolList.Received]
        var hasMore: Bool
    }

    private func fetch(since: Date) async -> Page? {
        let query = CKQuery(
            recordType: PoolRecords.RecordType.list,
            predicate: NSPredicate(format: "modificationDate >= %@", since as NSDate)
        )
        query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: true)]

        do {
            let (matches, cursor) = try await database.records(matching: query, resultsLimit: Self.pageLimit)
            let lists = matches.compactMap { _, result -> PoolList.Received? in
                guard let record = try? result.get() else { return nil }
                return PoolList.received(record)
            }
            return Page(lists: lists, hasMore: cursor != nil)
        } catch {
            Log.sync.error("The pool could not be read : \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Reads the roster, and believes it only if the author wrote it.
    private func readRoster() async {
        guard PoolTrust.root != nil else { return }

        let query = CKQuery(recordType: PoolRecords.RecordType.roster, predicate: NSPredicate(value: true))

        do {
            let (matches, _) = try await database.records(matching: query, resultsLimit: 20)
            let rosters = matches.compactMap { _, result -> Set<String>? in
                guard let record = try? result.get() else { return nil }
                return PoolTrust.trusted(in: record)
            }
            guard let trusted = rosters.first else { return }
            try await store.setTrusted(trusted)
        } catch {
            Log.sync.error("The roster could not be read : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Writes the roster, which only the author's own device may do.
    @discardableResult
    func publishRoster(naming creators: Set<String>, as contributor: UUID) async -> Bool {
        guard PoolTrust.isRoot(await identity()) else { return false }

        do {
            let record = PoolTrust.record(naming: creators, by: contributor)
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            try await store.setTrusted(creators)
            return true
        } catch {
            Log.sync.error("The roster was refused : \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Where the last pass stopped

    private func cursor() async -> Date {
        guard let data = try? await state.value(for: Self.cursorKey),
            let seconds = try? JSONDecoder().decode(Double.self, from: data)
        else { return .distantPast }
        return Date(timeIntervalSince1970: seconds)
    }

    private func setCursor(_ date: Date) async {
        guard let data = try? JSONEncoder().encode(date.timeIntervalSince1970) else { return }
        try? await state.setValue(data, for: Self.cursorKey)
    }

    /// Forgets where the last pass stopped, so the next one starts over.
    func forgetCursor() async {
        try? await state.setValue(nil, for: Self.cursorKey)
    }
}
