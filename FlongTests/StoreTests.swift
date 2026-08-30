//
//  StoreTests.swift
//  FlongTests
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import Testing

@testable import Flong

@Suite("Store")
struct StoreTests {
    private let feedURL = URL(string: "https://feeds.example.com/atom.xml")!

    private func makeFeed() -> Feed {
        Feed(url: feedURL, title: "Example")
    }

    @Test("The v1 migration creates the whole local data model")
    func migrationCreatesTheModel() throws {
        let database = try AppDatabase.inMemory()

        let tables = try database.writer.read { db in
            try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }

        let expected: Set<String> = [
            "feed", "entry", "entry_body", "tag", "tag_binding",
            "rule", "saved_query", "read_state_block", "sync_state", "sync_record", "entry_fts", "story",
            "story_member", "story_topic", "topic_preference", "topic",
        ]
        #expect(expected.isSubset(of: tables))
    }

    @Test("Migrating twice leaves the schema alone")
    func migrationIsIdempotent() throws {
        let queue = try DatabaseQueue()
        _ = try AppDatabase(queue)
        _ = try AppDatabase(queue)

        let applied = try queue.read { db in try AppDatabase.migrator.appliedIdentifiers(db) }
        #expect(
            applied == [
                "v1.model", "v2.search", "v3.readStates", "v4.stories", "v5.covers", "v6.topics",
                "v7.briefLanguage", "v8.recordTags", "v9.askAgain", "v10.topicPreferences",
                "v11.severalTopics", "v12.duplicates", "v13.keyWhatIsAlreadyHere", "v14.vocabulary",
                "v15.askedOnce", "v16.whyItWasKept", "v17.archiveLedger", "v18.oneArticle",
                "v19.marksThatArriveFirst", "v20.secureThePictures",
            ]
        )
    }

    @Test("The migration that folded the library in carries the marks onto the articles")
    func marksAreCarriedOver() throws {
        let queue = try DatabaseQueue()
        // The schema as it stood before the star was written on the copy.
        try AppDatabase.migrator.migrate(queue, upTo: "v15.askedOnce")

        let feed = UUID.v7()
        let starred = UUID.v7()
        let plain = UUID.v7()
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO feed (id, url, title, folder, created_at) VALUES (?, ?, ?, NULL, ?)",
                arguments: [feed, "https://a.example.com/f.xml", "A", Date()]
            )
            for (id, isStarred) in [(starred, true), (plain, false)] {
                try db.execute(
                    sql: """
                        INSERT INTO entry (id, feed_id, guid, title, received_at, is_starred)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [id, feed, "urn:\(id)", "Title", Date(), isStarred]
                )
                try db.execute(
                    sql: """
                        INSERT INTO library_item (id, entry_id, guid, title, promoted_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [UUID.v7(), id, "urn:\(id)", "Title", Date()]
                )
            }
        }

        try AppDatabase.migrator.migrate(queue)

        // A reader who starred things before the update finds them in their
        // favourites afterwards. The star was written on the copy by v16 and
        // is written back onto the article by v18, and neither step may lose
        // it : it is the one thing in the library nothing else recorded.
        let carried = try queue.read { db in
            try UUID.fetchAll(db, sql: "SELECT id FROM entry WHERE is_starred = 1")
        }
        #expect(carried == [starred])

        // And the second store is gone rather than left behind to drift.
        let tables = try queue.read { db in
            try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        #expect(!tables.contains("library_item"))
    }

    @Test("An article kept after its stream row was purged comes back as an article")
    func theOrphansAreRebuilt() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v15.askedOnce")

        let feed = UUID.v7()
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO feed (id, url, title, folder, created_at) VALUES (?, ?, ?, NULL, ?)",
                arguments: [feed, "https://a.example.com/f.xml", "A", Date()]
            )
            // A copy whose article was purged long ago : exactly what the
            // library existed to protect, and exactly what a careless removal
            // would have thrown away on the one day it was taken out.
            try db.execute(
                sql: """
                    INSERT INTO library_item
                    (id, entry_id, feed_url, feed_title, guid, title, promoted_at, content_html, plain_text)
                    VALUES (?, NULL, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    UUID.v7(), "https://a.example.com/f.xml", "A", "urn:orphelin",
                    "Un article gardé", Date(), "<p>Le corps.</p>", "Le corps.",
                ]
            )
        }

        try AppDatabase.migrator.migrate(queue)

        let rebuilt = try queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.title AS title, b.sanitized_html AS html
                    FROM entry e LEFT JOIN entry_body b ON b.entry_id = e.id
                    WHERE e.guid = 'urn:orphelin'
                    """
            )
        }
        #expect(rebuilt.count == 1)
        #expect(rebuilt.first?["title"] as String? == "Un article gardé")
        #expect(rebuilt.first?["html"] as String? == "<p>Le corps.</p>")
    }

    @Test("A feed, an article and its body round trip with every column filled")
    func recordsRoundTrip() throws {
        let database = try AppDatabase.inMemory()
        let date = Date(timeIntervalSince1970: 1_756_000_000)

        // Every property is filled on purpose : a column named wrong reads back
        // as nil, so only a complete fixture can catch it.
        let feed = Feed(
            url: feedURL,
            siteURL: URL(string: "https://example.com"),
            iconURL: URL(string: "https://example.com/icon.png"),
            title: "Example",
            folder: "veille/ios",
            language: "en",
            etag: "\"686897696a7c876b7e\"",
            lastModified: "Fri, 29 Aug 2026 10:00:00 GMT",
            fetchCount: 12,
            notModifiedCount: 9,
            failureCount: 1,
            lastFailureReason: "timeout",
            lastFetchAt: date,
            lastSuccessAt: date.addingTimeInterval(-60),
            quarantinedAt: date.addingTimeInterval(-120),
            observedInterval: 3600,
            refreshInterval: 900,
            readerModeEnabled: true,
            loadsImages: false,
            createdAt: date.addingTimeInterval(-86400)
        )
        let entry = Entry(
            feedID: feed.id,
            guid: "urn:example:1",
            url: URL(string: "https://example.com/1"),
            title: "First",
            excerpt: "A summary",
            author: "A. Author",
            language: "en",
            publishedAt: date,
            updatedAt: date.addingTimeInterval(60),
            receivedAt: date.addingTimeInterval(120),
            isRead: true,
            readAt: date.addingTimeInterval(180),
            isStarred: true,
            isHidden: true,
            enclosures: [Enclosure(url: URL(string: "https://example.com/1.mp3")!, type: "audio/mpeg", length: 42)],
            imageURL: URL(string: "https://example.com/1.jpg"),
            canonicalKey: "example.com/1"
        )
        let body = EntryBody(
            entryID: entry.id,
            sanitizedHTML: "<p>Hello</p>",
            extractedHTML: "<article><p>Hello</p></article>",
            plainText: "Hello"
        )

        try database.writer.write { db in
            try feed.insert(db)
            try entry.insert(db)
            try body.insert(db)
        }

        let read = try database.writer.read { db in
            (
                feed: try Feed.fetchOne(db, key: feed.id),
                entry: try Entry.fetchOne(db, key: entry.id),
                body: try EntryBody.fetchOne(db, key: body.entryID)
            )
        }

        #expect(read.feed == feed)
        #expect(read.entry == entry)
        #expect(read.body == body)
        #expect(read.entry?.hasMedia == true)
        #expect(read.entry?.imageURL?.absoluteString == "https://example.com/1.jpg")
        #expect(read.entry?.canonicalKey == "example.com/1")
        #expect(read.feed?.notModifiedRate == 0.75)
    }

    @Test("One feed cannot hold the same article twice")
    func guidIsUniquePerFeed() throws {
        let database = try AppDatabase.inMemory()
        let feed = makeFeed()

        try database.writer.write { db in
            try feed.insert(db)
            try Entry(feedID: feed.id, guid: "urn:example:1", title: "First").insert(db)
        }

        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in
                try Entry(feedID: feed.id, guid: "urn:example:1", title: "First again").insert(db)
            }
        }
    }

    @Test("An article cannot point at a feed that does not exist")
    func foreignKeysAreEnforced() throws {
        let database = try AppDatabase.inMemory()

        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in
                try Entry(feedID: .v7(), guid: "urn:example:1", title: "Orphan").insert(db)
            }
        }
    }

    @Test("Deleting a feed takes its articles and their bodies with it")
    func deletingAFeedCascades() throws {
        let database = try AppDatabase.inMemory()
        let feed = makeFeed()
        let entry = Entry(feedID: feed.id, guid: "urn:example:1", title: "First")

        try database.writer.write { db in
            try feed.insert(db)
            try entry.insert(db)
            try EntryBody(entryID: entry.id, plainText: "Hello").insert(db)
            _ = try feed.delete(db)
        }

        let counts = try database.writer.read { db in
            (entries: try Entry.fetchCount(db), bodies: try EntryBody.fetchCount(db))
        }
        #expect(counts.entries == 0)
        #expect(counts.bodies == 0)
    }

    @Test("A database on disk is created, migrated and reopened")
    func onDiskDatabase() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let feed = makeFeed()
        do {
            let database = try AppDatabase.onDisk(folder: folder)
            try database.writer.write { db in try feed.insert(db) }
        }

        let file = folder.appendingPathComponent("flong.sqlite")
        #expect(FileManager.default.fileExists(atPath: file.path))

        // The simulator does not implement data protection and reports no class
        // at all, so the check only bites on a device.
        #if os(iOS)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            if let protection = attributes[.protectionKey] as? FileProtectionType {
                #expect(protection == .completeUntilFirstUserAuthentication)
            }
        #endif

        // Reopening runs the migrator again over a schema that is already there.
        let reopened = try AppDatabase.onDisk(folder: folder)
        let titles = try reopened.writer.read { db in try Feed.fetchAll(db).map(\.title) }
        #expect(titles == [feed.title])
    }

    @Test("Identifiers sort by creation time inside SQLite")
    func identifiersSortByCreationTime() throws {
        let database = try AppDatabase.inMemory()
        let feed = makeFeed()
        let start = Date(timeIntervalSince1970: 1_756_000_000)
        let ids = (0..<20).map { UUID.v7(at: start.addingTimeInterval(Double($0))) }

        try database.writer.write { db in
            try feed.insert(db)
            for (offset, id) in ids.enumerated() {
                try Entry(id: id, feedID: feed.id, guid: "urn:example:\(offset)", title: "Article").insert(db)
            }
        }

        let sorted = try database.writer.read { db in
            try UUID.fetchAll(db, sql: "SELECT id FROM entry ORDER BY id")
        }
        #expect(sorted == ids)
    }
}
