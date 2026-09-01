//
//  SharedList.swift
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
import GRDB
import OSLog

/// What one person put in a shared collection.
///
/// **One record per participant, and never one per article.** Each person
/// writes only their own list and reads everybody else's, which is the shape
/// section 7 gives the stream archives and for the same reason : *file
/// synchronization goes wrong when two devices write one file and somebody has
/// to resolve a conflict nobody can resolve correctly.* With participants in
/// the place of devices, two people filing at the same moment cannot collide,
/// there is no merge to get wrong and there is no conflict resolution to write.
///
/// It follows that **a person takes back what they put in, and nothing else.**
/// Removing an article is a rewrite of your own list, and a rewrite of a record
/// one person owns is not a lost update.
///
/// **It is affordable only because a body never travels.** An excerpt with its
/// title, address, date and byline is under a kilobyte, so a collection of a
/// thousand articles still fits inside a single record. Chunking exists for the
/// day that stops being true, and will rarely be reached.
nonisolated enum SharedList {
    /// How much of a record the entries may fill.
    ///
    /// The same margin ``CatchUpHeaders`` keeps, and for the same reason : a
    /// save refused for being a few bytes over the limit costs a great deal
    /// more than a chunk cut early.
    static let chunkLimit = 700 * 1024

    // MARK: - Sending

    /// One person's list, cut into as many records as its bytes need.
    ///
    /// The participant is named by their own record in the container, which is
    /// stable for them and which two of their devices work out to the same
    /// value : a reader filing from their iPad rewrites the list they filed
    /// from their iPhone rather than opening a second one.
    static func records(
        for entries: [SharedEntry],
        by participant: CKRecord.ID,
        in zone: CKRecordZone.ID
    ) -> [CKRecord] {
        var records: [CKRecord] = []
        var batch: [SharedEntry] = []
        var size = 0

        func flush() {
            guard let payload = try? JSONEncoder().encode(batch) else { return }
            let record = CKRecord(
                recordType: SyncRecords.RecordType.sharedList,
                recordID: CKRecord.ID(
                    recordName: SyncRecords.name(forSharedListBy: participant, chunk: records.count),
                    zoneID: zone
                )
            )
            record["entries"] = SyncRecords.compressed(String(decoding: payload, as: UTF8.self))
            records.append(record)
            batch = []
            size = 0
        }

        for entry in entries {
            let weight = entry.weight
            if size > 0, size + weight > chunkLimit { flush() }
            batch.append(entry)
            size += weight
            if size >= chunkLimit { flush() }
        }

        // Always at least one record, even for a list of nothing : emptying a
        // list is a change that has to travel, and a record that stopped being
        // written would leave everybody else showing what was taken out.
        if !batch.isEmpty || records.isEmpty { flush() }
        return records
    }

    // MARK: - Receiving

    /// The entries a record carries, bounded, or nothing where it carries none.
    ///
    /// Everything here came off another person's device, so nothing is trusted
    /// for having been written by a copy of this application : each entry is
    /// put through ``SharedEntry/received`` and the ones with nothing usable
    /// left are dropped rather than stored empty.
    static func entries(from record: CKRecord) -> [SharedEntry] {
        guard record.recordType == SyncRecords.RecordType.sharedList,
            let payload = SyncRecords.expanded(record["entries"] as? Data),
            let decoded = try? JSONDecoder().decode([SharedEntry].self, from: Data(payload.utf8))
        else { return [] }

        return decoded.map(\.received).filter(\.isUsable)
    }

    /// Whoever wrote a record, as CloudKit names them.
    ///
    /// The server sets it and a client cannot, which is what makes it worth
    /// attributing anything to : a participant who wrote somebody else's name
    /// into a field of their own would be believed, and this cannot be written
    /// at all.
    ///
    /// It is for saying who on the page, and never for finding a row : a record
    /// that is deleted carries no author, so ``SyncRecords/listKey(ofRecordNamed:)``
    /// is what the store is keyed by.
    static func author(of record: CKRecord) -> String {
        record.creatorUserRecordID?.recordName ?? CKCurrentUserDefaultName
    }
}

/// The articles of the collections the reader shares or was invited to.
nonisolated struct SharedEntryStore: Sendable {
    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    /// What one participant put in one shared collection.
    ///
    /// The reader's own list is what they may add to and take from : an article
    /// somebody else filed is in the collection without being theirs.
    func entries(inList listKey: String, inZone zoneName: String) async throws -> [SharedEntry] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM shared_entry WHERE zone_name = ? AND list_key = ?
                    ORDER BY COALESCE(published_at, received_at) DESC
                    """,
                arguments: [zoneName, listKey]
            )
            .map(Self.entry(from:))
        }
    }

    /// Everything in one shared collection, most recently published first.
    ///
    /// `excluding` leaves out one participant's list, which is what the owner
    /// of a collection wants : they read their own filings from their own
    /// articles, and what they need from here is what everybody else added.
    func entries(inZone zoneName: String, excluding listKey: String? = nil) async throws -> [SharedEntry] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM shared_entry WHERE zone_name = ? AND (? IS NULL OR list_key <> ?)
                    ORDER BY COALESCE(published_at, received_at) DESC
                    """,
                arguments: [zoneName, listKey, listKey]
            )
            .map(Self.entry(from:))
        }
    }

    /// Who filed each thing in one shared collection, by the article's identity.
    ///
    /// Kept apart from the entries themselves because it is about the filing
    /// and not about the article : the same piece filed by two people is one
    /// row, and the name on it is whoever got there first.
    func authors(inZone zoneName: String) async throws -> [String: String] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT guid, author_name FROM shared_entry WHERE zone_name = ?",
                arguments: [zoneName]
            )
            .reduce(into: [:]) { found, row in found[row["guid"] as String] = row["author_name"] as String }
        }
    }

    /// Replaces what one person has in one collection.
    ///
    /// **The whole of that person's list, every time.** What arrives about one
    /// participant is the whole truth about what they filed, so an article
    /// missing from it is one they took out : applying the additions alone
    /// would leave everybody else showing a filing that was removed.
    ///
    /// Only their own rows are touched. Another participant's are none of this
    /// record's business, and rewriting them from it is how one person's
    /// removal would delete everybody's.
    func replace(
        _ entries: [SharedEntry],
        inList listKey: String,
        by author: String,
        inZone zoneName: String,
        at date: Date = Date()
    ) async throws {
        try await database.writer.write { db in
            // **When a thing arrived is not changed by somebody editing their
            // list.** A list is rewritten whole every time any of it changes,
            // so an article that has been here for a week would be stamped as
            // new the moment its filer added something else, and every notice
            // built on the stamp would announce it again. What was here keeps
            // the moment it turned up.
            let arrived = try Row.fetchAll(
                db,
                sql: "SELECT guid, received_at FROM shared_entry WHERE zone_name = ? AND list_key = ?",
                arguments: [zoneName, listKey]
            )
            .reduce(into: [String: Date]()) { found, row in found[row["guid"] as String] = row["received_at"] as Date }

            try db.execute(
                sql: "DELETE FROM shared_entry WHERE zone_name = ? AND list_key = ?",
                arguments: [zoneName, listKey]
            )

            for entry in entries {
                // Two people filing the same piece is one row, and the first to
                // arrive keeps it : the entry is the article and not the
                // filing, so a second copy would be the same headline twice.
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO shared_entry
                            (id, zone_name, list_key, author_name, guid, title, url, excerpt, author,
                             published_at, image_url, feed_url, source_title, received_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        UUID.v7(), zoneName, listKey, author, entry.guid, entry.title, entry.url,
                        entry.excerpt, entry.author, entry.publishedAt, entry.imageURL,
                        entry.feedURL, entry.sourceTitle, arrived[entry.guid] ?? date,
                    ]
                )
            }
        }
    }

    /// What has turned up in the shared collections since a moment.
    ///
    /// **Not the reader's own**, which is what `excluding` is for : being told
    /// about what you filed yourself is being told what you already know.
    ///
    /// `muted` are the collections the reader has asked to hear nothing about,
    /// left out here rather than filtered afterwards so that a muted collection
    /// cannot move the watermark past a collection that is not.
    func arrived(
        since: Date,
        excluding listKey: String?,
        muted: Set<String> = []
    ) async throws -> [(zone: String, author: String, entry: SharedEntry)] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM shared_entry
                    WHERE received_at > ? AND (? IS NULL OR list_key <> ?)
                    ORDER BY received_at
                    """,
                arguments: [since, listKey, listKey]
            )
            .filter { !muted.contains($0["zone_name"] as String) }
            .map { (zone: $0["zone_name"] as String, author: $0["author_name"] as String, entry: Self.entry(from: $0)) }
        }
    }

    /// Drops everything a collection held, for a share that has gone.
    func forget(zoneName: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM shared_entry WHERE zone_name = ?", arguments: [zoneName])
        }
    }

    private static func entry(from row: Row) -> SharedEntry {
        SharedEntry(
            guid: row["guid"],
            title: row["title"],
            url: row["url"],
            excerpt: row["excerpt"],
            author: row["author"],
            publishedAt: row["published_at"],
            imageURL: row["image_url"],
            feedURL: row["feed_url"],
            sourceTitle: row["source_title"]
        )
    }
}
