//
//  SharedSync.swift
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

/// The collections the reader was invited to.
///
/// **A second engine, on a second database.** `CKSyncEngine`'s own
/// documentation says this is how it is meant to be used : *you can have
/// multiple instances of `CKSyncEngine` in a single process, each targeting a
/// different database. For example, you may have one syncing a person's private
/// database and another syncing their shared database.* ``CloudSync`` is the
/// first of those and is untouched by any of this ; this is the second.
///
/// **It sends as well as fetches**, which is what distinguishes a collaboration
/// from a document. A participant filing an article writes into somebody else's
/// zone, and the writes leave through here.
///
/// **What arrives is never the reader's own article.** It came from a feed they
/// do not follow, it goes to `shared_entry`, and it is never counted unread,
/// purged, indexed as theirs or re-shared. ``SharedEntryStore`` is the whole of
/// where it may land.
actor SharedSync {
    private let database: AppDatabase
    private let container: CKContainer
    private let entries: SharedEntryStore
    private let collections: SharedCollectionStore
    private let state: SyncState

    private var engine: CKSyncEngine?
    /// Records waiting to go out, since the batch provider is synchronous and
    /// building one of these needs the store.
    private var pending: [CKRecord.ID: CKRecord] = [:]

    /// What this device is called in the container, for naming its own list.
    ///
    /// Asked once and kept : it never changes for an account, and it is a round
    /// trip nobody should pay for on every save.
    private var me: CKRecord.ID?

    init(
        database: AppDatabase,
        container: CKContainer = CKContainer(identifier: CloudSync.containerIdentifier)
    ) {
        self.database = database
        self.container = container
        self.entries = SharedEntryStore(database)
        self.collections = SharedCollectionStore(database)
        self.state = SyncState(database)
    }

    // MARK: - Running

    /// The key the engine's own state is kept under.
    ///
    /// Its own, and not ``CloudSync``'s : two engines have two sets of change
    /// tokens, and handing one the other's would have it ask the wrong database
    /// what had changed since a moment that means nothing there.
    private static let engineKey = "cloudkit.shared-engine-state"

    func start() async {
        guard engine == nil else { return }

        do {
            guard try await container.accountStatus() == .available else { return }
        } catch {
            return
        }

        var configuration = CKSyncEngine.Configuration(
            database: container.sharedCloudDatabase,
            stateSerialization: await serialization(),
            delegate: self
        )
        configuration.automaticallySync = true

        engine = CKSyncEngine(configuration)
        Log.sync.notice("The shared collections are being synchronized")
    }

    func synchronize() async {
        guard let engine else {
            await start()
            return
        }
        try? await engine.fetchChanges()
        try? await engine.sendChanges()
    }

    /// Writes this reader's own list into a collection somebody shared.
    ///
    /// **Only their own list.** Every participant writes the record named after
    /// them and reads everybody else's, so there is no record two people write
    /// and no conflict to resolve. What another participant filed is not this
    /// device's to rewrite, and a save that tried would be refused anyway.
    func file(_ filed: [SharedEntry], inZone zoneName: String, ownedBy owner: String) async {
        guard let engine, let me = await participant() else { return }

        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: owner)
        let records = SharedList.records(for: filed, by: me, in: zoneID)

        // Kept so the batch provider can hand them over : it is synchronous,
        // and building a record needs the store.
        pending = records.reduce(into: pending) { $0[$1.recordID] = $1 }
        engine.state.add(pendingRecordZoneChanges: records.map { .saveRecord($0.recordID) })
    }

    private func participant() async -> CKRecord.ID? {
        if let me { return me }
        me = try? await container.userRecordID()
        return me
    }

    private func serialization() async -> CKSyncEngine.State.Serialization? {
        guard let data = try? await state.value(for: Self.engineKey) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }
}

extension SharedSync: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            let data = try? JSONEncoder().encode(update.stateSerialization)
            try? await state.setValue(data, for: Self.engineKey)

        case .fetchedDatabaseChanges(let changes):
            await apply(changes)

        case .fetchedRecordZoneChanges(let changes):
            await apply(changes)

        case .sentRecordZoneChanges(let sent):
            for saved in sent.savedRecords { pending[saved.recordID] = nil }
            for failure in sent.failedRecordSaves {
                // A participation the owner has revoked, or a read-only one.
                // Neither is a fault of this device's and neither is worth
                // retrying : the reader is told by the collection going.
                Log.sync.error("A shared list was refused : \(failure.error.errorCode)")
                pending[failure.record.recordID] = nil
            }

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }

        let waiting = pending
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { waiting[$0] }
    }

    // MARK: - What arrived

    /// A zone appearing or disappearing, which is a collection gained or lost.
    ///
    /// **A zone that goes is a share that ended**, whether the owner stopped
    /// sharing, deleted the collection, or removed this reader from it. There
    /// is nothing to keep : the articles were never this device's, and leaving
    /// them would leave a collection nobody can reach the other end of.
    private func apply(_ changes: CKSyncEngine.Event.FetchedDatabaseChanges) async {
        for deletion in changes.deletions {
            let zone = deletion.zoneID.zoneName
            try? await entries.forget(zoneName: zone)
            try? await collections.forget(zoneName: zone)
            Log.sync.notice("A shared collection was withdrawn, and is gone from here")
        }
    }

    private func apply(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        // One person's list arrives whole, so it is applied whole : what a list
        // carries replaces everything that person had in that collection, which
        // is what makes a removal travel. Chunks of one list are gathered first
        // so that the second chunk does not delete what the first just wrote.
        var lists: [Key: (author: String, entries: [SharedEntry])] = [:]

        for record in changes.modifications.map(\.record) {
            let zone = record.recordID.zoneID

            switch record.recordType {
            case SyncRecords.RecordType.sharedCollection:
                await remember(record, in: zone)

            case SyncRecords.RecordType.sharedList:
                guard let listKey = SyncRecords.listKey(ofRecordNamed: record.recordID.recordName) else { continue }
                let key = Key(zone: zone.zoneName, list: listKey)
                let found = SharedList.entries(from: record)
                lists[key, default: (SharedList.author(of: record), [])].entries += found

            default:
                break
            }
        }

        for (key, list) in lists {
            try? await entries.replace(list.entries, inList: key.list, by: list.author, inZone: key.zone)
        }

        for deletion in changes.deletions {
            // A list deleted is that participant filing nothing, which is not
            // the same as their never having been here. The record carries no
            // author by then, which is why the store is keyed by the name.
            guard let listKey = SyncRecords.listKey(ofRecordNamed: deletion.recordID.recordName) else { continue }
            try? await entries.replace(
                [], inList: listKey, by: "", inZone: deletion.recordID.zoneID.zoneName
            )
        }
    }

    /// One participant's list in one collection.
    private struct Key: Hashable {
        let zone: String
        let list: String
    }

    /// Writes down a collection the reader has been invited to.
    private func remember(_ record: CKRecord, in zone: CKRecordZone.ID) async {
        let title = SharedEntry.bounded(record["title"] as? String, to: 200) ?? String(localized: "Shared collection")

        try? await collections.remember(
            SharedCollection(
                id: UUID.v7(),
                zoneName: zone.zoneName,
                ownerName: zone.ownerName,
                // None of the reader's own making : there is no tag of theirs
                // behind a collection somebody else shared.
                collectionName: nil,
                title: title,
                isOwned: false,
                shareURL: nil,
                createdAt: record["createdAt"] as? Date ?? Date()
            )
        )
    }
}
