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

        migrator.registerMigration("v2.search") { db in
            try createSearchIndex(db)
        }

        migrator.registerMigration("v3.readStates") { db in
            try createReadStateBlocks(db)
        }

        migrator.registerMigration("v4.stories") { db in
            try createStories(db)
        }

        migrator.registerMigration("v5.covers") { db in
            try addCovers(db)
        }

        migrator.registerMigration("v6.topics") { db in
            try addTopics(db)
        }

        migrator.registerMigration("v7.briefLanguage") { db in
            try addBriefLanguage(db)
        }

        migrator.registerMigration("v8.recordTags") { db in
            try createRecordTags(db)
        }

        migrator.registerMigration("v9.askAgain") { db in
            try askAgain(db)
        }

        migrator.registerMigration("v10.topicPreferences") { db in
            try createTopicPreferences(db)
        }

        migrator.registerMigration("v11.severalTopics") { db in
            try createStoryTopics(db)
        }

        migrator.registerMigration("v12.duplicates") { db in
            try addDuplicates(db)
        }

        migrator.registerMigration("v13.keyWhatIsAlreadyHere") { db in
            try keyExistingArticles(db)
        }

        return migrator
    }

    /// The same article, arriving twice.
    ///
    /// A paper that publishes a feed per desk puts the same piece in several
    /// of them, and a reader following two desks read it twice. The second
    /// copy keeps its row, because it belongs to a feed the reader follows and
    /// unsubscribing from that feed must take it away, but it points at the
    /// first and is shown nowhere.
    ///
    /// `ON DELETE SET NULL` : when the first copy is purged by age, the second
    /// stops being a duplicate of anything and becomes the article.
    private static func addDuplicates(_ db: Database) throws {
        try db.alter(table: "entry") { table in
            table.add(column: "canonical_key", .text)
            table.add(column: "duplicate_of", .blob).references("entry", onDelete: .setNull)
        }
        try db.create(index: "entry_on_canonical_key", on: "entry", columns: ["canonical_key"])
    }

    /// Keys the articles that were already here, and marks the copies.
    ///
    /// The column arrived empty and only new articles were keyed, so a reader
    /// who had been running Flong for a week kept every copy they already had
    /// : the fault they would report, and did.
    ///
    /// One pass over the stream. It costs a second on a large one, once, which
    /// is cheaper than the machinery of a resumable job for something that
    /// never runs again.
    static func keyExistingArticles(_ db: Database) throws {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT e.id AS id, e.url AS url, e.title AS title, e.published_at AS published_at,
                       COALESCE(f.site_url, f.url) AS site_url
                FROM entry e JOIN feed f ON f.id = e.feed_id
                WHERE e.canonical_key IS NULL
                """
        )

        for row in rows {
            let key = ArticleKey.of(
                url: (row["url"] as String?).flatMap(URL.init(string:)),
                title: row["title"] as String? ?? "",
                publishedAt: row["published_at"] as Date?,
                room: FeedURL.room(of: (row["site_url"] as String?).flatMap(URL.init(string:)))
            )
            guard let key else { continue }
            try db.execute(
                sql: "UPDATE entry SET canonical_key = ? WHERE id = ?",
                arguments: [key, row["id"] as UUID]
            )
        }

        // The earliest copy of each key is the article ; the rest point at it.
        try db.execute(
            sql: """
                UPDATE entry AS e
                SET duplicate_of = (
                    SELECT o.id FROM entry o
                    WHERE o.canonical_key = e.canonical_key
                    ORDER BY o.received_at, o.id LIMIT 1
                )
                WHERE e.canonical_key IS NOT NULL
                  AND e.id <> (
                    SELECT o.id FROM entry o
                    WHERE o.canonical_key = e.canonical_key
                    ORDER BY o.received_at, o.id LIMIT 1
                  )
                """
        )
    }

    /// The subjects a story falls under, which are more than one.
    ///
    /// A column held exactly one, which is not how a page reads : a security
    /// advisory about a stolen database is under both computer security and
    /// cybercrime, and a reader who asked for more of either means this one.
    ///
    /// What the single column held is carried over rather than thrown away,
    /// so a page already sorted stays sorted until the next rebuild.
    private static func createStoryTopics(_ db: Database) throws {
        try db.create(table: "story_topic") { table in
            table.column("story_id", .blob).notNull().references("story", onDelete: .cascade)
            table.column("name", .text).notNull()
            table.primaryKey(["story_id", "name"])
        }
        try db.create(index: "story_topic_on_name", on: "story_topic", columns: ["name"])

        try db.execute(
            sql: """
                INSERT OR IGNORE INTO story_topic (story_id, name)
                SELECT id, topic FROM story WHERE topic IS NOT NULL
                """
        )
        // The index of the single column goes with the column it indexes, or
        // SQLite refuses the drop and leaves the schema half changed.
        try db.execute(sql: "DROP INDEX IF EXISTS story_on_topic")
        try db.alter(table: "story") { table in
            table.drop(column: "topic")
        }
    }

    /// What the reader wants more or less of.
    ///
    /// Keyed by the name of the subject, since a subject has nothing else to
    /// be known by : it is written afresh by the model on each rebuild, and
    /// the reader pressed on a word rather than on a row of a table.
    ///
    /// Nought is the absence of an opinion and is never stored, so the table
    /// holds one row per subject the reader has actually spoken about.
    private static func createTopicPreferences(_ db: Database) throws {
        try db.create(table: "topic_preference") { table in
            table.primaryKey("name", .text)
            table.column("score", .integer).notNull()
            table.column("updated_at", .datetime).notNull()
        }
    }

    /// Asks the model about every story once more.
    ///
    /// A build in between wrote briefs in the language of the articles and
    /// stamped them with the language of the reader, so they read as answered
    /// and nothing would ever have asked again : a page of English headlines
    /// for a French reader, permanently. Forgetting what was asked costs one
    /// question per story, once.
    private static func askAgain(_ db: Database) throws {
        try db.execute(sql: "UPDATE story SET brief_locale = NULL")
    }

    /// What the server last said about each record it holds.
    ///
    /// CloudKit refuses a record that carries no change tag when it already
    /// has one under that name : `record to insert already exists`. A record
    /// built from the store alone carries none, so every second save of
    /// anything was refused, for ever. The tag travels inside the system
    /// fields of the record the server hands back, which is what is kept here.
    ///
    /// It is a cache : losing it costs one refused save per record, after
    /// which the server hands the record back and the tag is learned again.
    private static func createRecordTags(_ db: Database) throws {
        try db.create(table: "sync_record") { table in
            table.primaryKey("record_name", .text)
            table.column("system_fields", .blob).notNull()
            table.column("updated_at", .datetime).notNull()
        }
    }

    /// The language a brief was written in.
    ///
    /// A brief is written in the reader's language, and a reader who changes it
    /// would otherwise keep yesterday's for ever : nothing else about the story
    /// has changed, so nothing else would ask for it to be written again.
    private static func addBriefLanguage(_ db: Database) throws {
        try db.alter(table: "story") { table in
            table.add(column: "brief_locale", .text)
        }
    }

    /// The subject a story falls under, when the model found one.
    ///
    /// A column on the story rather than a table of its own : a story is under
    /// exactly one subject, subjects are derived data that is never
    /// synchronized, and the whole set is rewritten every time the page is
    /// rebuilt. A table would be three joins to say what a string says.
    private static func addTopics(_ db: Database) throws {
        try db.alter(table: "story") { table in
            table.add(column: "topic", .text)
        }
        try db.create(index: "story_on_topic", on: "story", columns: ["topic"])
    }

    /// The picture that stands for an article.
    ///
    /// An address, never the file : the bytes belong to the publisher and are
    /// asked for only when a screen shows them. It travels to the library with
    /// the rest, so a kept article still has its illustration once the stream
    /// row it came from has been purged.
    private static func addCovers(_ db: Database) throws {
        try db.alter(table: "entry") { table in
            table.add(column: "image_url", .text)
        }
        try db.alter(table: "library_item") { table in
            table.add(column: "image_url", .text)
        }
    }

    /// The stories of the digest.
    ///
    /// A story is a group of articles about one event, and its signature is the
    /// vocabulary its articles share. Section 11 proposed vectorizing a recent
    /// window of the stream for this ; measurement said otherwise, and
    /// `TextSignature` says why.
    ///
    /// Stories are derived data. They are never synchronized, any more than the
    /// full-text index is : another device holds the same articles and works out
    /// the same stories, and sending them would cost records to say what the
    /// other end already knows.
    private static func createStories(_ db: Database) throws {
        try db.create(table: "story") { table in
            table.primaryKey("id", .blob)
            table.column("title", .text).notNull()
            table.column("summary", .text)
            // Section 14 : anything produced automatically says so, in the
            // interface and in exports.
            table.column("is_generated", .boolean).notNull().defaults(to: false)
            // Set when the reader has said they would rather have the article's
            // own headline, so the model does not write over their choice.
            table.column("brief_locked", .boolean).notNull().defaults(to: false)

            // The vocabulary the story's articles share, as terms and weights.
            table.column("signature", .jsonText)

            table.column("article_count", .integer).notNull().defaults(to: 0)
            table.column("feed_count", .integer).notNull().defaults(to: 0)
            table.column("first_at", .datetime).notNull()
            table.column("last_at", .datetime).notNull()
            table.column("updated_at", .datetime).notNull()
        }

        try db.create(index: "story_on_last_at", on: "story", columns: ["last_at"])

        try db.create(table: "story_member") { table in
            table.column("story_id", .blob).notNull().references("story", onDelete: .cascade)
            table.column("entry_id", .blob).notNull().references("entry", onDelete: .cascade)
            table.column("similarity", .double).notNull()
            table.primaryKey(["story_id", "entry_id"])
        }

        // An article belongs to one story at most : two would mean showing the
        // same article twice in a digest that exists to show less.
        try db.create(index: "story_member_on_entry", on: "story_member", columns: ["entry_id"], options: .unique)
    }

    /// The read states, as one row per period rather than one per article.
    ///
    /// `read_state` of v1 was written for one row per feed and per month, and
    /// was never used. One row per month, over every feed, is what actually
    /// meets the record budget of section 7 : three years of reading is a few
    /// dozen records instead of several thousand. It is replaced rather than
    /// altered, nothing having ever been stored in it.
    private static func createReadStateBlocks(_ db: Database) throws {
        try db.create(table: "read_state_block") { table in
            // The month the articles were published in, which every device
            // works out alike, or `undated`.
            table.column("period", .text).notNull()
            table.column("kind", .text).notNull()
            // The compressed set of fingerprints.
            table.column("fingerprints", .blob).notNull()
            table.column("updated_at", .datetime).notNull()
            table.primaryKey(["period", "kind"])
        }

        try db.drop(table: "read_state")
    }

    /// The full-text index of the stream, and the triggers that keep it in step.
    ///
    /// The table is **contentless** rather than external content : it holds an
    /// index and not a second copy of the articles, which is what section 11 of
    /// the specification is after, and `contentless_delete` lets a row go on its
    /// identifier alone. External content would demand the exact original text
    /// back on every delete, and a cascade that has already removed the body has
    /// nothing to give back. That is how a full-text index quietly corrupts
    /// itself.
    ///
    /// `porter` wraps `unicode61`, so `reforme` finds `réforme` and `calendrier`
    /// finds `calendriers`. The stemmer is English, the only one SQLite ships :
    /// close enough on French suffixes to be worth having, and a per-language
    /// index is what doing better would take.
    private static func createSearchIndex(_ db: Database) throws {
        try db.execute(
            sql: """
                CREATE VIRTUAL TABLE entry_fts USING fts5(
                    title, excerpt, body, author,
                    content='', contentless_delete=1,
                    tokenize='porter unicode61 remove_diacritics 2',
                    prefix='2 3'
                )
                """
        )

        // What is already in the store, indexed once.
        try db.execute(sql: "\(indexInsert) \(indexSelect) WHERE 1")

        try db.execute(
            sql: """
                CREATE TRIGGER entry_fts_after_insert AFTER INSERT ON entry BEGIN
                    \(indexInsert) \(indexSelect) WHERE e.id = new.id;
                END
                """
        )
        try db.execute(
            sql: """
                CREATE TRIGGER entry_fts_after_update AFTER UPDATE OF title, excerpt, author ON entry BEGIN
                    DELETE FROM entry_fts WHERE rowid = old.rowid;
                    \(indexInsert) \(indexSelect) WHERE e.id = new.id;
                END
                """
        )
        try db.execute(
            sql: """
                CREATE TRIGGER entry_fts_after_delete AFTER DELETE ON entry BEGIN
                    DELETE FROM entry_fts WHERE rowid = old.rowid;
                END
                """
        )

        // The body arrives after its article and changes on its own, so it
        // reindexes the whole row rather than one column of it.
        for (name, event, row) in [
            ("entry_body_fts_after_insert", "AFTER INSERT ON entry_body", "new"),
            ("entry_body_fts_after_update", "AFTER UPDATE OF plain_text ON entry_body", "new"),
            ("entry_body_fts_after_delete", "AFTER DELETE ON entry_body", "old"),
        ] {
            try db.execute(
                sql: """
                    CREATE TRIGGER \(name) \(event) BEGIN
                        DELETE FROM entry_fts WHERE rowid = (SELECT rowid FROM entry WHERE id = \(row).entry_id);
                        \(indexInsert) \(indexSelect) WHERE e.id = \(row).entry_id;
                    END
                    """
            )
        }
    }

    /// The one shape every write to the index takes.
    ///
    /// Trigger and rebuild share it, so the index can never end up holding
    /// different columns depending on which of them wrote the row.
    static let indexInsert = "INSERT INTO entry_fts(rowid, title, excerpt, body, author)"
    static let indexSelect = """
        SELECT e.rowid, e.title, e.excerpt, b.plain_text, e.author
        FROM entry e LEFT JOIN entry_body b ON b.entry_id = e.id
        """

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
