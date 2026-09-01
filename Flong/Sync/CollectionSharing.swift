//
//  CollectionSharing.swift
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

/// Inviting somebody to a collection, and knowing who is already in one.
///
/// **The share is a discrete act and is not the engine's business.**
/// `CKSyncEngine` keeps a database in step in the background, which is what
/// section 7 asks of it and what it is good at. Creating a zone, saving a share
/// and handing it to the share sheet happens once, because the reader asked for
/// it, and has to have either finished or failed by the time the sheet appears.
/// So this talks to `CKDatabase` directly, and what the shared collection then
/// holds is synchronized like everything else.
///
/// **Zone-wide rather than hierarchical.** A hierarchy means a parent reference
/// on every record and a fix-up on every insertion, for a structure that is
/// flat. `CKShare(recordZoneID:)` shares the zone and everything that will ever
/// be put in it, which is exactly what a collection is.
actor CollectionSharing {
    /// The container the reader's own data lives in, and the one a share is
    /// made against : a share reaches across accounts, never across containers.
    nonisolated let container: CKContainer

    private let store: SharedCollectionStore

    init(
        database: AppDatabase,
        container: CKContainer = CKContainer(identifier: CloudSync.containerIdentifier)
    ) {
        self.container = container
        self.store = SharedCollectionStore(database)
    }

    // MARK: - Inviting

    /// The share for one of the reader's collections, made if there is not one.
    ///
    /// **Idempotent, because the share sheet is not.** A reader may invite one
    /// person today and another next week, and the second invitation is to the
    /// same collection : a second share would be a second zone holding a second
    /// copy of everything, and the first participant would never see what the
    /// second one filed. So an existing share is fetched and handed back, and
    /// only a collection that has never been shared makes anything.
    ///
    /// **A row whose share has gone is a row that is wrong.** The reader may
    /// have stopped sharing from the system's own sheet, on this device or
    /// another, and that deletes the share without telling this table. Finding
    /// the zone without a share in it is that, so the row is dropped and the
    /// collection is shared afresh rather than handing back nothing.
    func share(ofCollectionNamed name: String) async throws -> CKShare {
        let database = container.privateCloudDatabase

        if let existing = try await store.owned(named: name) {
            let zoneID = CKRecordZone.ID(zoneName: existing.zoneName, ownerName: CKCurrentUserDefaultName)
            if let share = try await share(in: zoneID) {
                Log.sync.notice("A collection already shared was invited to again")
                return share
            }
            Log.sync.notice("A shared collection had no share left, and is shared again")
            try await store.forget(zoneName: existing.zoneName)
        }

        let id = UUID.v7()
        let zoneID = CKRecordZone.ID(
            zoneName: SyncRecords.zoneName(forSharedCollection: id),
            ownerName: CKCurrentUserDefaultName
        )

        // The zone first and on its own : a share addresses a zone, so the zone
        // has to exist before anything can be said about it.
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])

        let record = CKRecord(
            recordType: SyncRecords.RecordType.sharedCollection,
            recordID: CKRecord.ID(recordName: SyncRecords.sharedCollectionName, zoneID: zoneID)
        )
        record["title"] = name
        record["createdAt"] = Date()

        let share = CKShare(recordZoneID: zoneID)
        // What the invitation says it is. Without it the share sheet offers the
        // reader's collection under the name of the application, which tells
        // the person receiving it nothing about what they are being invited to.
        share[CKShare.SystemFieldKey.title] = name

        _ = try await database.modifyRecords(saving: [record, share], deleting: [])

        try await store.remember(
            SharedCollection(
                id: id,
                zoneName: zoneID.zoneName,
                ownerName: CKCurrentUserDefaultName,
                collectionName: name,
                title: name,
                isOwned: true,
                shareURL: share.url,
                createdAt: Date()
            )
        )

        Log.sync.notice("A collection was shared, in a zone of its own")
        return share
    }

    /// The share already on a collection, for a reader who wants to see who is
    /// in it rather than invite somebody new.
    func existingShare(ofCollectionNamed name: String) async throws -> CKShare? {
        guard let existing = try await store.owned(named: name) else { return nil }
        let zoneID = CKRecordZone.ID(zoneName: existing.zoneName, ownerName: CKCurrentUserDefaultName)
        return try await share(in: zoneID)
    }

    /// Stops sharing a collection, and takes the zone down with it.
    ///
    /// **Deleting the zone is what revokes the share**, since the share lives
    /// in it. Every participant loses it at once, which is the right answer for
    /// a collection whose owner has thrown it away : leaving the zone standing
    /// would go on showing them something that no longer exists here, with
    /// nothing left on this device to ever take it down.
    ///
    /// A collection that was never shared has no zone, and this does nothing.
    /// Nor is a failure worth stopping a deletion for : the reader asked for
    /// the collection to go, and it goes whether or not iCloud was reachable.
    func stopSharing(collectionNamed name: String) async {
        guard let existing = try? await store.owned(named: name) else { return }
        let zoneID = CKRecordZone.ID(zoneName: existing.zoneName, ownerName: CKCurrentUserDefaultName)

        do {
            _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
            Log.sync.notice("A shared collection was taken down with its zone")
        } catch {
            Log.sync.error("A shared zone could not be deleted : \(error.localizedDescription, privacy: .public)")
        }

        try? await store.forget(zoneName: existing.zoneName)
    }

    /// Records where the invitation points, once the system has made one.
    ///
    /// The address does not exist when the share is created : it is filled in
    /// when the reader actually picks somebody to send it to, which happens
    /// inside the share sheet and after the preparation handler has returned.
    func rememberURL(of share: CKShare) async {
        guard let url = share.url else { return }
        try? await store.setShareURL(url, forZone: share.recordID.zoneID.zoneName)
    }

    // MARK: - The zone's own share

    /// The zone-wide share of a zone, or `nil` where the zone is not shared.
    ///
    /// A zone-wide share sits under a name CloudKit reserves for it, which is
    /// the only way to ask for one : it is not a record the application named
    /// and it is not reachable through the zone itself.
    private func share(in zoneID: CKRecordZone.ID) async throws -> CKShare? {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)

        do {
            return try await container.privateCloudDatabase.record(for: id) as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            // Not shared, or not there at all. Both mean there is no share, and
            // neither is a failure the reader has to be told about.
            return nil
        }
    }
}
