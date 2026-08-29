//
//  BackgroundWorkTests.swift
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
import Synchronization
import Testing

@testable import Flong

/// A job whose work is counting, so a runner can be tested without waiting for
/// anything real.
private final class CountingJob: ResumableJob, @unchecked Sendable {
    let name = "counting"
    private let lock = NSLock()
    private var left: Int
    private(set) var steps = 0
    let batch: Int

    init(total: Int, batch: Int = 10) {
        self.left = total
        self.batch = batch
    }

    func remaining() async throws -> Int { lock.withLock { left } }

    func step() async throws -> Int {
        lock.withLock {
            steps += 1
            let done = min(batch, left)
            left -= done
            return done
        }
    }
}

@Suite("Long work")
struct BackgroundWorkTests {
    @Test("A job runs to its end, a batch at a time")
    func running() async throws {
        let job = CountingJob(total: 45, batch: 10)

        let outcome = await JobRunner(job).run()

        #expect(outcome.done == 45)
        #expect(outcome.isFinished)
        #expect(job.steps == 6)
    }

    @Test("A job stopped between two batches loses nothing, and picks up where it was")
    func resuming() async throws {
        let job = CountingJob(total: 100, batch: 10)

        // The first run is given no time at all, so it stops after one batch.
        let first = await JobRunner(job).run(until: Date())
        #expect(first.done == 0)

        // A run that is given a moment gets through part of it.
        let task = Task { await JobRunner(job).run() }
        let second = await task.value
        #expect(second.done + first.done == 100)
        #expect(second.isFinished)

        // And a run with nothing left does nothing at all.
        let third = await JobRunner(job).run()
        #expect(third.done == 0)
        #expect(third.isFinished)
    }

    @Test("A cancelled run stops between batches rather than in the middle of one")
    func cancelling() async throws {
        let job = CountingJob(total: 1000, batch: 1)

        let task = Task { await JobRunner(job).run() }
        task.cancel()
        let outcome = await task.value

        #expect(outcome.done < 1000)
        #expect(try await job.remaining() == 1000 - outcome.done)
    }

    @Test("Progress is reported as it goes")
    func progress() async throws {
        let job = CountingJob(total: 30, batch: 10)
        let reports = Mutex<[Int]>([])

        await JobRunner(job).run { done, _ in reports.withLock { $0.append(done) } }

        #expect(reports.withLock { $0 } == [10, 20, 30])
    }
}

@Suite("The work an import leaves behind", .serialized)
struct FirstFetchJobTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let server = StubServer(host: "firstfetch.example.com")

    init() throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
    }

    private var job: FirstFetchJob {
        FirstFetchJob(
            database,
            fetcher: FeedFetcher(
                session: server.makeSession(),
                throttle: HostThrottle(interval: 0, burst: 100),
                userAgent: "Flong/test"
            )
        )
    }

    @Test("A feed never fetched is work left to do")
    func remaining() async throws {
        for index in 0..<5 {
            try await subscriptions.subscribe(
                to: Subscription(address: "https://firstfetch.example.com/\(index).xml", title: "Feed \(index)")
            )
        }

        #expect(try await job.remaining() == 5)
    }

    @Test("The import finishes, however many times it is interrupted")
    func finishing() async throws {
        let body = try Fixtures.data("Feeds/rss2.xml")
        server.install { _ in StubResponse(statusCode: 200, body: body) }
        defer { server.reset() }

        for index in 0..<20 {
            try await subscriptions.subscribe(
                to: Subscription(address: "https://firstfetch.example.com/\(index).xml", title: "Feed \(index)")
            )
        }

        // Interrupted after every batch, as a background task would be.
        var rounds = 0
        while try await job.remaining() > 0, rounds < 20 {
            _ = try await job.step()
            rounds += 1
        }

        #expect(try await job.remaining() == 0)
        #expect(try await ArticleStore(database).count(.all) == 40)
    }

    @Test("A feed that refuses to be fetched does not hold the queue for ever")
    func failingFeeds() async throws {
        server.install { _ in StubResponse(statusCode: 404) }
        defer { server.reset() }

        try await subscriptions.subscribe(
            to: Subscription(address: "https://firstfetch.example.com/gone.xml", title: "Gone")
        )

        // Three refusals settle it, and a quarantined feed is no longer work.
        for _ in 0..<FeedRefresh.quarantineAfterRejection {
            _ = try await job.step()
        }

        #expect(try await job.remaining() == 0)
    }
}
