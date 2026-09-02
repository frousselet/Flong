//
//  SourceReconciliationTests.swift
//  FlongTests
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

/// A removal that never arrived, and the two halves of putting it right.
///
/// The first half is that a removal cannot be lost any more : the intention is
/// written down before it is queued, so an engine that was not there, a reset
/// or one refusal from the server no longer end it. The second is the repair
/// for the devices already wrong, which nothing else can reach : a source the
/// zone no longer holds, offered to the reader for removal.
@Suite("A source removed on another device")
struct SourceReconciliationTests {
    private func feed(_ title: String, at host: String) -> Feed {
        Feed(url: URL(string: "https://\(host)/atom.xml")!, title: title)
    }

    private func name(of feed: Feed) -> String { SyncRecords.name(forFeed: feed.url) }

    @Test("A source the zone no longer holds is one another device removed")
    func stranded() {
        let gone = feed("Le Monde", at: "lemonde.example.com")
        let kept = feed("Libération", at: "liberation.example.com")

        let stranded = SourceReconciliation.stranded(
            feeds: [gone, kept],
            confirmed: [name(of: gone), name(of: kept)],
            held: [name(of: kept)]
        )

        #expect(stranded.map(\.title) == ["Le Monde"])
    }

    /// The mistake that would cost a reader the source they had just added.
    @Test("A source the server has never confirmed is on its way up, not gone")
    func neverConfirmed() {
        let fresh = feed("Le Monde", at: "lemonde.example.com")

        // Followed a moment ago, or followed while the device was offline :
        // absent from the zone because it has not been sent, which is the
        // opposite of having been removed.
        #expect(SourceReconciliation.stranded(feeds: [fresh], confirmed: [], held: []).isEmpty)
    }

    @Test("A zone holding every source has nothing to tidy")
    func settled() {
        let feeds = [feed("Le Monde", at: "lemonde.example.com"), feed("Libération", at: "liberation.example.com")]
        let names = Set(feeds.map(name(of:)))

        #expect(SourceReconciliation.stranded(feeds: feeds, confirmed: names, held: names).isEmpty)
    }

    @Test("What is offered is in the order the reader reads it")
    func ordered() {
        let feeds = [
            feed("Libération", at: "liberation.example.com"),
            feed("arrêt sur images", at: "asi.example.com"),
            feed("Le Monde", at: "lemonde.example.com"),
        ]

        // By name and not by case : a source spelled in lower case belongs
        // where its name puts it, not at the end of the list.
        let stranded = SourceReconciliation.stranded(feeds: feeds, confirmed: Set(feeds.map(name(of:))), held: [])
        #expect(stranded.map(\.title) == ["arrêt sur images", "Le Monde", "Libération"])
    }
}

/// The intention to delete, which used to live nowhere it could survive.
@Suite("A deletion that outlives the moment it was decided")
struct PendingDeletionTests {
    private let database: AppDatabase
    private let state: SyncState

    init() throws {
        database = try AppDatabase.inMemory()
        state = SyncState(database)
    }

    @Test("Nothing is outstanding until something is removed")
    func empty() async throws {
        #expect(try await state.outstandingDeletions().isEmpty)
    }

    /// The whole of the bug, in one test. The engine may not exist at the
    /// moment a reader removes a source : a launch with no network fails the
    /// account check and leaves it nil for the session. The intention has to
    /// outlive that, or the source stays on the reader's other device for good.
    @Test("A removal decided with no engine is still there to be sent")
    func survivesTheEngineNotBeingThere() async throws {
        let feed = URL(string: "https://lemonde.example.com/atom.xml")!
        try await state.rememberDeletions([SyncRecords.name(forFeed: feed)])

        #expect(try await state.outstandingDeletions() == [SyncRecords.name(forFeed: feed)])
    }

    @Test("They come back in the order they were decided")
    func ordered() async throws {
        let moment = Date(timeIntervalSince1970: 1_787_646_600)
        try await state.rememberDeletions(["feed-second"], at: moment.addingTimeInterval(60))
        try await state.rememberDeletions(["feed-first"], at: moment)

        #expect(try await state.outstandingDeletions() == ["feed-first", "feed-second"])
    }

    @Test("Deciding the same removal twice is one intention, and keeps the first moment")
    func idempotent() async throws {
        let moment = Date(timeIntervalSince1970: 1_787_646_600)
        try await state.rememberDeletions(["feed-one"], at: moment)
        try await state.rememberDeletions(["feed-one"], at: moment.addingTimeInterval(3600))

        // A pass that queues the outstanding ones again must not push a name
        // to the back of the queue every time it does.
        #expect(try await state.outstandingDeletions() == ["feed-one"])
    }

    /// Only the server ends an intention : what it has confirmed gone, and what
    /// it says it never had, which is the same outcome reached another way.
    @Test("What the server has confirmed gone is finished with")
    func confirmed() async throws {
        try await state.rememberDeletions(["feed-one", "feed-two"])
        try await state.forgetDeletions(["feed-one"])

        #expect(try await state.outstandingDeletions() == ["feed-two"])
    }

    @Test("A zone taken down whole takes every intention with it")
    func zoneGone() async throws {
        try await state.rememberDeletions(["feed-one", "feed-two"])
        try await state.forgetEveryDeletion()

        #expect(try await state.outstandingDeletions().isEmpty)
    }

    /// A repair forgets what the server said about every record, and must not
    /// forget what this device has still to have deleted : that is the one
    /// thing a repair cannot work out again, the row it is about being gone.
    @Test("Forgetting every tag leaves the removals waiting")
    func aRepairKeepsThem() async throws {
        try await state.rememberDeletions(["feed-one"])
        try await state.forgetEveryRecord()

        #expect(try await state.outstandingDeletions() == ["feed-one"])
    }
}
