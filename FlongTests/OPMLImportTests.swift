//
//  OPMLImportTests.swift
//  FlongTests
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

@Suite("OPML import")
struct OPMLImportTests {
    private let store: SubscriptionStore
    private let opml: OPMLImport

    init() throws {
        let database = try AppDatabase.inMemory()
        store = SubscriptionStore(database)
        opml = OPMLImport(store)
    }

    private static let file = Data(
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Subscriptions</title></head>
          <body>
            <outline text="Tech">
              <outline type="rss" text="Example" xmlUrl="https://feeds.example.com/1.xml"
                       htmlUrl="https://example.com"/>
              <outline text="iOS">
                <outline type="rss" text="Nested" xmlUrl="FEEDS.example.com/2.xml"/>
              </outline>
            </outline>
            <outline type="rss" xmlUrl="https://www.example.org/feed"/>
          </body>
        </opml>
        """.utf8
    )

    @Test("A file brings its feeds and its folder tree over")
    func importing() async throws {
        let report = try await opml(Self.file)

        #expect(report.added == 3)
        #expect(report.alreadyFollowed == 0)
        #expect(report.skipped.isEmpty)

        let feeds = try await store.feeds()
        #expect(feeds.map(\.title) == ["Example", "example.org", "Nested"])
        #expect(try await store.folders().map(\.path) == ["Tech", "Tech/iOS"])
    }

    @Test("Addresses are canonicalized on the way in")
    func addressesAreCanonical() async throws {
        _ = try await opml(Self.file)

        let nested = try await store.feed(at: "https://feeds.example.com/2.xml")
        #expect(nested?.title == "Nested")
        #expect(nested?.folder == "Tech/iOS")
    }

    @Test("A feed with no title of its own is named after its host")
    func untitledFeed() async throws {
        _ = try await opml(Self.file)

        let feed = try await store.feed(at: "https://www.example.org/feed")
        #expect(feed?.title == "example.org")
    }

    @Test("The same file imported twice adds nothing")
    func importingTwice() async throws {
        _ = try await opml(Self.file)
        let second = try await opml(Self.file)

        #expect(second.added == 0)
        #expect(second.alreadyFollowed == 3)
        #expect(try await store.count() == 3)
    }

    @Test("A second import leaves the reader's own naming and filing alone")
    func importingDoesNotOverwrite() async throws {
        _ = try await opml(Self.file)
        let feed = try #require(try await store.feed(at: "https://feeds.example.com/1.xml"))

        try await store.rename(feed.id, to: "My own name")
        try await store.move(feed.id, toFolder: "Veille")
        _ = try await opml(Self.file)

        let again = try await store.feed(id: feed.id)
        #expect(again?.title == "My own name")
        #expect(again?.folder == "Veille")
    }

    @Test("One address listed twice is one subscription")
    func duplicatesInsideTheFile() async throws {
        let report = try await opml(
            Data(
                """
                <opml><body>
                  <outline text="Once" xmlUrl="https://feeds.example.com/1.xml"/>
                  <outline text="Twice" xmlUrl="https://feeds.example.com:443/1.xml"/>
                </body></opml>
                """.utf8
            )
        )

        #expect(report.added == 1)
        #expect(report.alreadyFollowed == 1)
        #expect(try await store.count() == 1)
    }

    @Test("An address nobody can read is reported, not fatal")
    func unusableAddressesAreReported() async throws {
        let report = try await opml(
            Data(
                """
                <opml><body>
                  <outline text="Fine" xmlUrl="https://feeds.example.com/1.xml"/>
                  <outline text="Nonsense" xmlUrl="not an address"/>
                  <outline text="Private" xmlUrl="https://alice:hunter2@feeds.example.com/2.xml"/>
                </body></opml>
                """.utf8
            )
        )

        #expect(report.added == 1)
        #expect(report.total == 3)
        #expect(report.skipped.map(\.title) == ["Nonsense", "Private"])
        #expect(report.skipped.map(\.reason) == [.malformed, .embeddedCredentials])
    }

    @Test("A file that is not a subscription list stops the import")
    func aBadFileImportsNothing() async throws {
        await #expect(throws: OPMLError.notOPML) { _ = try await opml(Data("<rss/>".utf8)) }
        #expect(try await store.count() == 0)
    }
}
