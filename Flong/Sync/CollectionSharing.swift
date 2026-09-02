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
    private let entries: SharedEntryStore
    private let members: ShareMemberStore

    init(
        database: AppDatabase,
        container: CKContainer = CKContainer(identifier: CloudSync.containerIdentifier)
    ) {
        self.container = container
        self.store = SharedCollectionStore(database)
        self.entries = SharedEntryStore(database)
        self.members = ShareMemberStore(database)
    }

    // MARK: - Who put what in

    /// Who filed each article in one shared collection, by its identity.
    ///
    /// **Two questions joined here so that neither leaves this layer.** The
    /// store says which identifier filed which article, and the share says what
    /// that identifier is called ; the identifier itself is a CloudKit user
    /// record name, which is opaque and has no business anywhere near a view.
    ///
    /// `owner` is `nil` for one of the reader's own collections, whose share is
    /// in their private database. A collection they were invited to has its
    /// share in the shared one, under the owner named here.
    ///
    /// **Nothing comes back for the reader's own filings.** A collection saying
    /// who put a thing in it should not keep telling them it was them.
    func attribution(inZone zone: String, ownedBy owner: String?) async -> [String: String] {
        guard let authors = try? await entries.authors(inZone: zone) else { return [:] }

        let database = owner == nil ? container.privateCloudDatabase : container.sharedCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: zone, ownerName: owner ?? CKCurrentUserDefaultName)

        let names = await ShareParticipants.names(inZone: zoneID, from: database)
        let me = try? await container.userRecordID().recordName

        return authors.reduce(into: [:]) { found, pair in
            guard pair.value != me, let name = names[pair.value] else { return }
            found[pair.key] = name
        }
    }

    // MARK: - Who is in it

    /// Reads the share of one collection and writes down who it lists.
    ///
    /// **A round trip, so it is not what a page draws from.** The store is,
    /// and this is what corrects the store : a grid of twenty collections
    /// cannot ask iCloud twenty questions before it draws a face, and a reader
    /// on a train would watch every one of them fail.
    ///
    /// Nothing is written when the share cannot be read. A fetch that failed
    /// says nothing about who is in a collection, and treating it as an empty
    /// roster would empty the collection because the network was down.
    ///
    /// `owner` is `nil` for one of the reader's own collections, whose share is
    /// in their private database. A collection they were invited to has its
    /// share in the shared one, under the owner named here.
    @discardableResult
    func refreshMembers(inZone zone: String, ownedBy owner: String?) async -> [ShareMember] {
        let database = owner == nil ? container.privateCloudDatabase : container.sharedCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: zone, ownerName: owner ?? CKCurrentUserDefaultName)

        guard let share = await ShareParticipants.share(inZone: zoneID, from: database) else { return [] }

        let me = try? await container.userRecordID().recordName
        let roster = ShareParticipants.roster(of: share, in: zone, me: me)
        try? await members.reconcile(roster, inZone: zone)

        return (try? await members.members(inZone: zone)) ?? []
    }

    /// Takes one person out of a collection the reader owns.
    ///
    /// **Only from a collection of theirs.** A share is the owner's to change
    /// and the server refuses everybody else, so this addresses the private
    /// database and no other : a participant who wants out leaves through the
    /// system's own sheet, which is where leaving has always lived.
    ///
    /// **What they filed stays.** They wrote it into the collection, in a
    /// record of their own, and taking somebody out of a share is about what
    /// they may see from now on. Unsaying what they said is a different act and
    /// is not this one.
    func remove(_ member: String, fromCollectionNamed name: String) async throws {
        guard let existing = try await store.owned(named: name) else { return }
        let zoneID = CKRecordZone.ID(zoneName: existing.zoneName, ownerName: CKCurrentUserDefaultName)

        let me = try? await container.userRecordID().recordName
        let roster = try await ShareParticipants.remove(
            member,
            fromShareIn: zoneID,
            from: container.privateCloudDatabase,
            me: me
        )

        try? await members.reconcile(roster, inZone: existing.zoneName)
        Log.sync.notice("Somebody was taken out of a shared collection")
    }

    /// Writes this reader's own card into one collection of theirs.
    ///
    /// **The only place a participant's face can come from.** A
    /// `CKUserIdentity` carries none, so what is not written here is not drawn
    /// anywhere : the other people in the collection see initials, or nothing.
    ///
    /// One small record and nothing else touched, so a reader who changes their
    /// picture does not resend everything they filed.
    @discardableResult
    func publishCard(named name: String?, picture: Data?, inZone zoneName: String) async -> Bool {
        guard let me = try? await container.userRecordID() else { return false }

        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let card = ShareMember.card(name: name, picture: picture, by: me, in: zoneID)

        do {
            _ = try await container.privateCloudDatabase.modifyRecords(saving: [card], deleting: [])
            return true
        } catch {
            Log.sync.error("A card could not be sent : \(error.localizedDescription, privacy: .public)")
            return false
        }
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

    /// Sends what the reader has in one of their own shared collections.
    ///
    /// **Through `CKDatabase` and not through an engine**, for the same reason
    /// the share itself is : the owner's shared zones are in their private
    /// database, and ``CloudSync`` addresses one zone by construction. Teaching
    /// it several is a change worth making one day and not one to make in
    /// passing ; what a save loses meanwhile is the engine's retrying, and this
    /// is called again on every change to the collection, so a push that fails
    /// is a push the next filing makes good.
    ///
    /// **The whole list, every time.** A list is the whole truth about what one
    /// person filed, so an article taken out of the collection has to leave the
    /// record for the removal to reach anybody.
    ///
    /// A collection nobody was invited to does nothing here.
    ///
    /// The reader's own card goes with it. It is one small record and it is
    /// what puts a face rather than an identifier against everything they file,
    /// so it travels with the filings rather than waiting for a pass of its
    /// own : a participant invited today should not have to wait until the
    /// owner next edits their profile to learn who invited them.
    func push(
        collectionNamed name: String,
        from database: AppDatabase,
        credentials: CredentialStoring,
        readerNamed reader: String?,
        picture: Data?
    ) async {
        guard let existing = try? await store.owned(named: name),
            let me = try? await container.userRecordID()
        else { return }

        let zoneID = CKRecordZone.ID(zoneName: existing.zoneName, ownerName: CKCurrentUserDefaultName)

        do {
            let filed = try await SharedEntry.entries(in: database, collectionNamed: name, credentials: credentials)
            let records =
                SharedList.records(for: filed, by: me, in: zoneID)
                + [ShareMember.card(name: reader, picture: picture, by: me, in: zoneID)]
            _ = try await container.privateCloudDatabase.modifyRecords(saving: records, deleting: [])
            Log.sync.notice("Sent \(filed.count) excerpts to a shared collection")
        } catch let error as CKError where error.code == .zoneNotFound {
            // The zone is gone, from another device or from the system's sheet.
            // The collection is not shared any more, and the row saying it is
            // would have every later filing try again against nothing.
            try? await store.forget(zoneName: existing.zoneName)
        } catch {
            Log.sync.error("A shared collection could not be sent : \(error.localizedDescription, privacy: .public)")
        }
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
        try? await members.forget(zoneName: existing.zoneName)
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
