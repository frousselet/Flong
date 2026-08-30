//
//  Mark.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import OSLog

/// What the reader has said about one article.
///
/// Starred or not, the note if there is one, and the collections it was filed
/// into. Everything else about an article is a fact its feed reported ; this is
/// the part that is theirs, and the only part worth a record.
///
/// **One record per marked article, and not a month at a time.** Read states
/// compact into a block per month because reading is a thing that happens once
/// and never unhappens : a union merge is right for them, and it is commutative,
/// so two devices writing the same month cannot lose each other's work. A mark
/// is not like that. A star comes off, a note is deleted, an article leaves a
/// collection, and the reader expects the `no` to travel as surely as the `yes`.
/// Carrying that in a block would mean the last device to write a month wins the
/// whole month, and a star made on one device while another was offline would be
/// silently rubbed out. One record per article is the only shape where the `no`
/// travels and nothing is clobbered ; it is what section 8 already budgeted for
/// the library it replaces, and for the same reason : the reader marks a few
/// thousand articles in years, not a hundred thousand.
nonisolated struct Mark: Hashable, Sendable, Codable {
    /// The feed the article came from, which is half of its identity between
    /// devices : a local row identifier means nothing on another one.
    var feedURL: String
    var guid: String
    var isStarred: Bool
    var annotation: String?
    var collections: [String]

    /// What it means, and what that meaning may be compared with.
    ///
    /// Section 14 shares these rather than have each device embed the same
    /// article : an on-device model is not free, and the answer is the same on
    /// every one of them. A vector only compares to vectors of the same model
    /// and revision, so both travel with it.
    var vector: Data?
    var vectorModel: String?
    var vectorRevision: String?

    var fingerprint: ArticleFingerprint? {
        URL(string: feedURL).map { ArticleFingerprint(feedURL: $0, guid: guid) }
    }

    /// Whether it says anything at all.
    ///
    /// An article nobody starred, wrote on or filed has nothing to say, and its
    /// record is deleted rather than kept saying nothing.
    var isEmpty: Bool {
        !isStarred && (annotation?.isEmpty ?? true) && collections.isEmpty
    }

    /// The same mark, with a vector this device has no use for taken out.
    ///
    /// A vector made by another model, or another revision of this one, is
    /// dropped rather than stored : comparing across revisions does not fail
    /// loudly, it quietly returns nonsense. This device computes its own and
    /// republishes it.
    func vetted(by embedder: Embedder) -> Mark {
        guard let model = vectorModel, let revision = vectorRevision.flatMap(Int.init),
            !embedder.isCurrent(model: model, revision: revision)
        else { return self }

        var vetted = self
        vetted.vector = nil
        vetted.vectorModel = nil
        vetted.vectorRevision = nil
        return vetted
    }
}

/// Where the marks are read from and written back to.
///
/// **A mark that arrives before its article waits for it.** The whole stream
/// travels now, so the article is coming, but CloudKit hands over its batches
/// in whatever order it likes and a mark may well land first. Dropping it would
/// lose a star for good ; holding it is one row, drained the moment the article
/// shows up, whether it came from iCloud or from the feed itself. Read states
/// solve the same problem the same way, by keeping the block and applying it
/// again to whatever has arrived since.
nonisolated struct MarkStore: Sendable {
    private let database: AppDatabase
    private let collections: CollectionStore
    private let embedder: Embedder

    init(_ database: AppDatabase, embedder: Embedder = Embedder()) {
        self.database = database
        self.collections = CollectionStore(database)
        self.embedder = embedder
    }

    // MARK: - What this device has to say

    /// Every mark this device holds, including the ones still waiting for their
    /// article.
    ///
    /// The waiting ones are included deliberately : a device that republishes
    /// everything it knows must not quietly drop a star it was told about and
    /// has not been able to apply yet.
    func all() async throws -> [Mark] {
        try await marks(of: nil) + pending()
    }

    /// The marks of a handful of articles, for a change that just happened.
    func marks(of ids: [UUID]) async throws -> [Mark] {
        try await marks(of: ids as [UUID]?)
    }

    private func marks(of ids: [UUID]?) async throws -> [Mark] {
        let memberships = try await collections.memberships()
        let narrowing = ids.map { " AND e.id IN (\(databaseQuestionMarks(count: $0.count)))" } ?? ""

        return try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.id AS id, f.url AS feed_url, e.guid AS guid, e.is_starred AS is_starred,
                           e.annotation AS annotation, e.vector AS vector,
                           e.vector_model AS vector_model, e.vector_revision AS vector_revision
                    FROM entry e JOIN feed f ON f.id = e.feed_id
                    WHERE e.is_hidden = 0 AND e.duplicate_of IS NULL
                      AND (e.is_starred = 1 OR COALESCE(e.annotation, '') <> ''
                           OR e.id IN (SELECT target_id FROM tag_binding WHERE target_kind = 'entry'))
                    \(narrowing)
                    """,
                arguments: StatementArguments(ids ?? [])
            )
            .compactMap { row in
                guard let feedURL = row["feed_url"] as String? else { return nil }
                return Mark(
                    feedURL: feedURL,
                    guid: row["guid"],
                    isStarred: row["is_starred"],
                    annotation: row["annotation"],
                    collections: memberships[row["id"] as UUID] ?? [],
                    vector: row["vector"],
                    vectorModel: row["vector_model"],
                    vectorRevision: row["vector_revision"]
                )
            }
        }
    }

    /// The identity of the articles a change touched, whether or not they are
    /// still marked.
    ///
    /// An article the reader has just unmarked has nothing left to send, and it
    /// is precisely then that the other devices most need to be told. So what a
    /// change answers with is the pair that names the record, and the caller
    /// decides whether it holds a mark or a deletion.
    func identities(of ids: [UUID]) async throws -> [(feedURL: URL, guid: String)] {
        guard !ids.isEmpty else { return [] }

        return try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT f.url AS feed_url, e.guid AS guid
                    FROM entry e JOIN feed f ON f.id = e.feed_id
                    WHERE e.id IN (\(databaseQuestionMarks(count: ids.count)))
                    """,
                arguments: StatementArguments(ids)
            )
            .compactMap { row in
                guard let url = (row["feed_url"] as String?).flatMap(URL.init(string:)) else { return nil }
                return (feedURL: url, guid: row["guid"] as String)
            }
        }
    }

    // MARK: - What another device said

    /// Writes an arriving mark onto the article it names.
    ///
    /// Returns whether it changed anything here. A mark for an article this
    /// device has not fetched yet is held rather than dropped.
    @discardableResult
    func merge(_ arriving: Mark) async throws -> Bool {
        let mark = arriving.vetted(by: embedder)
        guard let feedURL = URL(string: mark.feedURL) else { return false }

        guard let (id, changed) = try await apply(mark, feedURL: feedURL) else {
            try await hold(mark)
            return false
        }

        let filed = try await collections.collections(of: id)
        guard changed || filed != mark.collections else { return false }

        try await collections.set(mark.collections, of: id)
        return true
    }

    /// Takes back everything a mark said, for an article another device
    /// unmarked entirely.
    @discardableResult
    func unmark(_ feedURL: URL, guid: String) async throws -> Bool {
        let id: UUID? = try await database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM pending_mark WHERE feed_url = ? AND guid = ?",
                arguments: [feedURL.absoluteString, guid]
            )

            guard let feed = try Feed.filter(Feed.Columns.url == feedURL).fetchOne(db),
                var entry = try Entry.filter(Column("feed_id") == feed.id && Column("guid") == guid).fetchOne(db)
            else { return nil }

            entry.isStarred = false
            entry.annotation = nil
            try entry.update(db)
            return entry.id
        }

        guard let id else { return false }
        try await collections.set([], of: id)
        return true
    }

    /// Applies the marks whose article has arrived since they did.
    ///
    /// Returns how many it could finally write, which is what a synchronization
    /// reports and what makes the waiting visible rather than magical.
    @discardableResult
    func drain() async throws -> Int {
        let waiting = try await pending()
        guard !waiting.isEmpty else { return 0 }

        var applied = 0
        for mark in waiting {
            guard let feedURL = URL(string: mark.feedURL),
                let (id, _) = try await apply(mark, feedURL: feedURL)
            else { continue }

            try await collections.set(mark.collections, of: id)
            try await database.writer.write { db in
                try db.execute(
                    sql: "DELETE FROM pending_mark WHERE feed_url = ? AND guid = ?",
                    arguments: [mark.feedURL, mark.guid]
                )
            }
            applied += 1
        }
        return applied
    }

    // MARK: - Rows

    /// Writes a mark onto its article, when this device holds it.
    ///
    /// Answers with the article and whether anything on it actually moved. A
    /// record that arrives twice must change nothing the second time, and a
    /// synchronization that reported one marked article every hour for the same
    /// unchanged star would be a report worth nothing.
    private func apply(_ mark: Mark, feedURL: URL) async throws -> (id: UUID, changed: Bool)? {
        try await database.writer.write { db in
            guard let feed = try Feed.filter(Feed.Columns.url == feedURL).fetchOne(db),
                var entry = try Entry.filter(Column("feed_id") == feed.id && Column("guid") == mark.guid).fetchOne(db)
            else { return nil }

            var changed = entry.isStarred != mark.isStarred || entry.annotation != mark.annotation
            entry.isStarred = mark.isStarred
            entry.annotation = mark.annotation
            // Only when this device has none : a vector it computed itself is
            // as good, and rewriting it would be work for no answer.
            if entry.vector == nil, mark.vector != nil {
                entry.vector = mark.vector
                entry.vectorModel = mark.vectorModel
                entry.vectorRevision = mark.vectorRevision
                changed = true
            }
            try entry.update(db)
            return (entry.id, changed)
        }
    }

    private func hold(_ mark: Mark) async throws {
        guard let payload = try? JSONEncoder().encode(mark) else { return }

        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO pending_mark (feed_url, guid, payload, received_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT (feed_url, guid) DO UPDATE SET payload = excluded.payload,
                        received_at = excluded.received_at
                    """,
                arguments: [mark.feedURL, mark.guid, payload, Date()]
            )
        }
    }

    /// The marks still waiting for their article.
    func pending() async throws -> [Mark] {
        try await database.writer.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM pending_mark ORDER BY received_at")
                .compactMap { try? JSONDecoder().decode(Mark.self, from: $0) }
        }
    }
}
