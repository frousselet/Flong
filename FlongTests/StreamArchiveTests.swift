//
//  StreamArchiveTests.swift
//  FlongTests
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import Testing

@testable import Flong

/// The archive, against a folder standing in for the iCloud container.
///
/// A temporary directory behaves as the container does in every way this code
/// cares about : files appear in it, they have modification dates, and each
/// device writes in a folder of its own.
@Suite("The stream, as files two devices share")
struct StreamArchiveTests {
    private let now = Date(timeIntervalSince1970: 1_787_646_600)
    private let root: URL

    init() throws {
        root = URL.temporaryDirectory.appending(path: "archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// One device : its own store, and its own name in the shared folder.
    private struct Device {
        let database: AppDatabase
        let subscriptions: SubscriptionStore
        let articles: ArticleStore
        let archive: StreamArchive
        let name: String

        init(named name: String, root: URL) throws {
            let database = try AppDatabase.inMemory()
            self.database = database
            self.subscriptions = SubscriptionStore(database)
            self.articles = ArticleStore(database)
            self.archive = StreamArchive(database, root: root, device: name)
            self.name = name
        }

        @discardableResult
        func add(_ guid: String, to feed: Feed, title: String, at date: Date, body: String? = "<p>Un corps.</p>")
            async throws -> Entry
        {
            var entry = Entry(
                feedID: feed.id,
                guid: guid,
                url: URL(string: "https://example.com/\(guid)"),
                title: title,
                publishedAt: date,
                receivedAt: date
            )
            entry.hasMedia = false
            try await database.writer.write { db in
                try entry.insert(db)
                if let body {
                    try EntryBody(entryID: entry.id, sanitizedHTML: body, plainText: "Un corps.").insert(db)
                }
            }
            return entry
        }

        func follow(_ address: String, title: String = "A") async throws -> Feed {
            try await subscriptions.subscribe(to: Subscription(address: address, title: title)).feed
        }
    }

    private let address = "https://feeds.example.com/f.xml"

    @Test("A day of articles becomes one file, and the other device reads it whole")
    func oneDayOneFile() async throws {
        let first = try Device(named: "phone", root: root)
        let second = try Device(named: "pad", root: root)

        let feed = try await first.follow(address)
        try await first.add("urn:1", to: feed, title: "Première", at: now)
        try await first.add("urn:2", to: feed, title: "Seconde", at: now)
        _ = try await second.follow(address)

        #expect(try await first.archive.write() == 1)
        #expect(try await second.archive.ingest(read: [], at: now) == 2)

        let summaries = try await second.articles.summaries(.all, now: now)
        #expect(summaries.map(\.title).sorted() == ["Première", "Seconde"])
        // Whole, not a title and a link : the body is what makes an article
        // taken from another device readable.
        let newest = try #require(summaries.first)
        let article = try #require(await second.articles.article(id: newest.id))
        #expect(article.bodyHTML == "<p>Un corps.</p>")
    }

    /// An archive holds a fortnight, so the moment an article turns up on the
    /// receiving device decides whether the reader is told about a fortnight of
    /// somebody else's backlog as though it had all just broken.
    @Test("An article taken from another device keeps the moment that device received it")
    func theArrivalMomentTravels() async throws {
        let first = try Device(named: "phone", root: root)
        let second = try Device(named: "pad", root: root)

        let feed = try await first.follow(address)
        let old = now.addingTimeInterval(-9 * 24 * 60 * 60)
        try await first.add("urn:old", to: feed, title: "Ancienne", at: old)
        _ = try await second.follow(address)

        try await first.archive.write()
        // Ingested now, nine days after the first device received it.
        #expect(try await second.archive.ingest(read: [], at: now) == 1)

        let summaries = try await second.articles.summaries(.all, now: now)
        let taken = try #require(summaries.first)
        let stored = try await second.database.writer.read { db in try Entry.fetchOne(db, key: taken.id) }
        let entry = try #require(stored)

        #expect(entry.receivedAt < now.addingTimeInterval(-24 * 60 * 60))
        // And so nothing announces it : a notice asks what arrived since a
        // moment, and this did not arrive now.
        let arrived = try await second.articles.arrived(
            since: now.addingTimeInterval(-60), fromEveryFeed: true)
        #expect(arrived.isEmpty)
    }

    /// The rule that decides a second copy lives in one place, and the archive
    /// path did not ask it : those rows carried no key at all, so they were
    /// exempt from cross-feed duplicate detection for ever.
    @Test("An article taken from another device is keyed like one taken from a publisher")
    func theKeyTravelsToo() async throws {
        let first = try Device(named: "phone", root: root)
        let second = try Device(named: "pad", root: root)

        let feed = try await first.follow(address)
        try await first.add("urn:1", to: feed, title: "Une réforme", at: now)
        _ = try await second.follow(address)

        try await first.archive.write()
        #expect(try await second.archive.ingest(read: [], at: now) == 1)

        let summaries = try await second.articles.summaries(.all, now: now)
        let taken = try #require(summaries.first)
        let stored = try await second.database.writer.read { db in try Entry.fetchOne(db, key: taken.id) }
        #expect(try #require(stored).canonicalKey != nil)
    }

    @Test("A device never reads its own folder back")
    func itsOwnFolderIsNotAnInbox() async throws {
        let first = try Device(named: "phone", root: root)
        let feed = try await first.follow(address)
        try await first.add("urn:1", to: feed, title: "Une", at: now)

        try await first.archive.write()
        // Nothing to take : what it wrote is what it already has, and reading
        // it back would be work for no article.
        #expect(try await first.archive.ingest(read: [], at: now) == 0)
    }

    @Test("Reading twice takes nothing the second time")
    func ingestingIsIdempotent() async throws {
        let first = try Device(named: "phone", root: root)
        let second = try Device(named: "pad", root: root)

        let feed = try await first.follow(address)
        try await first.add("urn:1", to: feed, title: "Une", at: now)
        _ = try await second.follow(address)
        try await first.archive.write()

        #expect(try await second.archive.ingest(read: [], at: now) == 1)
        #expect(try await second.archive.ingest(read: [], at: now) == 0)
        #expect(try await second.articles.count(.all, now: now) == 1)
    }

    @Test("A day that grew is read again, and only its new articles land")
    func aDayThatGrew() async throws {
        let first = try Device(named: "phone", root: root)
        let second = try Device(named: "pad", root: root)

        let feed = try await first.follow(address)
        try await first.add("urn:1", to: feed, title: "Une", at: now)
        _ = try await second.follow(address)
        try await first.archive.write()
        #expect(try await second.archive.ingest(read: [], at: now) == 1)

        // The same day, one article later. The file is rewritten whole, and the
        // reader of it takes only what it does not already hold.
        try await first.add("urn:2", to: feed, title: "Deux", at: now.addingTimeInterval(60))
        try await Task.sleep(for: .milliseconds(1100))
        try await first.archive.write()

        #expect(try await second.archive.ingest(read: [], at: now) == 1)
        #expect(try await second.articles.count(.all, now: now) == 2)
    }

    @Test("A file naming a feed nobody follows is not an invitation to follow it")
    func staysWithinTheSubscriptions() async throws {
        let first = try Device(named: "phone", root: root)
        let second = try Device(named: "pad", root: root)

        let feed = try await first.follow(address)
        try await first.add("urn:1", to: feed, title: "Une", at: now)
        try await first.archive.write()

        // The second device follows nothing.
        #expect(try await second.archive.ingest(read: [], at: now) == 0)
        #expect(try await second.subscriptions.count() == 0)
    }

    @Test("An article read on one device arrives read on the other")
    func readStatesAreHonoured() async throws {
        let first = try Device(named: "phone", root: root)
        let second = try Device(named: "pad", root: root)

        let feed = try await first.follow(address)
        try await first.add("urn:1", to: feed, title: "Une", at: now)
        _ = try await second.follow(address)
        try await first.archive.write()

        let read: Set<ArticleFingerprint> = [ArticleFingerprint(feedURL: feed.url, guid: "urn:1")]
        #expect(try await second.archive.ingest(read: read, at: now) == 1)
        #expect(try await second.articles.summaries(.unread, now: now).isEmpty)
    }

    @Test("With no container there is nothing to do and nothing to fail")
    func withoutICloud() async throws {
        let database = try AppDatabase.inMemory()
        let archive = StreamArchive(database, root: nil, device: "phone")

        #expect(try await archive.write() == 0)
        #expect(try await archive.ingest(read: [], at: now) == 0)
    }
}
