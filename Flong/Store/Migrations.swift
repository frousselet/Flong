//
//  Migrations.swift
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

nonisolated extension AppDatabase {
    /// The schema, as an ordered list of migrations.
    ///
    /// A shipped migration is never edited : a schema change is a new
    /// registration, appended after the previous one, because a database in the
    /// field has already run everything above it.
    ///
    /// Identifiers of the store are UUIDv7 and are stored as sixteen byte blobs,
    /// which sort by creation time exactly as the strings would, in less than
    /// half the space.
    ///
    /// The `entry_fts` virtual table of section 6 of the specification is not
    /// here : the full-text index arrives with M1, in its own migration, and
    /// carries the trigger set that keeps it in step with `entry_body`.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
            // A migration edited rather than appended is a mistake. In debug
            // builds it costs a local database ; in the field it would be a
            // corrupted schema.
            migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1.model") { db in
            try createStream(db)
            try createLibrary(db)
            try createOrganization(db)
            try createSyncState(db)
        }

        return migrator
    }

    /// The stream : feeds and their articles, a cache bounded in age and volume.
    private static func createStream(_ db: Database) throws {
        try db.create(table: "feed") { table in
            table.primaryKey("id", .blob)
            table.column("url", .text).notNull().unique()
            table.column("site_url", .text)
            table.column("icon_url", .text)
            table.column("title", .text).notNull()
            table.column("folder", .text)
            table.column("language", .text)

            // HTTP conditionality, sent back on the next request.
            table.column("etag", .text)
            table.column("last_modified", .text)

            // Health, as surfaced in the feed settings. The 304 rate is
            // `not_modified_count` over `fetch_count`.
            table.column("fetch_count", .integer).notNull().defaults(to: 0)
            table.column("not_modified_count", .integer).notNull().defaults(to: 0)
            table.column("failure_count", .integer).notNull().defaults(to: 0)
            table.column("last_failure_reason", .text)
            table.column("last_fetch_at", .datetime)
            table.column("last_success_at", .datetime)
            table.column("quarantined_at", .datetime)

            // Scheduling : the observed median publication gap, and the manual
            // override that wins over it. Both in seconds.
            table.column("observed_interval", .double)
            table.column("refresh_interval", .double)

            // Local settings, never synchronized.
            table.column("reader_mode_enabled", .boolean).notNull().defaults(to: false)
            table.column("loads_images", .boolean).notNull().defaults(to: true)

            table.column("created_at", .datetime).notNull()
        }

        try db.create(table: "entry") { table in
            table.primaryKey("id", .blob)
            table.column("feed_id", .blob).notNull().indexed().references("feed", onDelete: .cascade)

            // The stable identity of the article : its GUID, or the link and the
            // publication date when the feed serves none.
            table.column("guid", .text).notNull()

            table.column("url", .text)
            table.column("title", .text).notNull()
            table.column("excerpt", .text)
            table.column("author", .text)
            table.column("language", .text)
            table.column("published_at", .datetime)
            table.column("updated_at", .datetime)
            table.column("received_at", .datetime).notNull()

            table.column("is_read", .boolean).notNull().defaults(to: false)
            table.column("read_at", .datetime)
            table.column("is_starred", .boolean).notNull().defaults(to: false)
            table.column("is_hidden", .boolean).notNull().defaults(to: false)

            // Enclosures travel with their article and are only ever read whole,
            // so they stay a JSON array rather than a table of their own.
            table.column("enclosures", .jsonText)
            table.column("has_media", .boolean).notNull().defaults(to: false)
        }

        try db.create(index: "entry_on_feed_guid", on: "entry", columns: ["feed_id", "guid"], options: .unique)
        try db.create(index: "entry_on_published_at", on: "entry", columns: ["published_at"])
        try db.create(
            index: "entry_unread",
            on: "entry",
            columns: ["received_at"],
            condition: Column("is_read") == false
        )
        try db.create(
            index: "entry_starred",
            on: "entry",
            columns: ["received_at"],
            condition: Column("is_starred") == true
        )

        try db.create(table: "entry_body") { table in
            table.primaryKey("entry_id", .blob).references("entry", onDelete: .cascade)
            table.column("sanitized_html", .text)
            table.column("extracted_html", .text)
            table.column("plain_text", .text)
        }
    }

    /// The library : what the user chose to keep, frozen at the moment of promotion.
    ///
    /// A library item repeats the title, the author and the feed of its article
    /// on purpose. The stream row it came from is purged by age, and the source
    /// itself may disappear ; neither may take the kept copy with it.
    private static func createLibrary(_ db: Database) throws {
        try db.create(table: "library_item") { table in
            table.primaryKey("id", .blob)
            table.column("entry_id", .blob).references("entry", onDelete: .setNull)

            table.column("feed_url", .text)
            table.column("feed_title", .text)
            table.column("guid", .text).notNull().indexed()
            table.column("url", .text)
            table.column("title", .text).notNull()
            table.column("author", .text)
            table.column("language", .text)
            table.column("published_at", .datetime)
            table.column("promoted_at", .datetime).notNull()

            table.column("content_html", .text)
            table.column("plain_text", .text)
            table.column("annotation", .text)

            // A vector only compares to vectors of the same model and revision,
            // so both travel with it and a mismatch means recomputing locally.
            table.column("vector", .blob)
            table.column("vector_model", .text)
            table.column("vector_revision", .text)
        }
    }

    /// Tags, rules and saved queries.
    private static func createOrganization(_ db: Database) throws {
        try db.create(table: "tag") { table in
            table.primaryKey("id", .blob)
            table.column("path", .text).notNull().unique()
            table.column("created_at", .datetime).notNull()
        }

        // A tag applies to an article, a feed or a library item, so the binding
        // carries the kind of what it points at rather than three foreign keys.
        try db.create(table: "tag_binding") { table in
            table.column("tag_id", .blob).notNull().references("tag", onDelete: .cascade)
            table.column("target_kind", .text).notNull()
            table.column("target_id", .blob).notNull()
            table.column("created_at", .datetime).notNull()
            table.primaryKey(["tag_id", "target_kind", "target_id"])
        }

        try db.create(index: "tag_binding_on_target", on: "tag_binding", columns: ["target_kind", "target_id"])

        try db.create(table: "rule") { table in
            table.primaryKey("id", .blob)
            table.column("name", .text).notNull()
            table.column("query", .text).notNull()
            table.column("actions", .jsonText).notNull()
            table.column("position", .integer).notNull()
            table.column("is_enabled", .boolean).notNull().defaults(to: true)
            table.column("created_at", .datetime).notNull()
            table.column("last_run_at", .datetime)
        }

        try db.create(table: "saved_query") { table in
            table.primaryKey("id", .blob)
            table.column("name", .text).notNull().unique()
            table.column("query", .text).notNull()
            table.column("position", .integer).notNull()
            table.column("created_at", .datetime).notNull()
        }
    }

    /// Read states and the synchronization tokens.
    ///
    /// Read states are compacted into one row per feed, per month and per kind.
    /// That is what keeps the CloudKit record count in the three thousand range
    /// instead of one record per article, and merging two of these rows is a
    /// union, so it needs no conflict resolution.
    private static func createSyncState(_ db: Database) throws {
        try db.create(table: "read_state") { table in
            table.primaryKey("id", .blob)
            table.column("feed_id", .blob).notNull().references("feed", onDelete: .cascade)
            table.column("period", .text).notNull()
            table.column("kind", .text).notNull()
            table.column("fingerprints", .blob).notNull()
            table.column("updated_at", .datetime).notNull()
        }

        try db.create(
            index: "read_state_on_feed_period_kind",
            on: "read_state",
            columns: ["feed_id", "period", "kind"],
            options: .unique
        )

        try db.create(table: "sync_state") { table in
            table.primaryKey("key", .text)
            table.column("value", .blob).notNull()
            table.column("updated_at", .datetime).notNull()
        }
    }
}
