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
}
