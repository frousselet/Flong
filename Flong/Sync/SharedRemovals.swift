//
//  SharedRemovals.swift
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
import GRDB
import OSLog

/// What the owner of a shared collection has taken out of it.
///
/// **The answer to the question the design left open.** One list per
/// participant means a person takes back what they put in and nothing else,
/// which is what removes conflict resolution from the whole design : nobody
/// rewrites anybody's record. The owner of a collection does need more than
/// that, and the shape that keeps the property is exactly this : a list of
/// their own saying what they have taken down, merging the same way as
/// everything else.
///
/// **It is a filter and never a deletion.** The filer's list still carries the
/// article, and their next edit sends the whole list again : a removal that
/// deleted rows would be undone by the next thing that person filed. So nothing
/// is deleted, the row is simply never shown, and applying one removal twice
/// does nothing the first did not. Union, commutative, idempotent, like every
/// other merge in section 7.
///
/// **Only the owner's copy counts.** A participant has write access to the zone
/// and could perfectly well save a record of this type ; naming it after the
/// writer means their record is one of their own rather than one that
/// overwrites the owner's, and the author check on the way in means nobody
/// reads it. A participant who wants their own filing out takes it out of their
/// own list, which is what they have always been able to do.
nonisolated enum SharedRemovals {
    /// How many removals one collection keeps.
    ///
    /// A guid is a few tens of bytes, so this is a long way under the record
    /// limit and a longer way past any collection anybody will fill. The cap
    /// exists so the record cannot grow without bound over years, and the
    /// oldest go first because a removal only matters while somebody's list
    /// may still be offering the thing.
    static let limit = 5000

    // MARK: - Sending

    /// The owner's list of what is out, as one record.
    static func record(for guids: [String], by owner: CKRecord.ID, in zone: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: SyncRecords.RecordType.sharedRemovals,
            recordID: CKRecord.ID(recordName: SyncRecords.name(forSharedRemovalsBy: owner), zoneID: zone)
        )

        let kept = Array(guids.suffix(limit))
        let payload = (try? JSONEncoder().encode(kept)) ?? Data()
        record["guids"] = SyncRecords.compressed(String(decoding: payload, as: UTF8.self))
        return record
    }

    // MARK: - Receiving

    /// What a record says is out, or nothing where it is not the owner's.
    ///
    /// `owner` is the zone's owner as CloudKit names them, which is what the
    /// record's creator has to match. It is `nil` on the owner's own device,
    /// where the zone is in their private database and says `__defaultOwner__`
    /// rather than who they are : a record in a zone of their own that they
    /// wrote is one they wrote, and there is nothing to check.
    static func guids(from record: CKRecord, ownedBy owner: String?) -> [String]? {
        guard record.recordType == SyncRecords.RecordType.sharedRemovals else { return nil }

        if let owner, SharedList.author(of: record) != owner {
            // A participant saying what is out of somebody else's collection.
            // Not an error and not worth telling anybody about : it is simply
            // not theirs to say.
            Log.sync.notice("A list of removals was not the owner's, and was left alone")
            return nil
        }

        guard let payload = SyncRecords.expanded(record["guids"] as? Data),
            let decoded = try? JSONDecoder().decode([String].self, from: Data(payload.utf8))
        else { return nil }

        return decoded.compactMap { SharedEntry.bounded($0, to: 500) }.prefix(limit).map { $0 }
    }
}

/// What has been taken out of each shared collection.
nonisolated struct SharedRemovalStore: Sendable {
    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    /// Everything out of one collection, oldest first, which is the order the
    /// record is written in and therefore the order the cap drops from.
    func guids(inZone zoneName: String) async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT guid FROM shared_removal WHERE zone_name = ? ORDER BY removed_at",
                arguments: [zoneName]
            )
        }
    }

    /// Takes one article out of one collection.
    func remove(_ guid: String, inZone zoneName: String, at date: Date = Date()) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO shared_removal (zone_name, guid, removed_at) VALUES (?, ?, ?)
                    ON CONFLICT (zone_name, guid) DO NOTHING
                    """,
                arguments: [zoneName, guid, date]
            )
        }
    }

    /// Applies what the owner's record says, whole.
    ///
    /// **Additive, so that two devices applying it in either order agree.** A
    /// removal that arrived here and is missing from the record is one the
    /// record has dropped past its cap, not one that was taken back : there is
    /// no putting an article back, so nothing here is ever unsaid.
    func apply(_ guids: [String], inZone zoneName: String, at date: Date = Date()) async throws {
        guard !guids.isEmpty else { return }

        try await database.writer.write { db in
            for guid in guids {
                try db.execute(
                    sql: """
                        INSERT INTO shared_removal (zone_name, guid, removed_at) VALUES (?, ?, ?)
                        ON CONFLICT (zone_name, guid) DO NOTHING
                        """,
                    arguments: [zoneName, guid, date]
                )
            }
        }
    }

    /// Everything a collection that has gone had taken out.
    func forget(zoneName: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM shared_removal WHERE zone_name = ?", arguments: [zoneName])
        }
    }
}
