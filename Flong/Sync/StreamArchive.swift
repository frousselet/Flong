//
//  StreamArchive.swift
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

/// The whole stream, as files in the reader's own iCloud.
///
/// **Why files and not records.** The reader keeps every article for good, and
/// a store that charges by the record cannot carry that : the count grows with
/// the data, and section 7 records the arithmetic, six figures for three
/// hundred feeds over a few years, which is where CloudKit starts refusing
/// saves and then rate limiting durably. iCloud Documents charges for bytes,
/// and bytes are what the reader said they had.
///
/// **One writer per file, which is the whole trick.** File synchronization goes
/// wrong when two devices write the same file, and then somebody has to resolve
/// a conflict nobody can resolve correctly. Here each device writes only inside
/// its own folder and reads everybody else's, so no file is ever written twice
/// and there is no conflict to have. It is an append-only log per device, which
/// is the shape that merges by doing nothing.
///
/// One file per device and per day. Three devices over three years is around
/// three thousand files, each sealed the day after it is written and never
/// touched again.
///
/// **This is the slow half.** A record pushed through `CKSyncEngine` arrives in
/// seconds ; a file in iCloud Documents arrives when it arrives, downloads on
/// demand, and has no push behind it. ``CatchUpHeaders`` still carries the near
/// end of the history for that reason, and this carries the rest.
nonisolated struct StreamArchive: Sendable {
    /// The folder the archives live in, inside the container's documents.
    static let folder = "Stream"
    static let fileExtension = "stream"

    private let database: AppDatabase
    private let root: URL?
    private let device: String

    /// - Parameters:
    ///   - root: where the archives live. Absent when there is no iCloud
    ///     account, or no entitlement yet, in which case everything here does
    ///     nothing at all rather than failing.
    ///   - device: which folder this device writes into, and the one it never
    ///     reads back.
    init(_ database: AppDatabase, root: URL?, device: String) {
        self.database = database
        self.root = root
        self.device = device
    }

    /// Where the container puts its documents, when there is one.
    ///
    /// This asks the file coordinator and can take a moment, so it is not for
    /// a screen to call : it belongs to the work that already happens away from
    /// the reader.
    static func ubiquityRoot(_ manager: FileManager = .default) -> URL? {
        guard let container = manager.url(forUbiquityContainerIdentifier: nil) else { return nil }
        return container.appending(path: "Documents").appending(path: folder)
    }

    /// A day of every feed, as one file.
    nonisolated struct Day: Codable, Sendable {
        var day: String
        var feeds: [Feed]

        nonisolated struct Feed: Codable, Sendable {
            var url: String
            var headers: [StreamBlock.Header]
        }
    }

    // MARK: - Writing

    /// Writes this device's own days, and returns how many files it wrote.
    ///
    /// `since` narrows which days are worth writing again : a day nothing
    /// arrived in since the last pass is a day whose file is already right.
    /// Today's file is rewritten as the day fills and sealed by the day ending,
    /// which is the only file that is ever written more than once.
    @discardableResult
    @concurrent
    func write(since: Date = .distantPast) async throws -> Int {
        guard let root else { return 0 }

        let groups = try await StreamBlock.groups(in: database, since: since)
        guard !groups.isEmpty else { return 0 }

        let mine = root.appending(path: device)
        try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)

        var days: [String: [Day.Feed]] = [:]
        for group in groups {
            days[group.day, default: []].append(Day.Feed(url: group.url.absoluteString, headers: group.headers))
        }

        var written = 0
        for (day, feeds) in days {
            let encoded = try JSONEncoder().encode(Day(day: day, feeds: feeds))
            let payload = (try? (encoded as NSData).compressed(using: .lzfse) as Data) ?? encoded

            // Atomic, and not coordinated : coordination is what keeps two
            // writers from tearing each other's file, and there is only ever
            // one writer here.
            try payload.write(to: mine.appending(path: "\(day).\(Self.fileExtension)"), options: .atomic)
            written += 1
        }

        Log.sync.notice("Wrote \(written) days of the stream to iCloud")
        return written
    }

    // MARK: - Reading

    /// Reads every other device's days that this one has not read yet.
    ///
    /// A file already read is skipped unless it has changed since, which is
    /// what makes this cheap to run often : the ledger is kept locally, since
    /// what one device has ingested is nobody else's business.
    @discardableResult
    @concurrent
    func ingest(read: Set<ArticleFingerprint>, at now: Date = Date()) async throws -> Int {
        guard let root, FileManager.default.fileExists(atPath: root.path()) else { return 0 }

        let manager = FileManager.default
        let devices = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var added = 0

        for folder in devices where folder.lastPathComponent != device {
            let files =
                (try? manager.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                )) ?? []

            for file in files where file.pathExtension == Self.fileExtension {
                let name = folder.lastPathComponent + "/" + file.lastPathComponent
                let modified =
                    (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast

                guard try await isWorthReading(name, modified: modified) else { continue }
                guard let payload = try? Data(contentsOf: file) else {
                    // Not on this device yet. Ask for it and come back : there
                    // is no point blocking a refresh on a download nobody is
                    // waiting for.
                    try? manager.startDownloadingUbiquitousItem(at: file)
                    continue
                }

                added += try await apply(payload, read: read, at: now)
                try await markRead(name, modified: modified, at: now)
            }
        }

        if added > 0 { Log.sync.notice("Took \(added) articles from another device's archive") }
        return added
    }

    private func apply(_ payload: Data, read: Set<ArticleFingerprint>, at now: Date) async throws -> Int {
        let expanded = (try? (payload as NSData).decompressed(using: .lzfse) as Data) ?? payload
        guard let day = try? JSONDecoder().decode(Day.self, from: expanded) else { return 0 }

        var added = 0
        for feed in day.feeds {
            guard let url = URL(string: feed.url) else { continue }
            added += try await StreamBlock.apply(feed.headers, from: url, into: database, read: read, at: now)
        }
        return added
    }

    // MARK: - Starting over

    /// Deletes the whole archive from iCloud, every device's folder included.
    ///
    /// **All of it, and not only this device's own.** Everywhere else the rule
    /// is that a device writes inside its own folder and never touches
    /// anybody's else, which is what makes this a log with no conflicts to
    /// resolve. This is the one operation that is not a write : a reader
    /// asking for everything to go means the whole of what Flong put in their
    /// iCloud Drive, and leaving three other folders standing would be
    /// answering a different question.
    ///
    /// Another device that still holds the stream will write its own days out
    /// again, which is the same thing the record zone does and is said plainly
    /// in the interface.
    ///
    /// Coordinated, unlike the writes : the files may be being read or written
    /// by another process on this device at the moment they go.
    func erase() throws {
        guard let root, FileManager.default.fileExists(atPath: root.path()) else { return }

        var failure: (any Error)?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: root, options: .forDeleting, error: &coordinationError) { url in
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                failure = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let failure { throw failure }

        Log.sync.notice("The shared archive was deleted from iCloud")
    }

    // MARK: - The ledger

    private func isWorthReading(_ name: String, modified: Date) async throws -> Bool {
        try await database.writer.read { db in
            let seen = try Date.fetchOne(
                db,
                sql: "SELECT modified_at FROM archive_ingest WHERE name = ?",
                arguments: [name]
            )
            guard let seen else { return true }
            return modified > seen
        }
    }

    private func markRead(_ name: String, modified: Date, at now: Date) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO archive_ingest (name, modified_at, ingested_at) VALUES (?, ?, ?)
                    ON CONFLICT(name) DO UPDATE SET modified_at = excluded.modified_at,
                                                    ingested_at = excluded.ingested_at
                    """,
                arguments: [name, modified, now]
            )
        }
    }
}
