//
//  CloudSync.swift
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
import OSLog

/// Synchronization, on the reader's own private database.
///
/// Section 7 of the specification is explicit that none of the hard parts are
/// written here : `CKSyncEngine` owns the scheduling, the batching, the
/// subscriptions, the retries and the backoff. What is written here is the two
/// questions it cannot answer, which live in ``SyncPayload`` : what this device
/// has to say, and what to do with what it hears.
///
/// This is the one file of the project that cannot be tested from the outside.
/// It needs an account, a container and a network, none of which a test may
/// assume. Everything either side of it is tested instead : the records, the
/// merge, the compaction and the failure classification.
actor CloudSync {
    /// The container the reader's own data lives in.
    static let containerIdentifier = "iCloud.com.rslt.Flong"

    private let database: AppDatabase
    private let payload: SyncPayload
    private let state: SyncState
    /// What a record belonging to one of the reader's shared collections means.
    /// Their own shared zones are in this database, so their participants'
    /// records arrive here : see ``SharedInbox``.
    private let inbox: SharedInbox
    private let container: CKContainer
    private let zoneID: CKRecordZone.ID
    private let report: @Sendable (SyncStatus) -> Void

    private var engine: CKSyncEngine?
    private var status: SyncStatus = .idle(lastSynchronized: nil) {
        didSet { report(status) }
    }

    init(
        database: AppDatabase,
        container: CKContainer = CKContainer(identifier: CloudSync.containerIdentifier),
        report: @escaping @Sendable (SyncStatus) -> Void = { _ in }
    ) {
        self.database = database
        self.container = container
        self.zoneID = CKRecordZone.ID(zoneName: SyncRecords.zoneName, ownerName: CKCurrentUserDefaultName)
        self.payload = SyncPayload(database, zone: zoneID)
        self.state = SyncState(database)
        self.inbox = SharedInbox(database)
        self.report = report
    }

    // MARK: - Running

    /// Starts synchronizing, unless there is no account to synchronize with.
    ///
    /// No account is not an error. Section 3 of the specification says Flong is
    /// fully usable on one device without iCloud, and the interface says so
    /// rather than complaining.
    func start() async {
        guard engine == nil else { return }

        do {
            guard try await container.accountStatus() == .available else {
                status = .unavailable
                return
            }
        } catch {
            status = SyncFailure.status(for: error)
            return
        }

        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: await serialization(),
            delegate: self
        )
        configuration.automaticallySync = true

        engine = CKSyncEngine(configuration)
        Log.sync.notice("Synchronization started")

        // A device that has never spoken says everything it knows, once.
        if await serialization() == nil {
            await enqueueEverything()
        }
    }

    /// Sends and fetches now, which is what a pull to refresh means.
    func synchronize() async {
        guard let engine else {
            await start()
            return
        }

        status = .working
        do {
            try await engine.sendChanges()
            try await engine.fetchChanges()
            status = .idle(lastSynchronized: Date())
        } catch {
            status = SyncFailure.status(for: error)
            Log.sync.error("Synchronization failed : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Forgets everything this device remembers about past exchanges, and
    /// starts again as though it had never spoken.
    ///
    /// **Three things are forgotten, and all three are needed.** Queueing every
    /// local record, which is what ``enqueueEverything()`` does, only sends :
    /// the engine still holds a change token, so it asks the server for what
    /// changed since that token and is told, correctly, that nothing did. A
    /// device whose copy has drifted learns nothing from that.
    ///
    /// - The engine's serialized state, which holds the change tokens. Without
    ///   it a new engine fetches the zone from the beginning.
    /// - What the server said about each record, so nothing is skipped for
    ///   having a tag that looks current.
    /// - The ledger of which shared archives have been read, so the days other
    ///   devices wrote are taken in again rather than skipped as seen.
    ///
    /// Expensive by construction and a development command for that reason :
    /// it spends the whole record budget of section 7 in one exchange.
    func resetFromScratch() async {
        engine = nil

        do {
            try await state.setEngineState(nil)
            try await state.forgetEveryRecord()
            try await payload.forgetEveryArchiveRead()
        } catch {
            Log.sync.error("Nothing could be forgotten : \(error.localizedDescription, privacy: .public)")
        }

        Log.sync.notice("Synchronization was reset, and starts again from nothing")
        await start()
    }

    /// Deletes the reader's zone from their iCloud, and forgets it ever existed.
    ///
    /// **The copy in iCloud goes with the local one, or the reset undoes
    /// itself.** Deleting the database alone would leave the engine's next
    /// fetch pulling the whole of the zone straight back down, and a reader who
    /// asked for everything to go would watch it all return. So the zone is
    /// deleted first, while the tokens that address it are still here, and what
    /// this device remembers about past exchanges is dropped afterwards.
    ///
    /// **What another device holds is not this device's to delete.** One that
    /// still has the reader's subscriptions will find the zone gone, take that
    /// as `zoneNotFound`, recreate it and put its own copy back : that is the
    /// existing repair path of ``handle(_:)`` and it is correct. The interface
    /// says so plainly rather than promising a reach this design does not have.
    ///
    /// Nothing to delete is not a failure : a reader with no iCloud account has
    /// no engine, and everything here is a no-op for them.
    func eraseEverything() async {
        guard let engine else { return }

        // Anything already queued would recreate what is about to be deleted,
        // since a save carries its zone with it.
        engine.state.remove(pendingRecordZoneChanges: engine.state.pendingRecordZoneChanges)
        engine.state.remove(pendingDatabaseChanges: engine.state.pendingDatabaseChanges)
        engine.state.add(pendingDatabaseChanges: [.deleteZone(zoneID)])

        do {
            try await engine.sendChanges()
            Log.sync.notice("The zone was deleted from the reader's iCloud")
        } catch {
            Log.sync.error("The zone could not be deleted : \(error.localizedDescription, privacy: .public)")
        }

        // Whatever the server said, this device is starting again from nothing.
        // The tables these live in are erased a moment later ; forgetting them
        // here is what stops the engine writing its state back into the fresh
        // schema on the way out.
        self.engine = nil
        try? await state.setEngineState(nil)
        try? await state.forgetEveryRecord()
        status = .idle(lastSynchronized: nil)
    }

    /// Queues everything this device holds, for a first exchange or a repair.
    func enqueueEverything() async {
        guard let engine else { return }

        do {
            let names = try await payload.everyRecordName()
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            engine.state.add(pendingRecordZoneChanges: names.map { .saveRecord(recordID(for: $0)) })
            Log.sync.notice("Queued \(names.count) records for a first exchange")
        } catch {
            Log.sync.error("Nothing could be queued : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Queues what changed, which is what every local edit calls.
    func enqueue(recordNames names: [String]) {
        guard let engine, !names.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: names.map { .saveRecord(recordID(for: $0)) })
    }

    func enqueue(deletions names: [String]) {
        guard let engine, !names.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: names.map { .deleteRecord(recordID(for: $0)) })
    }

    /// Deletes from iCloud everything one source ever put there.
    ///
    /// **Four kinds of record, and the reader's iCloud holds all four.** The
    /// subscription, so the reader's other devices stop following it too ; one
    /// record for each article they had marked under it, since a mark is the
    /// one thing here that is theirs rather than the publisher's ; every block
    /// of that feed's stream this device wrote, which is the bulk of them ; and
    /// the name they had written over the publisher, when the source that went
    /// was its last.
    ///
    /// The blocks are found by name rather than worked out : the days are gone
    /// with the articles, and a day cut into three records is three names only
    /// the ledger of what was saved still knows.
    func enqueueRemoval(ofFeed url: URL, marks: [String], sourceName: String?) async {
        var names = [SyncRecords.name(forFeed: url)] + marks
        if let sourceName { names.append(sourceName) }
        names += (try? await state.names(startingWith: SyncRecords.namePrefix(forCatchUpFeed: url))) ?? []

        enqueue(deletions: names)
        Log.sync.notice("Queued \(names.count) records for deletion with a source")
    }

    /// Queues what this device saw lately, so a device that was switched off
    /// learns what it missed, and drops what has fallen out of the window.
    func enqueueCatchUp(now: Date = Date()) async {
        do {
            let changes = try await payload.catchUpChanges(now: now)
            enqueue(recordNames: changes.records.map(\.recordID.recordName))
            enqueue(deletions: changes.expired)
        } catch {
            Log.sync.error("The catch up headers failed : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Compacts what has been read and queues the blocks that changed.
    func enqueueReadStates() async {
        do {
            let records = try await payload.readStateChanges()
            enqueue(recordNames: records.map(\.recordID.recordName))
        } catch {
            Log.sync.error("The read states could not be compacted : \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recordID(for name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    private func serialization() async -> CKSyncEngine.State.Serialization? {
        guard let data = try? await state.engineState() else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }
}

extension CloudSync: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            // Losing this is not a catastrophe, only a slow and expensive way to
            // learn nothing new, so it is written down after every exchange.
            let data = try? JSONEncoder().encode(update.stateSerialization)
            try? await state.setEngineState(data)

        case .accountChange(let change):
            await handle(change)

        case .fetchedDatabaseChanges(let changes):
            // A zone gone from this database is one of the reader's own shared
            // collections, stopped from another of their devices. The `Flong`
            // zone going is the erasure of section 20 and is handled where the
            // engine reports it, as `zoneNotFound` on the next save.
            for deletion in changes.deletions where deletion.zoneID != zoneID {
                await inbox.forget(zone: deletion.zoneID)
            }

        case .fetchedRecordZoneChanges(let changes):
            await apply(changes)

        case .sentRecordZoneChanges(let sent):
            await handle(sent)

        case .willFetchChanges, .willSendChanges:
            status = .working

        case .didFetchChanges, .didSendChanges:
            status = .idle(lastSynchronized: Date())

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

        // The records are gathered before the batch is built : the provider the
        // batch takes is synchronous, and the store is not.
        let names = Set(
            changes.compactMap { change -> String? in
                guard case .saveRecord(let id) = change else { return nil }
                return id.recordName
            }
        )
        let records = (try? await payload.records(named: names)) ?? [:]

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            records[recordID.recordName]
        }
    }

    // MARK: - Events

    private func apply(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        // What the server hands over is also what it will expect back : the
        // tag travels with it, and a save built without it is refused.
        try? await state.remember(changes.modifications.map(\.record))
        try? await state.forget(changes.deletions.map(\.recordID.recordName))

        // **The reader's own shared collections are in this database too.** A
        // zone-wide share lives in the owner's private database, so what a
        // participant files into one of the reader's collections arrives here
        // rather than through the shared engine, and it means something this
        // payload has never heard of. Sorted out first, and by zone : nothing
        // but a shared collection is ever put in a zone that is not `Flong`.
        let mine = changes.modifications.map(\.record).filter { !SharedInbox.belongsHere($0.recordID) }
        let shared = changes.modifications.map(\.record).filter { SharedInbox.belongsHere($0.recordID) }
        let removedElsewhere = changes.deletions.map(\.recordID).filter(SharedInbox.belongsHere)

        if !shared.isEmpty || !removedElsewhere.isEmpty {
            await inbox.apply(shared, isOwned: true)
            await inbox.apply(deletions: removedElsewhere)
            Log.sync.notice("A participant filed \(shared.count) records into a shared collection")
        }

        do {
            let applied = try await payload.apply(mine)
            let removed = try await payload.apply(
                deletions: changes.deletions.map(\.recordID).filter { !SharedInbox.belongsHere($0) }
                    .map(\.recordName)
            )

            if !applied.isEmpty || !removed.isEmpty {
                Log.sync.notice(
                    """
                    Applied \(applied.feeds) feeds, \(applied.markedArticles) marked articles, \
                    \(applied.readArticles) read states, \(removed.removed) removals
                    """
                )
            }
        } catch {
            Log.sync.error("Changes could not be applied : \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) async {
        try? await state.remember(sent.savedRecords)
        try? await state.forget(sent.deletedRecordIDs.map(\.recordName))

        for failure in sent.failedRecordSaves {
            switch failure.error.code {
            case .serverRecordChanged:
                // The only real conflict is two devices adding to the same month
                // of read states at once, and its merge is a union.
                guard let server = failure.error.serverRecord else { continue }

                // The server has just said what it holds and under which tag.
                // Keeping the tag is what stops the retry being refused for
                // the same reason as the attempt.
                try? await state.remember([server])

                if let reconciled = payload.reconciled(server, with: failure.record) {
                    engine?.state.add(pendingRecordZoneChanges: [.saveRecord(reconciled.recordID)])
                }

            case .zoneNotFound:
                // A shared collection's zone, taken down by its owner. Nothing
                // to repair : it is not this device's zone and putting it back
                // would recreate a share somebody ended.
                guard failure.record.recordID.zoneID == zoneID else {
                    await inbox.forget(zone: failure.record.recordID.zoneID)
                    continue
                }

                // The zone was deleted from another device or from the settings.
                // Nothing the server said about it holds any more.
                try? await state.forgetEveryRecord()
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                await enqueueEverything()

            case .quotaExceeded:
                status = .quotaExceeded
                Log.sync.error("The reader's iCloud storage is full")

            case .unknownItem:
                // The server does not have it after all, so neither does this.
                try? await state.forget([failure.record.recordID.recordName])

            default:
                if SyncFailure.isTransient(failure.error) {
                    status = SyncFailure.status(for: failure.error)
                } else {
                    Log.sync.error("A record was refused : \(failure.error.errorCode)")
                }
            }
        }
    }

    private func handle(_ change: CKSyncEngine.Event.AccountChange) async {
        switch change.changeType {
        case .signIn:
            await enqueueEverything()
            status = .idle(lastSynchronized: nil)

        case .signOut, .switchAccounts:
            // What is here stays here : signing out of iCloud is not a reason
            // to lose what the reader collected.
            try? await state.setEngineState(nil)
            engine = nil
            status = .unavailable

        @unknown default:
            break
        }
    }
}
