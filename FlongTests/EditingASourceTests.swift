//
//  EditingASourceTests.swift
//  FlongTests
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import Testing

@testable import Flong

/// The window's end of editing one source : the keychain, and the parameters
/// the reader is asked about.
///
/// The store's end is in `SubscriptionStoreTests`. What is here is what only
/// the window can answer for : whether an address is a secret is a fact about
/// the address, and moving between the two moves the row and the keychain
/// together.
@Suite("Editing a source", .serialized)
@MainActor
struct EditingASourceTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let credentials = MemoryCredentials()
    private let model: AppModel
    private let server = StubServer(host: "feeds.example.com")

    init() throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
        // A source that moves is fetched at once, and a suite is not a reason
        // to knock on a real publisher's door.
        server.install { _ in StubResponse(statusCode: 304) }
        model = AppModel(
            database: database,
            fetcher: FeedFetcher(
                session: server.makeSession(),
                throttle: HostThrottle(interval: 0, burst: 100),
                userAgent: "Flong/test"
            ),
            credentials: credentials,
            sessions: MemorySessions(),
            announcer: MemoryAnnouncer()
        )
    }

    @discardableResult
    private func follow(_ address: String, title: String = "Example") async throws -> Feed {
        try await subscriptions.subscribe(to: Subscription(address: address, title: title)).feed
    }

    private func stored(_ id: UUID) async throws -> Feed {
        try #require(try await subscriptions.feed(id: id))
    }

    // MARK: - Making a source secret, and open again

    @Test("A source made secret is masked, and its address goes to the keychain")
    func makingASourceSecret() async throws {
        let address = "https://feeds.example.com/rss?token=abcdefghijkl"
        let feed = try await follow(address)
        try await database.writer.write { db in
            try Entry(feedID: feed.id, guid: "urn:example:one", title: "One", isStarred: true).insert(db)
        }

        await model.editSource(feed.id, to: SourceEdit(title: "Example"), address: .secret(address))

        #expect(model.failure == nil)
        let now = try await stored(feed.id)
        #expect(MaskedURL.isMasked(now.url))
        #expect(now.previousURL?.absoluteString == address)
        #expect(try credentials.credential(for: feed.id) == .secretURL(#require(URL(string: address))))
        // The whole point : the articles and the stars on them do not move.
        let remaining = try await database.writer.read { db in try Entry.fetchCount(db) }
        #expect(remaining == 1)
    }

    @Test("A source made open again is written back in the open, and the keychain is emptied")
    func makingASourceOpen() async throws {
        let address = "https://feeds.example.com/rss?token=abcdefghijkl"
        let feed = try await follow(address)
        await model.editSource(feed.id, to: SourceEdit(title: "Example"), address: .secret(address))

        await model.editSource(feed.id, to: SourceEdit(title: "Example"), address: .open(""))

        #expect(model.failure == nil)
        let now = try await stored(feed.id)
        #expect(!MaskedURL.isMasked(now.url))
        #expect(now.url.absoluteString == address)
        #expect(try credentials.credential(for: feed.id) == nil)
    }

    @Test("A source made open with no address anywhere is refused rather than broken")
    func makingASourceOpenWithNothingToWrite() async throws {
        let feed = try await follow("https://feeds.example.com/rss?token=abcdefghijkl")
        await model.editSource(
            feed.id,
            to: SourceEdit(title: "Example"),
            address: .secret("https://feeds.example.com/rss?token=abcdefghijkl")
        )
        try credentials.setCredential(nil, for: feed.id)

        await model.editSource(feed.id, to: SourceEdit(title: "Example"), address: .open(""))

        #expect(model.failure == .noAddress)
        let now = try await stored(feed.id)
        #expect(MaskedURL.isMasked(now.url))
    }

    @Test("A new secret address replaces the one in the keychain and moves the source")
    func replacingASecretAddress() async throws {
        let feed = try await follow("https://feeds.example.com/rss?token=first")
        await model.editSource(
            feed.id,
            to: SourceEdit(title: "Example"),
            address: .secret("https://feeds.example.com/rss?token=first")
        )
        let masked = try await stored(feed.id).url

        await model.editSource(
            feed.id,
            to: SourceEdit(title: "Example"),
            address: .secret("https://feeds.example.com/rss?token=second")
        )

        let now = try await stored(feed.id)
        #expect(MaskedURL.isMasked(now.url))
        #expect(now.url != masked)
        #expect(
            try credentials.credential(for: feed.id)
                == .secretURL(#require(URL(string: "https://feeds.example.com/rss?token=second")))
        )
    }

    @Test("Changing something else on a secret source leaves the secret alone")
    func editingAroundASecret() async throws {
        let address = "https://feeds.example.com/rss?token=abcdefghijkl"
        let feed = try await follow(address)
        await model.editSource(feed.id, to: SourceEdit(title: "Example"), address: .secret(address))
        let masked = try await stored(feed.id).url

        await model.editSource(
            feed.id,
            to: SourceEdit(title: "My own name", isFavourite: true),
            address: .secret("")
        )

        let now = try await stored(feed.id)
        #expect(now.url == masked)
        #expect(now.title == "My own name")
        #expect(now.isFavourite)
        #expect(try credentials.credential(for: feed.id) == .secretURL(#require(URL(string: address))))
    }

    @Test("An address another source is already served at is refused")
    func refusingAnAddressAlreadyFollowed() async throws {
        let first = try await follow("https://feeds.example.com/1.xml")
        try await follow("https://feeds.example.com/2.xml")

        await model.editSource(
            first.id,
            to: SourceEdit(title: "Example"),
            address: .open("https://feeds.example.com/2.xml")
        )

        #expect(model.failure == .addressAlreadyFollowed)
        let now = try await stored(first.id)
        #expect(now.url == first.url)
    }

    // MARK: - The parameters of an address

    @Test("The parameters offered are the ones the feed and its articles carry")
    func addressParameters() async throws {
        let feed = try await follow("https://feeds.example.com/rss?format=atom&token=abcdefghijkl")
        var entry = Entry(
            feedID: feed.id,
            guid: "urn:example:one",
            url: URL(string: "https://feeds.example.com/one?key=secretsecret&page=2"),
            title: "One"
        )
        entry.hasMedia = false
        try await database.writer.write { db in try entry.insert(db) }

        let found = await model.addressParameters(of: feed.id, feedURL: feed.url)

        #expect(found.map(\.name) == ["format", "token", "key", "page"])
        // Enough of each value to recognize it, and never enough to use it.
        #expect(found.first(where: { $0.name == "token" })?.masked == "ab••••••••••")
        #expect(found.first(where: { $0.name == "format" })?.masked == "••••")
    }

    @Test("The parameters of a secret address are read back from the keychain")
    func addressParametersOfASecretSource() async throws {
        let address = "https://feeds.example.com/rss?token=abcdefghijkl"
        let feed = try await follow(address)
        var entry = Entry(
            feedID: feed.id,
            guid: "urn:example:one",
            url: URL(string: "https://feeds.example.com/one?key=secretsecret"),
            title: "One"
        )
        entry.hasMedia = false
        try await database.writer.write { db in try entry.insert(db) }

        await model.editSource(feed.id, to: SourceEdit(title: "Example"), address: .secret(address))
        let masked = try await stored(feed.id)
        let found = await model.addressParameters(of: feed.id, feedURL: masked.url)

        // The row holds a digest and nothing a reader would recognize, so the
        // address behind it is read from the keychain : refusing to look told a
        // reader staring at their own token that the feed carried no parameter.
        #expect(found.map(\.name) == ["token", "key"])

        let real = await model.secretAddress(ofFeed: feed.id)
        #expect(real == address)
    }

    @Test("What the reader designated is kept per source, folded")
    func designating() async throws {
        let feed = try await follow("https://feeds.example.com/rss?Token=abcdefghijkl")

        await model.setSecretParameters(["Token"], for: feed.id)

        let kept = await model.secretParameters(of: feed.id)
        #expect(kept == ["token"])
    }
}
