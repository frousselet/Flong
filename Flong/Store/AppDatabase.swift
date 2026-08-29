//
//  AppDatabase.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB

/// The local SQLite database, opened and migrated.
///
/// Everything Flong knows lives here : the stream, the library, the tags, the
/// rules and the synchronization tokens. The store is the only writer, and it
/// keeps its schema through ``migrator``.
nonisolated final class AppDatabase: Sendable {
    /// The connection pool, which serializes writes and lets reads run in parallel.
    let writer: any DatabaseWriter

    /// Opens a database on an existing writer and brings its schema up to date.
    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// The database of the running application.
    ///
    /// It sits in Application Support, outside the backup exclusions : the stream
    /// is rebuildable, but the library is not, so the file is worth backing up.
    static func onDisk(folder: URL? = nil) throws -> AppDatabase {
        let folder = try folder ?? defaultFolder()
        try prepare(folder: folder)
        let file = folder.appendingPathComponent("flong.sqlite")
        return try AppDatabase(DatabasePool(path: file.path, configuration: configuration()))
    }

    /// A database living in memory, for tests and previews.
    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: configuration()))
    }

    private static func defaultFolder() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Flong", isDirectory: true)
    }

    /// Creates the containing folder, carrying the data protection class the database needs.
    ///
    /// The class is "after first unlock" : anything stricter would stop the
    /// background tasks of section 15 of the specification from touching the
    /// database while the device is locked. On iOS a file inherits the class of
    /// the folder it is created in, which covers the `-wal` and `-shm` files too.
    private static func prepare(folder: URL) throws {
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
            attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif

        let manager = FileManager.default
        if manager.fileExists(atPath: folder.path) {
            if !attributes.isEmpty {
                try manager.setAttributes(attributes, ofItemAtPath: folder.path)
            }
        } else {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: attributes)
        }
    }

    private static func configuration() -> Configuration {
        var configuration = Configuration()

        // Statement arguments stay out of the trace. Article bodies and secret
        // feed URLs travel through here, and section 20 of the specification
        // forbids logging either of them.
        configuration.publicStatementArguments = false
        configuration.foreignKeysEnabled = true

        return configuration
    }
}
