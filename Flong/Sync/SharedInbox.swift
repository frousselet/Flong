//
//  SharedInbox.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CloudKit
import Foundation
import OSLog

/// What to do with a record that belongs to a shared collection.
///
/// **Both engines need this, which is why it is neither of them.** A
/// participant's records arrive through ``SharedSync``, on the shared database,
/// because that is where a collection somebody else owns turns up. The owner's
/// arrive through ``CloudSync``, on their private database, because their own
/// shared zones are in it : what a participant files is written into the
/// owner's zone, and the owner learns of it the way they learn of anything else
/// in their own database. Two engines, one meaning, so one place that knows it.
///
/// **A zone that is not the `Flong` zone is one of these.** That is the whole
/// of the test on the private side, and it is enough : nothing else is ever put
/// in a zone of the reader's private database, and the record types say which
/// of these it is.
nonisolated struct SharedInbox: Sendable {
    private let entries: SharedEntryStore
    private let collections: SharedCollectionStore

    init(_ database: AppDatabase) {
        self.entries = SharedEntryStore(database)
        self.collections = SharedCollectionStore(database)
    }

    /// Whether a record belongs to a shared collection rather than to the
    /// reader's own data.
    static func belongsHere(_ id: CKRecord.ID) -> Bool {
        id.zoneID.zoneName != SyncRecords.zoneName
    }

    // MARK: - What arrived

    /// Applies everything a fetch brought back for the shared collections.
    ///
    /// **One person's list is applied whole.** What a list carries is the whole
    /// truth about what that person filed, so an article missing from it is one
    /// they took out : applying the additions alone would leave everybody else
    /// showing a filing that was removed. The chunks of one list are gathered
    /// before anything is written, or the second chunk would delete what the
    /// first had just put in.
    func apply(_ records: [CKRecord], isOwned: Bool) async {
        var lists: [Key: (author: String, entries: [SharedEntry])] = [:]

        for record in records {
            let zone = record.recordID.zoneID

            switch record.recordType {
            case SyncRecords.RecordType.sharedCollection:
                await remember(record, in: zone, isOwned: isOwned)

            case SyncRecords.RecordType.sharedList:
                guard let listKey = SyncRecords.listKey(ofRecordNamed: record.recordID.recordName) else { continue }
                let key = Key(zone: zone.zoneName, list: listKey)
                lists[key, default: (SharedList.author(of: record), [])].entries += SharedList.entries(from: record)

            default:
                break
            }
        }

        for (key, list) in lists {
            try? await entries.replace(list.entries, inList: key.list, by: list.author, inZone: key.zone)
        }
    }

    /// A record that has gone, which for a list means that person filed nothing.
    ///
    /// A deletion carries an identifier and no author, which is why a row is
    /// keyed by the name of the record that brought it.
    func apply(deletions: [CKRecord.ID]) async {
        for id in deletions {
            guard let listKey = SyncRecords.listKey(ofRecordNamed: id.recordName) else { continue }
            try? await entries.replace([], inList: listKey, by: "", inZone: id.zoneID.zoneName)
        }
    }

    /// A zone that has gone, which is a share that ended however it ended.
    ///
    /// The owner stopped sharing, deleted the collection, or took this reader
    /// out of it. There is nothing to keep either way : the articles were never
    /// this device's, and leaving them would strand a collection with no other
    /// end to reach.
    func forget(zone: CKRecordZone.ID) async {
        try? await entries.forget(zoneName: zone.zoneName)
        try? await collections.forget(zoneName: zone.zoneName)
        Log.sync.notice("A shared collection was withdrawn, and is gone from here")
    }

    // MARK: - The collection itself

    private func remember(_ record: CKRecord, in zone: CKRecordZone.ID, isOwned: Bool) async {
        // The reader's own shared collections are already written down, by the
        // device that made the share, and that row knows which made collection
        // is behind it. Overwriting it from the record would lose exactly that.
        guard !isOwned else { return }

        let title = SharedEntry.bounded(record["title"] as? String, to: 200) ?? String(localized: "Shared collection")

        try? await collections.remember(
            SharedCollection(
                id: UUID.v7(),
                zoneName: zone.zoneName,
                ownerName: zone.ownerName,
                // Nothing of the reader's making : there is no tag of theirs
                // behind a collection somebody else shared.
                collectionName: nil,
                title: title,
                isOwned: false,
                shareURL: nil,
                createdAt: record["createdAt"] as? Date ?? Date()
            )
        )
    }

    /// One participant's list in one collection.
    private struct Key: Hashable {
        let zone: String
        let list: String
    }
}
