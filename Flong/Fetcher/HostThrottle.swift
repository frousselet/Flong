//
//  HostThrottle.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Spaces out the requests Flong makes to one server.
///
/// The bucket is per host name and not per feed, as section 8 of the
/// specification requires : a reader following forty feeds on one platform would
/// otherwise hit it forty times at once, which is indistinguishable from an
/// attack and gets the application blocked rather than the feeds refreshed.
///
/// Nothing sleeps in here. The throttle hands out a moment, the caller waits for
/// it, so one slow host never holds up the others.
actor HostThrottle {
    /// The least time between two requests to the same host.
    private let interval: TimeInterval
    /// How many requests may go at once after a quiet spell.
    private let burst: Int

    private var nextRequest: [String: Date] = [:]
    private var pausedUntil: [String: Date] = [:]

    init(interval: TimeInterval = 1, burst: Int = 4) {
        self.interval = interval
        self.burst = burst
    }

    /// Reserves the next slot for a host, and says how long to wait for it.
    func wait(forHost host: String, now: Date = Date()) -> TimeInterval {
        // The reservation runs on a clock of its own, which is allowed to lag
        // behind the real one by exactly one burst. That lag is the credit a
        // host builds up while it is left alone, and capping it is what stops a
        // reader who was away for a week from coming back with a thousand
        // simultaneous requests.
        let earliest = now.addingTimeInterval(-interval * Double(burst - 1))
        var next = max(nextRequest[host] ?? earliest, earliest)
        if let paused = pausedUntil[host] { next = max(next, paused) }

        nextRequest[host] = next.addingTimeInterval(interval)
        return max(0, next.timeIntervalSince(now))
    }

    /// Holds every request to a host until a moment the server named.
    ///
    /// This is what `Retry-After` means, and honouring it is the difference
    /// between a client a publisher tolerates and one they block.
    func pause(host: String, until date: Date) {
        pausedUntil[host] = max(pausedUntil[host] ?? .distantPast, date)
    }

    /// When a host may next be asked for anything, for tests and diagnostics.
    func pause(forHost host: String) -> Date? {
        pausedUntil[host]
    }
}
