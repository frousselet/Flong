//
//  ErasureTests.swift
//  FlongTests
//
//  Created by François Rousselet on 31/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import Testing

@testable import Flong

/// Starting over : what a reader means by everything, and what is left after.
///
/// The one command in the application that takes something away for good, so
/// the two things worth proving are that nothing survives it and that what
/// survives it is a working application rather than a broken one.
@Suite("Deleting everything")
struct ErasureTests {
    private func seeded(_ database: AppDatabase) async throws -> Feed {
        let feed = try await SubscriptionStore(database)
            .subscribe(to: Subscription(address: "https://feeds.example.com/atom.xml", title: "Example"))
            .feed

        var entry = Entry(
            feedID: feed.id,
            guid: "urn:example:one",
            url: URL(string: "https://feeds.example.com/one"),
            title: "One",
            excerpt: "About one",
            publishedAt: Date()
        )
        entry.hasMedia = false

        try await database.writer.write { db in
            try entry.insert(db)
            try EntryBody(entryID: entry.id, sanitizedHTML: "<p>One</p>").insert(db)
            // The machinery's own memory of iCloud, which has to go with the
            // rest or the next exchange is answered from a token for a zone
            // that no longer exists.
            try db.execute(
                sql: "INSERT INTO sync_state (key, value, updated_at) VALUES ('engine', ?, ?)",
                arguments: [Data("a change token".utf8), Date()]
            )
        }
        return feed
    }

    @Test("The store comes back empty, with its schema and nothing in it")
    func store() async throws {
        let database = try AppDatabase.inMemory()
        try await seeded(database)

        try await database.eraseEverything()

        let counts = try await database.writer.read { db in
            [
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed") ?? -1,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry") ?? -1,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_body") ?? -1,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_state") ?? -1,
            ]
        }
        #expect(counts == [0, 0, 0, 0])

        // The schema is back, migrations and all : nothing that runs afterwards
        // has to know a reset happened.
        let applied = try await database.writer.read { db in try AppDatabase.migrator.appliedIdentifiers(db) }
        #expect(applied == Set(AppDatabase.migrator.migrations))

        // And it is a database that can be written to again, which is the only
        // proof that matters.
        try await seeded(database)
        let feeds = try await database.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed") }
        #expect(feeds == 1)
    }

    @Test("Every choice the reader made is forgotten, in both stores")
    func preferences() {
        let defaults = UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        let store = Preferences(cloud: nil, local: defaults)

        store.firstName = "Ada"
        store.lastName = "Lovelace"
        store.articleBody = .page
        store.wantsNewStoryNotices = true
        store.storiesAnnouncedAt = Date()
        let device = store.device

        store.forgetEverything()

        #expect(store.firstName.isEmpty)
        #expect(store.lastName.isEmpty)
        #expect(store.picture == nil)
        #expect(store.articleBody == .feed)
        #expect(!store.wantsNewStoryNotices)
        #expect(store.storiesAnnouncedAt == nil)
        // The identifier goes too, and the next one asked for is a new one.
        #expect(store.device != device)
    }

    @Test("The keychain keeps nothing back")
    func keychain() throws {
        let credentials = MemoryCredentials()
        try credentials.setCredential(FeedCredential.basic(user: "reader", password: "hunter2"), for: UUID.v7())
        try credentials.setCredential(FeedCredential.basic(user: "reader", password: "hunter2"), for: UUID.v7())

        let sessions = MemorySessions()
        try sessions.setSession(
            SiteSession(
                host: "lemonde.fr",
                cookies: [SessionCookie(named: "session", value: "opaque", domain: "lemonde.fr")]
            ),
            for: "lemonde.fr"
        )

        try credentials.removeEverything()
        try sessions.removeEverything()

        #expect(try credentials.identifiers().isEmpty)
        #expect(try sessions.hosts().isEmpty)
    }
}

/// The window's own end of it.
@Suite("The window, after everything was deleted", .serialized)
@MainActor
struct ErasedWindowTests {
    private let database: AppDatabase
    private let credentials = MemoryCredentials()
    private let sessions = MemorySessions()
    private let preferences: Preferences
    private let model: AppModel
    private let server = StubServer(host: "feeds.example.com")

    init() throws {
        database = try AppDatabase.inMemory()
        preferences = Preferences(
            cloud: nil,
            local: UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        )
        // Wired to a stub : the clock starts again at the end of a reset, and a
        // suite is not a reason to knock on a real publisher's door.
        server.install { _ in StubResponse(statusCode: 304) }
        model = AppModel(
            database: database,
            fetcher: FeedFetcher(
                session: server.makeSession(),
                throttle: HostThrottle(interval: 0, burst: 100),
                userAgent: "Flong/test"
            ),
            credentials: credentials,
            sessions: sessions,
            preferences: preferences,
            announcer: MemoryAnnouncer()
        )
    }

    @Test("Nothing the reader had is left, and the window is one that works")
    func everything() async throws {
        let feed = try await SubscriptionStore(database)
            .subscribe(to: Subscription(address: "https://feeds.example.com/atom.xml", title: "Example"))
            .feed
        var entry = Entry(
            feedID: feed.id,
            guid: "urn:example:one",
            url: URL(string: "https://feeds.example.com/one"),
            title: "One",
            excerpt: "About one",
            publishedAt: Date()
        )
        entry.hasMedia = false
        try await database.writer.write { db in try entry.insert(db) }

        try credentials.setCredential(FeedCredential.basic(user: "reader", password: "hunter2"), for: feed.id)
        try sessions.setSession(
            SiteSession(
                host: "lemonde.fr",
                cookies: [SessionCookie(named: "session", value: "opaque", domain: "lemonde.fr")]
            ),
            for: "lemonde.fr"
        )

        model.firstName = "Ada"
        model.lastName = "Lovelace"
        await model.makeCollection(named: "Read later")
        await model.load()
        await model.loadSubscribedSites()

        #expect(!model.isEmpty)
        #expect(!model.summaries.isEmpty)
        #expect(!model.subscribedSites.isEmpty)

        await model.deleteEverything()

        // What the reader collected.
        #expect(model.isEmpty)
        #expect(model.feedCount == 0)
        #expect(model.summaries.isEmpty)
        #expect(model.sourceGroups.isEmpty)
        #expect(model.collections.allSatisfy { $0.kind != .made("Read later") })

        // What they were signed in to, and what they typed about themselves.
        #expect(model.subscribedSites.isEmpty)
        #expect(model.authenticatedFeeds.isEmpty)
        #expect(try credentials.identifiers().isEmpty)
        #expect(try sessions.hosts().isEmpty)
        #expect(model.name == nil)
        #expect(model.picture == nil)
        #expect(preferences.firstName.isEmpty)

        // Where they were, which is where a first launch puts them.
        #expect(model.selection == .all)
        #expect(model.selectedArticle == nil)
        #expect(model.article == nil)
        #expect(model.searchText.isEmpty)
        #expect(model.failure == nil)

        // And an application that still works : a subscription made after the
        // reset lands exactly as one made before it, which is the half a reset
        // that only emptied tables would get wrong.
        try await SubscriptionStore(database)
            .subscribe(to: Subscription(address: "https://feeds.example.com/second.xml", title: "Second"))
        await model.load()
        #expect(!model.isEmpty)
        #expect(model.sourceGroups.map(\.title) == ["feeds.example.com"])
    }
}
