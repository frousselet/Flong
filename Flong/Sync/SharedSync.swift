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
    private let inbox: SharedInbox
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
        self.inbox = SharedInbox(database)
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

    /// Puts an article into a collection somebody shared, or takes it back out.
    ///
    /// **Only ever this reader's own list.** Every participant writes the
    /// record named after them and reads everybody else's, so there is no
    /// record two people write and no conflict to resolve. What another
    /// participant filed is not this device's to rewrite, and a save that tried
    /// would be refused by the server anyway.
    ///
    /// It follows that **a reader takes back what they put in and nothing
    /// else** : an article somebody else filed is not in this list and cannot
    /// be removed from it.
    ///
    /// The store is written first and the record queued after. The list is what
    /// the page shows, so a reader who files something sees it at once and
    /// whether iCloud was reachable is a separate question.
    func file(_ entry: SharedEntry?, removing guid: String? = nil, inZone zoneName: String, ownedBy owner: String)
        async
    {
        guard let me = await participant() else { return }
        let listKey = SyncRecords.namePrefix(forSharedListBy: me)

        var filed = (try? await entries.entries(inList: listKey, inZone: zoneName)) ?? []
        if let guid { filed.removeAll { $0.guid == guid } }
        if let entry {
            filed.removeAll { $0.guid == entry.guid }
            filed.insert(entry, at: 0)
        }

        try? await entries.replace(filed, inList: listKey, by: me.recordName, inZone: zoneName)
        await push(filed, inList: listKey, inZone: zoneName, ownedBy: owner, by: me)
    }

    /// Sends this reader's list as it now stands.
    private func push(
        _ filed: [SharedEntry],
        inList listKey: String,
        inZone zoneName: String,
        ownedBy owner: String,
        by me: CKRecord.ID
    ) async {
        guard let engine else { return }

        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: owner)
        let records = SharedList.records(for: filed, by: me, in: zoneID)

        // Kept so the batch provider can hand them over : it is synchronous,
        // and building a record needs the store.
        pending = records.reduce(into: pending) { $0[$1.recordID] = $1 }
        engine.state.add(pendingRecordZoneChanges: records.map { .saveRecord($0.recordID) })
    }

    /// Whether this reader put a given article in a given shared collection.
    ///
    /// What the menu draws its tick from, and it is about their own list alone :
    /// an article somebody else filed is in the collection without being
    /// theirs, and a tick against it would offer to remove something they
    /// cannot remove.
    func filedGUIDs(inZone zoneName: String) async -> Set<String> {
        guard let me = await participant() else { return [] }
        let listKey = SyncRecords.namePrefix(forSharedListBy: me)
        let filed = (try? await entries.entries(inList: listKey, inZone: zoneName)) ?? []
        return Set(filed.map(\.guid))
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

    private func apply(_ changes: CKSyncEngine.Event.FetchedDatabaseChanges) async {
        for deletion in changes.deletions {
            await inbox.forget(zone: deletion.zoneID)
        }
    }

    private func apply(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        await inbox.apply(changes.modifications.map(\.record), isOwned: false)
        await inbox.apply(deletions: changes.deletions.map(\.recordID))
    }
}
