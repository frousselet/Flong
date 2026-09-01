//
//  CollaborationNoticeTests.swift
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

/// What is said when somebody puts something in a shared collection.
@Suite("Collaboration notices")
struct CollaborationNoticeTests {

    // MARK: - The wording

    @Test("Nothing filed says nothing")
    func saysNothingAboutNothing() {
        #expect(Announcement.filings([]) == nil)
    }

    /// The case worth writing well : the person leads, because a collaboration
    /// is somebody doing something and not a calculation.
    @Test("One filing names the person, the collection, and the headline")
    func namesOneFiling() throws {
        let announcement = try #require(
            Announcement.filings([(collection: "Typographie", by: "Marie", title: "Une réforme")])
        )

        #expect(announcement.title.contains("Marie"))
        #expect(announcement.title.contains("Typographie"))
        #expect(announcement.body == "Une réforme")
        #expect(announcement.thread == Announcement.Thread.filings)
    }

    @Test("A filing by somebody who cannot be named still names the collection")
    func namesTheCollectionAlone() throws {
        let announcement = try #require(
            Announcement.filings([(collection: "Typographie", by: nil, title: "Une réforme")])
        )

        #expect(announcement.title.contains("Typographie"))
        #expect(announcement.body == "Une réforme")
    }

    /// One person adding four pieces is one thing happening, and four names
    /// would be four.
    @Test("Several filings by one person name that person once")
    func countsPeopleAndNotFilings() throws {
        let announcement = try #require(
            Announcement.filings([
                (collection: "Typographie", by: "Marie", title: "Une réforme"),
                (collection: "Typographie", by: "Marie", title: "Un rapport"),
            ])
        )

        #expect(announcement.title.contains("Typographie"))
        #expect(announcement.body == "Marie")
    }

    @Test("Filings across collections do not claim to be in one of them")
    func doesNotNameOneOfSeveral() throws {
        let announcement = try #require(
            Announcement.filings([
                (collection: "Typographie", by: "Marie", title: "Une réforme"),
                (collection: "Urbanisme", by: "Paul", title: "Un rapport"),
            ])
        )

        #expect(!announcement.title.contains("Typographie"))
        #expect(announcement.body.contains("Marie"))
        #expect(announcement.body.contains("Paul"))
    }

    @Test("Several filings by nobody nameable fall back to the headlines")
    func fallsBackToHeadlines() throws {
        let announcement = try #require(
            Announcement.filings([
                (collection: "Typographie", by: nil, title: "Une réforme"),
                (collection: "Typographie", by: nil, title: "Un rapport"),
            ])
        )

        #expect(announcement.body.contains("Une réforme"))
        #expect(announcement.body.contains("Un rapport"))
    }

    // MARK: - When a thing arrived

    /// The bug this exists to stop. A list is rewritten whole every time any of
    /// it changes, so a week-old article would be stamped as new the moment its
    /// filer added something else, and announced all over again.
    @Test("An article already here keeps the moment it turned up")
    func keepsTheMomentItArrived() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let store = SharedEntryStore(database)
        let monday = Date(timeIntervalSince1970: 1_000_000)
        let friday = monday.addingTimeInterval(4 * 86_400)

        try await store.replace(
            [SharedEntry(guid: "one", title: "First")],
            inList: "list-marie-", by: "_marie", inZone: "shared-1", at: monday
        )
        // Marie adds a second piece on Friday, which rewrites her whole list.
        try await store.replace(
            [SharedEntry(guid: "one", title: "First"), SharedEntry(guid: "two", title: "Second")],
            inList: "list-marie-", by: "_marie", inZone: "shared-1", at: friday
        )

        let since = friday.addingTimeInterval(-60)
        let arrived = try await store.arrived(since: since, excluding: nil)

        #expect(arrived.map(\.entry.guid) == ["two"])
    }

    @Test("What the reader filed themselves is not announced to them")
    func skipsTheirOwn() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let store = SharedEntryStore(database)
        let now = Date()

        try await store.replace(
            [SharedEntry(guid: "mine", title: "Mine")],
            inList: "list-me-", by: "_me", inZone: "shared-1", at: now
        )
        try await store.replace(
            [SharedEntry(guid: "theirs", title: "Theirs")],
            inList: "list-marie-", by: "_marie", inZone: "shared-1", at: now
        )

        let arrived = try await store.arrived(since: now.addingTimeInterval(-60), excluding: "list-me-")
        #expect(arrived.map(\.entry.guid) == ["theirs"])
    }

    /// Left out of the query rather than filtered afterwards, so that a muted
    /// collection cannot move the watermark past one that is not.
    @Test("A collection the reader quietened says nothing")
    func skipsAMutedCollection() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let store = SharedEntryStore(database)
        let now = Date()

        try await store.replace(
            [SharedEntry(guid: "quiet", title: "Quiet")],
            inList: "list-marie-", by: "_marie", inZone: "shared-quiet", at: now
        )
        try await store.replace(
            [SharedEntry(guid: "loud", title: "Loud")],
            inList: "list-marie-", by: "_marie", inZone: "shared-loud", at: now
        )

        let arrived = try await store.arrived(
            since: now.addingTimeInterval(-60), excluding: nil, muted: ["shared-quiet"]
        )
        #expect(arrived.map(\.entry.guid) == ["loud"])
    }

    @Test("Nothing has arrived since a moment after everything arrived")
    func findsNothingAfterwards() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let store = SharedEntryStore(database)
        let now = Date()

        try await store.replace(
            [SharedEntry(guid: "one", title: "First")],
            inList: "list-marie-", by: "_marie", inZone: "shared-1", at: now
        )

        #expect(try await store.arrived(since: now.addingTimeInterval(60), excluding: nil).isEmpty)
    }

    // MARK: - The switches

    @Test("Muting one collection is remembered, and lets the others speak")
    func mutesOneCollection() {
        let preferences = Preferences(cloud: nil, local: defaults())
        preferences.mutedSharedCollections = ["shared-quiet"]

        #expect(preferences.mutedSharedCollections == ["shared-quiet"])
    }

    /// A reader who turns the switch on means the collections they are in,
    /// including the ones they have not been invited to yet.
    @Test("A collection nobody quietened is loud")
    func isLoudByDefault() {
        let preferences = Preferences(cloud: nil, local: defaults())
        #expect(preferences.mutedSharedCollections.isEmpty)
    }

    @Test("The wanting travels and the watermark does not")
    func keepsTheWatermarkLocal() {
        let local = defaults()
        let preferences = Preferences(cloud: nil, local: local)

        preferences.wantsCollaborationNotices = true
        preferences.collaborationsAnnouncedAt = Date(timeIntervalSince1970: 1_000_000)

        #expect(preferences.wantsCollaborationNotices)
        #expect(preferences.collaborationsAnnouncedAt != nil)
        // The watermark is about this device and is kept where a device keeps
        // what is its own.
        #expect(local.object(forKey: "notify.collaborations-announced-at") != nil)
    }

    private func defaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        return suite
    }
}
