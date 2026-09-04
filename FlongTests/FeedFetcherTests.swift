//
//  FeedFetcherTests.swift
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

@Suite("Feed fetcher", .serialized)
struct FeedFetcherTests {
    private let server = StubServer(host: "fetcher.example.com")

    private func fetcher(limits: FeedFetcher.Limits = FeedFetcher.Limits()) -> FeedFetcher {
        FeedFetcher(
            session: server.makeSession(),
            throttle: HostThrottle(interval: 0, burst: 100),
            limits: limits,
            userAgent: "Flong/test (+https://github.com/frousselet/Flong)"
        )
    }

    private var feedURL: URL { server.url.appending(path: "feed.xml") }

    @Test("A feed comes back with what the server said about it")
    func fetching() async throws {
        server.install { _ in
            StubResponse(
                statusCode: 200,
                headers: [
                    "Content-Type": "application/rss+xml",
                    "ETag": "\"abc\"",
                    "Last-Modified": "Wed, 26 Aug 2026 09:00:00 GMT",
                ],
                body: Data("<rss/>".utf8)
            )
        }
        defer { server.reset() }

        let outcome = await fetcher().fetch(FetchRequest(url: feedURL))

        guard case .updated(let document) = outcome else {
            Issue.record("Expected an update, got \(outcome)")
            return
        }
        #expect(document.data == Data("<rss/>".utf8))
        #expect(document.etag == "\"abc\"")
        #expect(document.lastModified == "Wed, 26 Aug 2026 09:00:00 GMT")
        #expect(document.contentType == "application/rss+xml")
    }

    @Test("Every request is conditional and says who is asking")
    func conditionalRequest() async throws {
        server.install { _ in StubResponse(statusCode: 304) }
        defer { server.reset() }

        let outcome = await fetcher().fetch(
            FetchRequest(url: feedURL, etag: "\"abc\"", lastModified: "Wed, 26 Aug 2026 09:00:00 GMT")
        )

        let request = try #require(server.requests.first)
        #expect(request.headers["If-None-Match"] == "\"abc\"")
        #expect(request.headers["If-Modified-Since"] == "Wed, 26 Aug 2026 09:00:00 GMT")
        #expect(request.headers["User-Agent"]?.contains("github.com/frousselet/Flong") == true)

        guard case .notModified = outcome else {
            Issue.record("Expected 304 to be recognized, got \(outcome)")
            return
        }
    }

    @Test("A server asking to be left alone is left alone")
    func rateLimiting() async throws {
        server.install { _ in StubResponse(statusCode: 429, headers: ["Retry-After": "120"]) }
        defer { server.reset() }

        let throttle = HostThrottle(interval: 0, burst: 100)
        let fetcher = FeedFetcher(session: server.makeSession(), throttle: throttle, userAgent: "Flong/test")

        let outcome = await fetcher.fetch(FetchRequest(url: feedURL))

        guard case .failed(.rateLimited(let retryAfter)) = outcome else {
            Issue.record("Expected rate limiting, got \(outcome)")
            return
        }
        #expect(retryAfter == 120)

        let paused = await throttle.pause(forHost: server.host)
        #expect(paused != nil)
        #expect(paused.map { $0.timeIntervalSinceNow > 60 } == true)
    }

    @Test(
        "Statuses are told apart, since they do not mean the same thing",
        arguments: [
            (401, FetchFailure.unauthorized(status: 401)),
            (403, FetchFailure.unauthorized(status: 403)),
            (404, FetchFailure.gone(status: 404)),
            (410, FetchFailure.gone(status: 410)),
            (500, FetchFailure.http(status: 500)),
        ]
    )
    func statuses(status: Int, expected: FetchFailure) async throws {
        server.install { _ in StubResponse(statusCode: status) }
        defer { server.reset() }

        let outcome = await fetcher().fetch(FetchRequest(url: feedURL))

        guard case .failed(let failure) = outcome else {
            Issue.record("Expected a failure, got \(outcome)")
            return
        }
        #expect(failure == expected)
    }

    @Test("A body that never ends is dropped rather than swallowed")
    func sizeCap() async throws {
        server.install { _ in StubResponse(statusCode: 200, body: Data(repeating: 0x41, count: 200_000)) }
        defer { server.reset() }

        var limits = FeedFetcher.Limits()
        limits.maximumBytes = 1024

        let outcome = await fetcher(limits: limits).fetch(FetchRequest(url: feedURL))

        guard case .failed(.tooLarge) = outcome else {
            Issue.record("Expected the cap to bite, got \(outcome)")
            return
        }
    }

    @Test("Retry-After is read as seconds or as a date")
    func retryAfterHeader() {
        let now = Date(timeIntervalSince1970: 1_787_646_600)

        #expect(FeedFetcher.retryAfter("120", now: now) == 120)
        #expect(FeedFetcher.retryAfter(" 30 ", now: now) == 30)
        #expect(FeedFetcher.retryAfter("Tue, 25 Aug 2026 08:35:00 GMT", now: now) == 300)
        #expect(FeedFetcher.retryAfter("Tue, 25 Aug 2026 08:00:00 GMT", now: now) == 0)
        #expect(FeedFetcher.retryAfter(nil) == nil)
        #expect(FeedFetcher.retryAfter("soon") == nil)
    }
}

@Suite("Host throttle")
struct HostThrottleTests {
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    @Test("Requests to one host are spaced out")
    func spacing() async {
        let throttle = HostThrottle(interval: 2, burst: 1)

        #expect(await throttle.wait(forHost: "example.com", now: now) == 0)
        #expect(await throttle.wait(forHost: "example.com", now: now) == 2)
        #expect(await throttle.wait(forHost: "example.com", now: now) == 4)
    }

    @Test("Another host is not made to wait for this one")
    func hostsAreIndependent() async {
        let throttle = HostThrottle(interval: 2, burst: 1)

        _ = await throttle.wait(forHost: "example.com", now: now)
        #expect(await throttle.wait(forHost: "other.example", now: now) == 0)
    }

    @Test("A host left alone may be asked several things at once")
    func burst() async {
        let throttle = HostThrottle(interval: 1, burst: 3)

        for _ in 0..<3 {
            #expect(await throttle.wait(forHost: "example.com", now: now) == 0)
        }
        #expect(await throttle.wait(forHost: "example.com", now: now) == 1)
    }

    @Test("Credit does not pile up for ever")
    func creditIsCapped() async {
        let throttle = HostThrottle(interval: 1, burst: 2)
        _ = await throttle.wait(forHost: "example.com", now: now)

        // An hour later, the host owes at most the burst, not thirty six hundred.
        let later = now.addingTimeInterval(3600)
        for _ in 0..<2 {
            #expect(await throttle.wait(forHost: "example.com", now: later) == 0)
        }
        #expect(await throttle.wait(forHost: "example.com", now: later) == 1)
    }

    @Test("A pause holds every request to that host")
    func pausing() async {
        let throttle = HostThrottle(interval: 1, burst: 10)
        await throttle.pause(host: "example.com", until: now.addingTimeInterval(300))

        #expect(await throttle.wait(forHost: "example.com", now: now) == 300)
    }
}

@Suite("Refresh schedule")
struct RefreshScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    @Test("The interval follows the median gap, not the burst")
    func observedInterval() {
        // Four posts an hour apart, then two in the same minute.
        let dates = [0, 3600, 7200, 10800, 10860, 10920].map { now.addingTimeInterval(Double($0)) }

        #expect(RefreshSchedule.observedInterval(from: dates) == 3600)
    }

    @Test("An interval nobody would want is brought back in range")
    func clamping() {
        let hourly = (0..<5).map { now.addingTimeInterval(Double($0) * 60) }
        #expect(RefreshSchedule.observedInterval(from: hourly) == RefreshSchedule.minimumInterval)

        let yearly = (0..<5).map { now.addingTimeInterval(Double($0) * 365 * 86400) }
        #expect(RefreshSchedule.observedInterval(from: yearly) == RefreshSchedule.maximumInterval)

        #expect(RefreshSchedule.observedInterval(from: [now]) == nil)
    }

    @Test("Backoff doubles, and stops doubling")
    func backoff() {
        #expect(RefreshSchedule.backoff(afterFailures: 0, jitter: 1) == 0)
        #expect(RefreshSchedule.backoff(afterFailures: 1, jitter: 1) == RefreshSchedule.minimumInterval)
        #expect(RefreshSchedule.backoff(afterFailures: 3, jitter: 1) == RefreshSchedule.minimumInterval * 4)
        #expect(RefreshSchedule.backoff(afterFailures: 20, jitter: 1) <= RefreshSchedule.maximumInterval)
    }

    @Test("A feed is due when it has waited its interval, and not before")
    func isDue() {
        var feed = Feed(url: URL(string: "https://feeds.example.com/1.xml")!, title: "Example")
        #expect(RefreshSchedule.isDue(feed, now: now))

        feed.lastFetchAt = now
        feed.observedInterval = 3600
        #expect(!RefreshSchedule.isDue(feed, now: now.addingTimeInterval(1800)))
        #expect(RefreshSchedule.isDue(feed, now: now.addingTimeInterval(3601)))

        // The reader's own setting outranks what the feed suggests.
        feed.refreshInterval = RefreshSchedule.minimumInterval
        #expect(RefreshSchedule.isDue(feed, now: now.addingTimeInterval(1000)))
    }

    @Test("A quarantined feed is not asked for at all")
    func quarantine() {
        var feed = Feed(url: URL(string: "https://feeds.example.com/1.xml")!, title: "Example")
        feed.quarantinedAt = now

        #expect(!RefreshSchedule.isDue(feed, now: now.addingTimeInterval(86400 * 30)))
    }

    @Test("The stagger is stable, bounded, and different per device")
    func stagger() {
        let feedID = UUID.v7()
        let first = UUID()
        let second = UUID()

        let offset = DeviceStagger.offset(for: feedID, interval: 3600, device: first)
        #expect(offset == DeviceStagger.offset(for: feedID, interval: 3600, device: first))
        #expect(offset >= 0 && offset <= 1200)
        #expect(offset != DeviceStagger.offset(for: feedID, interval: 3600, device: second))
    }

    /// **The one thing the test above cannot say.** It asks the same process
    /// twice and was answered consistently by a `Hasher` seeded once per
    /// process : the offset was drawn afresh at every launch, so a device
    /// landed on a different side of its interval every time it started and a
    /// feed's next moment moved when nothing about the feed had. Pinning the
    /// value is the only way a test says `and again tomorrow`.
    @Test("The stagger is the same after a relaunch, which is what makes a due moment a moment")
    func staggerSurvivesTheProcess() {
        let feedID = UUID(uuidString: "00000000-0000-7000-8000-000000000001")!
        let device = UUID(uuidString: "00000000-0000-4000-8000-0000000000ff")!

        #expect(abs(DeviceStagger.offset(for: feedID, interval: 3600, device: device) - 297.6) < 0.001)
    }

    @Test("A feed's next moment is a moment, and the same one each time it is asked for")
    func dueIsAMoment() {
        var feed = Feed(url: URL(string: "https://feeds.example.com/1.xml")!, title: "Example")

        // Never fetched is due, and has been since it was subscribed to.
        #expect(RefreshSchedule.due(feed) == .distantPast)

        feed.lastFetchAt = now
        feed.observedInterval = 3600
        #expect(RefreshSchedule.due(feed) == now.addingTimeInterval(3600))

        // Asked twice, the same answer. It was not : the backoff drew a fresh
        // jitter on every call, so a failing feed's moment moved by minutes
        // between two evaluations a second apart.
        feed.failureCount = 3
        #expect(RefreshSchedule.due(feed) == RefreshSchedule.due(feed))
        #expect(RefreshSchedule.due(feed) == now.addingTimeInterval(RefreshSchedule.minimumInterval * 4))

        // And a quarantined feed has no moment at all.
        feed.quarantinedAt = now
        #expect(RefreshSchedule.due(feed) == nil)
    }

    @Test("A feed that is failing is staggered too, so two devices do not back off in lockstep")
    func staggerOnTheFailurePath() {
        let backedOff = RefreshSchedule.nextRefresh(after: now, interval: 3600, failures: 2, stagger: 90)
        #expect(backedOff == now.addingTimeInterval(RefreshSchedule.minimumInterval * 2 + 90))
    }
}
