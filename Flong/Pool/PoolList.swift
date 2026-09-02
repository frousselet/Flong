//
//  PoolList.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CloudKit
import Foundation

/// What the common pool is made of, and what it is called.
///
/// **The public database, and the same shape the shared collections use.** One
/// record per contributor rather than one per source, which is the argument of
/// section 7 made a second time : a pool of a thousand readers following three
/// hundred sources apiece is three hundred thousand records in the shape that
/// looks obvious, and a thousand in this one. Each person writes only their own
/// list and reads everybody else's, so two people offering the same source at
/// the same moment cannot collide and there is no conflict to resolve.
///
/// **Named after an identifier of the reader's own making**, kept in their
/// key-value store and therefore the same on their iPad as on their phone.
/// Deliberately not derived from their iCloud identity : a record name in a
/// database the whole world reads should say nothing about who wrote it, and a
/// name nobody can work out in advance is also a name nobody can take first to
/// stop somebody publishing.
nonisolated enum PoolRecords {
    enum RecordType {
        /// One chunk of one reader's list of what they follow.
        static let list = "PoolList"
        /// What the author of the application decided : who is believed on
        /// their own, who is cut out, and which addresses are never suggested.
        static let authority = "PoolAuthority"
        /// Who one contributor brought into the pool.
        static let vouch = "PoolVouch"
    }

    enum Field {
        static let feeds = "feeds"
        static let trusted = "trusted"
        static let banned = "banned"
        static let blocked = "blocked"
        static let sponsored = "sponsored"
    }

    static func name(forListBy contributor: UUID, chunk: Int = 0) -> String {
        "pool-" + contributor.uuidString.lowercased() + "-" + String(chunk)
    }

    static func name(forAuthorityBy contributor: UUID) -> String {
        "authority-" + contributor.uuidString.lowercased()
    }

    static func name(forVouchBy contributor: UUID) -> String {
        "vouch-" + contributor.uuidString.lowercased()
    }
}

/// One reader's offer, on its way out and on its way in.
nonisolated enum PoolList {
    /// How much of a record the sources may fill.
    ///
    /// The margin ``SharedList`` keeps, for the same reason : a save refused
    /// for being a few bytes over the limit costs a great deal more than a
    /// chunk cut early.
    static let chunkLimit = 700 * 1024

    // MARK: - Sending

    /// One reader's list, cut into as many records as its bytes need.
    ///
    /// Always at least one record, even for a list of nothing. A reader who has
    /// taken every source out of what they offer has said something, and a
    /// record that simply stopped being written would leave everybody else
    /// counting an offer that was withdrawn.
    static func records(for feeds: [PooledFeed], by contributor: UUID) -> [CKRecord] {
        var records: [CKRecord] = []
        var batch: [PooledFeed] = []
        var size = 0

        func flush() {
            guard let payload = try? JSONEncoder().encode(batch) else { return }
            let record = CKRecord(
                recordType: PoolRecords.RecordType.list,
                recordID: CKRecord.ID(recordName: PoolRecords.name(forListBy: contributor, chunk: records.count))
            )
            record[PoolRecords.Field.feeds] = SyncRecords.compressed(String(decoding: payload, as: UTF8.self))
            records.append(record)
            batch = []
            size = 0
        }

        for feed in feeds.prefix(PooledFeed.listLimit) {
            let weight = feed.url.utf8.count + feed.title.utf8.count + (feed.siteURL?.utf8.count ?? 0) + 24
            if size > 0, size + weight > chunkLimit { flush() }
            batch.append(feed)
            size += weight
            if size >= chunkLimit { flush() }
        }

        if !batch.isEmpty || records.isEmpty { flush() }
        return records
    }

    // MARK: - Receiving

    /// One record, read back into something the store can hold.
    ///
    /// **Everything in here was written by a stranger.** The public database
    /// accepts a record from anybody with an iCloud account, so every source is
    /// put through ``PooledFeed/received`` and the ones with nothing usable
    /// left are dropped rather than stored empty. A list holding more than one
    /// reader could plausibly follow is cut, which is what stops a single
    /// contributor from filling everybody else's database.
    static func received(_ record: CKRecord) -> Received? {
        guard record.recordType == PoolRecords.RecordType.list else { return nil }

        let payload = SyncRecords.expanded(record[PoolRecords.Field.feeds] as? Data)
        let decoded = payload.flatMap { try? JSONDecoder().decode([PooledFeed].self, from: Data($0.utf8)) }

        return Received(
            recordName: record.recordID.recordName,
            creator: creator(of: record),
            modifiedAt: record.modificationDate ?? Date(),
            feeds: (decoded ?? []).prefix(PooledFeed.listLimit).compactMap(\.received)
        )
    }

    /// One chunk of somebody's list, as the store takes it.
    nonisolated struct Received: Hashable, Sendable {
        var recordName: String
        /// Whoever wrote it, as CloudKit names them.
        var creator: String
        var modifiedAt: Date
        var feeds: [PooledFeed]
    }

    /// Whoever wrote a record, as CloudKit names them.
    ///
    /// **The server sets it and a client cannot**, which is the whole reason
    /// the counting of section 8 means anything : a contributor who could write
    /// somebody else's name into a field of their own would be ten people by
    /// dinner time, and this cannot be written at all. It is also what makes
    /// a sponsorship worth believing : ``PoolVouch`` says who somebody brought
    /// in, and the sponsor is the record's creator rather than a field of it.
    static func creator(of record: CKRecord) -> String {
        record.creatorUserRecordID?.recordName ?? CKCurrentUserDefaultName
    }
}
