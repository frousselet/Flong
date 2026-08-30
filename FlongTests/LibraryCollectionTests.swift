//
//  LibraryCollectionTests.swift
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

@Suite("The squares on the collections page")
struct LibraryCollectionTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let library: LibraryStore
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
        library = LibraryStore(database)
    }

    private func feed(_ address: String, title: String) async throws -> Feed {
        try await subscriptions.subscribe(to: Subscription(address: address, title: title)).feed
    }

    @discardableResult
    private func article(_ title: String, in feed: Feed, image: String? = nil) async throws -> UUID {
        let entry = Entry(
            feedID: feed.id,
            guid: "urn:example:\(title)",
            url: URL(string: "https://example.com/\(title)"),
            title: title,
            publishedAt: now,
            receivedAt: now
        )
        var stored = entry
        stored.imageURL = image.flatMap(URL.init(string:))
        try await database.writer.write { db in try stored.insert(db) }
        return stored.id
    }

    // MARK: - What the reader did on purpose

    @Test("Favourites and notes each become a square, and neither counts the other")
    func deliberate() async throws {
        let paper = try await feed("https://a.example.com/f.xml", title: "Le Quotidien")
        let starred = try await article("starred", in: paper, image: "https://example.com/a.jpg")
        let noted = try await article("noted", in: paper)
        try await article("neither", in: paper)

        try await library.setStarred([starred], to: true, at: now)
        _ = try await library.annotate(noted, with: "Worth coming back to", at: now)

        let collections = try await library.collections()
        let favourites = try #require(collections.first { $0.kind == .starred })
        let notes = try #require(collections.first { $0.kind == .annotated })

        #expect(favourites.count == 1)
        #expect(favourites.cover?.absoluteString == "https://example.com/a.jpg")
        #expect(notes.count == 1)
        // The article nobody touched is in neither, and is not kept at all.
        #expect(try await library.count() == 2)
    }

    @Test("Unstarring takes an article out of the favourites without losing a note")
    func unstarring() async throws {
        let paper = try await feed("https://a.example.com/f.xml", title: "Le Quotidien")
        let both = try await article("both", in: paper)

        try await library.setStarred([both], to: true, at: now)
        _ = try await library.annotate(both, with: "A note", at: now)
        try await library.setStarred([both], to: false, at: now)

        let collections = try await library.collections()
        #expect(collections.first { $0.kind == .starred } == nil)
        #expect(collections.first { $0.kind == .annotated }?.count == 1)
        // The copy stays, because the note is a reason of its own.
        #expect(try await library.count() == 1)
    }

    @Test("A favourite survives the article it came from")
    func survivesThePurge() async throws {
        let paper = try await feed("https://a.example.com/f.xml", title: "Le Quotidien")
        let kept = try await article("kept", in: paper)
        try await library.setStarred([kept], to: true, at: now)

        // Retention takes the stream row, and the copy's `entry_id` goes to
        // NULL with it. Reading the star back off the stream would have the
        // favourites empty themselves the first time a purge runs.
        try await database.writer.write { db in _ = try Entry.deleteAll(db) }

        #expect(try await library.collections().first { $0.kind == .starred }?.count == 1)
        #expect(try await library.summaries(in: .starred).count == 1)
    }

    // MARK: - What falls out of the copy

    @Test("Each month of keeping is a square, newest first")
    func months() async throws {
        let paper = try await feed("https://a.example.com/f.xml", title: "Le Quotidien")
        let calendar = Calendar.current
        let thisMonth = calendar.startOfDay(for: now)
        let older = try #require(calendar.date(byAdding: .month, value: -2, to: thisMonth))

        try await library.promote([try await article("recent", in: paper)], at: thisMonth)
        try await library.promote([try await article("old", in: paper)], at: older)

        let months = try await library.collections().compactMap { collection -> Date? in
            if case .month(let month) = collection.kind { return month } else { return nil }
        }

        #expect(months.count == 2)
        #expect(months[0] > months[1])
        // Named by the first of the month it stands for, in the reader's own
        // calendar rather than in a slice of UTC.
        #expect(calendar.component(.day, from: months[0]) == 1)
        #expect(calendar.isDate(months[0], equalTo: thisMonth, toGranularity: .month))
        #expect(try await library.summaries(in: .month(months[1])).count == 1)
    }

    @Test("An empty library shows no squares at all")
    func empty() async throws {
        #expect(try await library.collections().isEmpty)
    }
}
