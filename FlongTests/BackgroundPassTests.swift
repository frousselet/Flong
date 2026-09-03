//
//  BackgroundPassTests.swift
//  FlongTests
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

/// The whole of the work, at rest and on the mains.
///
/// The conditions themselves belong to the system : whether a device is idle,
/// charging and cool enough is `BGProcessingTaskRequest`'s answer on iOS and
/// the power source's on macOS, and neither is a thing a test can arrange.
/// What is testable is the part written here, which is the part Photos declares
/// and an application has to implement : one pass at a time, and a floor
/// between two of them.
@Suite("The full pass, and when it may run", .serialized)
struct BackgroundPassTests {
    init() {
        BackgroundScheduler.forgetTheLastFullPass()
    }

    @Test("A pass runs when nothing has run before it")
    func first() async {
        var ran = false
        let started = await BackgroundScheduler.runFullPass { ran = true }

        #expect(started)
        #expect(ran)
    }

    @Test("A second pass too soon after the first is left")
    func floor() async {
        _ = await BackgroundScheduler.runFullPass {}

        var ran = false
        let started = await BackgroundScheduler.runFullPass { ran = true }

        // Photos calls this `MinDurationBetweenInstances`. It is what stops a
        // pass deferred for want of power from running again the moment it is
        // rescheduled.
        #expect(!started)
        #expect(!ran)
    }

    @Test("A refresh stands aside while the full pass is running")
    func groupOfOne() async {
        var refreshed = false

        await BackgroundScheduler.runFullPass {
            await BackgroundScheduler.runRefresh { refreshed = true }
        }

        // Photos puts every heavy activity in one group with a concurrency
        // limit of one. Here the full pass fetches every feed a reader follows,
        // and a refresh running alongside it would double what the publishers
        // see.
        #expect(!refreshed)
    }

    @Test("A refresh runs freely when no pass is running")
    func refreshAlone() async {
        var refreshed = false
        await BackgroundScheduler.runRefresh { refreshed = true }

        #expect(refreshed)
    }

    @Test("The intervals are the ones Photos settled on")
    func intervals() {
        // `photoanalysisd.backgroundanalysis` : a six-hour interval, a hundred
        // minute floor, forty-five minutes of jitter.
        #expect(BackgroundScheduler.fullPassInterval == 6 * 60 * 60)
        #expect(BackgroundScheduler.fullPassFloor == 100 * 60)
        #expect(BackgroundScheduler.fullPassJitter == 45 * 60)

        // The floor has to be shorter than the interval, or a pass that ran on
        // time would refuse the next one for having been punctual.
        #expect(BackgroundScheduler.fullPassFloor < BackgroundScheduler.fullPassInterval)
    }

    @Test("The next pass is counted from the last one, not from whenever it was asked")
    func countedFromTheLast() async {
        let now = Date()
        _ = await BackgroundScheduler.runFullPass {}

        // Asked for a second later, and a second later again : the answer is
        // the same moment both times. It used to be six hours from whenever it
        // was asked, and it was asked at every launch and on every return to
        // the foreground, so on a phone anyone actually uses the pass was
        // pushed out of reach and only ever ran after a night untouched.
        let next = BackgroundScheduler.nextFullPass(now: now, jitter: 0)
        #expect(abs(next.timeIntervalSince(now) - BackgroundScheduler.fullPassInterval) < 5)
    }

    @Test("A device that has not had a pass for a day asks for one now")
    func overdueAsksNow() {
        BackgroundScheduler.forgetTheLastFullPass()

        let now = Date()
        #expect(BackgroundScheduler.nextFullPass(now: now, jitter: 0) == now)
    }

    @Test("The moment of the last pass outlives the process that ran it")
    func remembered() async {
        let now = Date()
        _ = await BackgroundScheduler.runFullPass {}

        // Held in a static for the life of the process, it was forgotten at
        // every relaunch, which on iOS is minutes : the floor guarded nothing
        // across exactly the launches it exists to guard across.
        #expect(BackgroundScheduler.lastFullPass().timeIntervalSince(now) > -5)
    }
}

/// The order a budget is spent in, and what a background pass will not spend.
///
/// A background refresh is given about twenty-five seconds and is cancelled
/// when they are up, so the order is not a detail : it decides which feeds are
/// ever refreshed at all on a large subscription list.
@Suite("Which feeds a short budget goes to")
struct RefreshOrderTests {
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    private func feed(_ title: String, interval: TimeInterval, fetched ago: TimeInterval?) -> Feed {
        var feed = Feed(url: URL(string: "https://\(title).example.com/f.xml")!, title: title)
        feed.refreshInterval = interval
        feed.lastFetchAt = ago.map { now.addingTimeInterval(-$0) }
        return feed
    }

    @Test("Lateness is measured against a feed's own rhythm, not in seconds")
    func relative() {
        // Both are an hour past due. The hourly one has waited a whole extra
        // interval ; the daily one a twenty-fourth of one, and has almost
        // certainly published nothing.
        let hourly = feed("hourly", interval: 3600, fetched: 7200)
        let daily = feed("daily", interval: 86400, fetched: 86400 + 3600)

        #expect(RefreshSchedule.lateness(hourly, now: now) > RefreshSchedule.lateness(daily, now: now))
    }

    @Test("A feed nobody has ever fetched comes first of all")
    func neverFetched() {
        let fresh = feed("new", interval: 3600, fetched: nil)
        let late = feed("late", interval: 3600, fetched: 100 * 3600)

        #expect(RefreshSchedule.lateness(fresh, now: now) > RefreshSchedule.lateness(late, now: now))
    }

    @Test("Exactly due is one, and not yet due is less")
    func theScale() {
        // One is the boundary the ordering is read against, so it is worth
        // pinning : below it a feed is not due at all.
        #expect(abs(RefreshSchedule.lateness(feed("due", interval: 3600, fetched: 3600), now: now) - 1) < 0.001)
        #expect(RefreshSchedule.lateness(feed("early", interval: 3600, fetched: 1800), now: now) < 1)
    }

    @Test("A feed that has been failing is not treated as more overdue for it")
    func backoffCounts() {
        // The backoff has already pushed its next fetch out. Measuring against
        // the interval alone would make a broken feed the most overdue thing
        // on the list and let it crowd out three hundred working ones.
        var failing = feed("failing", interval: 3600, fetched: 7200)
        failing.failureCount = 5
        let working = feed("working", interval: 3600, fetched: 7200)

        #expect(RefreshSchedule.lateness(failing, now: now) < RefreshSchedule.lateness(working, now: now))
    }

    /// **Nothing sets this today**, the background refusal having cost the
    /// notifications everything it saved : iOS calls every cellular interface
    /// expensive, so a pass that refused one asked no feed at all. It is the
    /// seat of the `Wi-Fi only` preference of section 8, and this pins the
    /// default a request carries until that preference exists.
    @Test("A request goes over a network the reader pays for unless it is told not to")
    func expensiveNetwork() {
        let asked = FetchRequest(url: URL(string: "https://feeds.example.com/f.xml")!)
        #expect(asked.isExpensiveNetworkAllowed)

        let withheld = FetchRequest(
            url: URL(string: "https://feeds.example.com/f.xml")!,
            isExpensiveNetworkAllowed: false
        )
        #expect(!withheld.isExpensiveNetworkAllowed)
    }
}
