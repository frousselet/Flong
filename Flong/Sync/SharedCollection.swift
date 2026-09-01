//
//  SharedCollection.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB

/// A collection the reader shared, or was invited to.
///
/// **The zone is what this is, and the name is only what it is called.** A
/// `CKShare` reaches one zone and a zone holds one zone-wide share, so a shared
/// collection is a zone of its own : never the `Flong` zone, which holds every
/// feed, every mark, every read state and the whole stream, and which sharing
/// would hand over in a single gesture.
///
/// **A row here is local and stays local.** The zone and the share are in the
/// reader's private database already, so their other devices learn of both from
/// CloudKit rather than from a record this would have to write. What it holds
/// is the way back : from a collection the reader made, to the zone standing
/// for it.
nonisolated struct SharedCollection: Identifiable, Hashable, Sendable {
    var id: UUID
    /// The zone in the owner's private database.
    var zoneName: String
    /// Whose zone it is. `CKCurrentUserDefaultName` for one of the reader's.
    var ownerName: String
    /// The made collection behind it, when the reader is the one sharing.
    ///
    /// A collection they were invited to has no tag of theirs behind it, so it
    /// has none of these and is known by its ``title`` alone.
    var collectionName: String?
    /// What it is called, which is the name the share carries.
    var title: String
    var isOwned: Bool
    /// Where the invitation points, once the system has made one.
    var shareURL: URL?
    var createdAt: Date
}

/// Which collections are shared, and which zone each of them is.
nonisolated struct SharedCollectionStore: Sendable {
    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    /// The share standing for one of the reader's own collections, if it is
    /// shared at all.
    func owned(named name: String) async throws -> SharedCollection? {
        try await database.writer.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM shared_collection WHERE collection_name = ? AND is_owned = 1",
                arguments: [name]
            )
            .map(Self.shared(from:))
        }
    }

    func all() async throws -> [SharedCollection] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM shared_collection ORDER BY created_at")
                .map(Self.shared(from:))
        }
    }

    /// The names of the reader's collections that are shared, for a page that
    /// wants to say so against each square without asking once per square.
    func ownedNames() async throws -> Set<String> {
        try await database.writer.read { db in
            try Set(
                String.fetchAll(
                    db,
                    sql: """
                        SELECT collection_name FROM shared_collection
                        WHERE is_owned = 1 AND collection_name IS NOT NULL
                        """
                )
            )
        }
    }

    /// The squares for the collections somebody else shared.
    ///
    /// Only those : a collection the reader shared themselves is still the made
    /// one it always was, and showing it twice would say sharing had turned it
    /// into something else.
    func invited(from entries: SharedEntryStore) async throws -> [ArticleCollection] {
        let mine = try await all().filter { !$0.isOwned }
        guard !mine.isEmpty else { return [] }

        var found: [ArticleCollection] = []
        for shared in mine {
            let held = try await entries.entries(inZone: shared.zoneName)
            found.append(
                ArticleCollection(
                    kind: .shared(zone: shared.zoneName, title: shared.title),
                    count: held.count,
                    cover: held.compactMap(\.imageURL).first.flatMap(URL.init(string:))
                )
            )
        }
        return found.sorted { CollectionStore.before($0.name ?? "", $1.name ?? "") }
    }

    func remember(_ shared: SharedCollection) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO shared_collection
                        (id, zone_name, owner_name, collection_name, title, is_owned, share_url, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (zone_name) DO UPDATE SET
                        collection_name = excluded.collection_name,
                        title = excluded.title,
                        share_url = excluded.share_url
                    """,
                arguments: [
                    shared.id, shared.zoneName, shared.ownerName, shared.collectionName,
                    shared.title, shared.isOwned, shared.shareURL?.absoluteString, shared.createdAt,
                ]
            )
        }
    }

    /// Where the invitation points, once the system has made one.
    ///
    /// It is not known when the share is created : the system fills the address
    /// in when the reader actually picks somebody to send it to.
    func setShareURL(_ url: URL?, forZone zoneName: String) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE shared_collection SET share_url = ? WHERE zone_name = ?",
                arguments: [url?.absoluteString, zoneName]
            )
        }
    }

    /// Follows a collection the reader renamed.
    ///
    /// The share's own title is not renamed with it. What the participants see
    /// is what they were invited to, and a name changing under them would be a
    /// second collection as far as they could tell.
    func rename(_ name: String, to renamed: String) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE shared_collection SET collection_name = ? WHERE collection_name = ? AND is_owned = 1",
                arguments: [renamed, name]
            )
        }
    }

    func forget(zoneName: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM shared_collection WHERE zone_name = ?", arguments: [zoneName])
        }
    }

    private static func shared(from row: Row) -> SharedCollection {
        SharedCollection(
            id: row["id"],
            zoneName: row["zone_name"],
            ownerName: row["owner_name"],
            collectionName: row["collection_name"],
            title: row["title"],
            isOwned: row["is_owned"],
            shareURL: (row["share_url"] as String?).flatMap(URL.init(string:)),
            createdAt: row["created_at"]
        )
    }
}
