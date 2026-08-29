//
//  SubscriptionsModelTests.swift
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

@Suite("Subscriptions screen")
@MainActor
struct SubscriptionsModelTests {
    private let database: AppDatabase
    private let model: SubscriptionsModel

    init() throws {
        database = try AppDatabase.inMemory()
        model = SubscriptionsModel(database: database)
    }

    /// Writes an OPML file the way the file chooser would hand one over.
    private func file(_ opml: String) throws -> URL {
        let url = URL.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).opml")
        try Data(opml.utf8).write(to: url)
        return url
    }

    @Test("Folders come first, sorted, and the loose feeds last")
    func sectionOrder() async throws {
        let store = SubscriptionStore(database)
        try await store.subscribe(to: [
            Subscription(address: "https://feeds.example.com/1.xml", folder: "Tech/iOS"),
            Subscription(address: "https://feeds.example.com/2.xml", folder: "Presse"),
            Subscription(address: "https://feeds.example.com/3.xml"),
            Subscription(address: "https://feeds.example.com/4.xml", folder: "Tech"),
        ])

        await model.load()

        #expect(model.sections.map(\.folder) == ["Presse", "Tech", "Tech/iOS", nil])
        #expect(model.sections.map(\.feeds.count) == [1, 1, 1, 1])
    }

    @Test("Importing a file fills the screen and reports what it did")
    func importing() async throws {
        let url = try file(
            """
            <opml><body>
              <outline text="Tech">
                <outline text="Example" xmlUrl="https://feeds.example.com/1.xml"/>
              </outline>
              <outline text="Broken" xmlUrl="not an address"/>
            </body></opml>
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        await model.importOPML(from: url)

        #expect(model.report?.added == 1)
        #expect(model.report?.skipped.count == 1)
        #expect(model.failure == nil)
        #expect(model.sections.map(\.folder) == ["Tech"])
    }

    @Test("A file that is not a subscription list is reported, not thrown")
    func importingSomethingElse() async throws {
        let url = try file("<rss><channel/></rss>")
        defer { try? FileManager.default.removeItem(at: url) }

        await model.importOPML(from: url)

        #expect(model.failure == .notOPML)
        #expect(model.report == nil)
        #expect(model.sections.isEmpty)
    }

    @Test("A file that is not there is reported too")
    func importingAMissingFile() async throws {
        await model.importOPML(from: URL.temporaryDirectory.appendingPathComponent("nothing.opml"))

        #expect(model.failure == .unreadableFile)
    }
}
