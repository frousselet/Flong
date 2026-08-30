//
//  RefreshSchedule.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Decides when a feed is worth asking again.
///
/// A feed that publishes twice a day is asked twice a day. Section 8 of the
/// specification derives the interval from the gaps the feed itself shows,
/// bounded so that neither a firehose nor an abandoned blog can push it to an
/// absurd rate.
nonisolated enum RefreshSchedule {
    static let minimumInterval: TimeInterval = 15 * 60
    static let maximumInterval: TimeInterval = 24 * 60 * 60
    static let defaultInterval: TimeInterval = 60 * 60

    /// The interval a feed's own publication history suggests.
    ///
    /// The median, not the mean : one burst of ten posts in an afternoon would
    /// otherwise convince the reader that the feed publishes every four minutes
    /// for ever.
    static func observedInterval(from dates: [Date]) -> TimeInterval? {
        let sorted = dates.sorted()
        guard sorted.count >= 3 else { return nil }

        let gaps = zip(sorted.dropFirst(), sorted).map { $0.timeIntervalSince($1) }.filter { $0 > 0 }
        guard !gaps.isEmpty else { return nil }

        let ordered = gaps.sorted()
        let middle = ordered.count / 2
        let median = ordered.count.isMultiple(of: 2) ? (ordered[middle - 1] + ordered[middle]) / 2 : ordered[middle]

        return min(max(median, minimumInterval), maximumInterval)
    }

    /// How long to wait before asking again after a failure.
    ///
    /// Doubling, with jitter so that a thousand readers who all failed during
    /// one outage do not come back in the same second.
    static func backoff(afterFailures failures: Int, jitter: Double = Double.random(in: 0.8...1.2)) -> TimeInterval {
        guard failures > 0 else { return 0 }
        let doubled = minimumInterval * pow(2, Double(min(failures, 6) - 1))
        return min(doubled * jitter, maximumInterval)
    }

    /// When a feed should next be asked for.
    ///
    /// The stagger keeps a reader's several devices from asking together : they
    /// would multiply the traffic reaching a publisher by the number of devices
    /// on the account, for no benefit at all.
    static func nextRefresh(
        after date: Date,
        interval: TimeInterval,
        failures: Int = 0,
        stagger: TimeInterval = 0
    ) -> Date {
        guard failures == 0 else { return date.addingTimeInterval(backoff(afterFailures: failures)) }
        return date.addingTimeInterval(min(max(interval, minimumInterval), maximumInterval) + stagger)
    }

    /// Whether a feed is due, taking the reader's own setting first.
    static func isDue(_ feed: Feed, now: Date = Date(), stagger: TimeInterval = 0) -> Bool {
        guard feed.quarantinedAt == nil else { return false }
        guard let last = feed.lastFetchAt else { return true }

        let interval = feed.refreshInterval ?? feed.observedInterval ?? defaultInterval
        return now >= nextRefresh(after: last, interval: interval, failures: feed.failureCount, stagger: stagger)
    }

    /// How overdue a feed is, as a share of its own interval.
    ///
    /// **Relative, and not in seconds.** A daily feed an hour late and an
    /// hourly feed an hour late are both an hour late, and only one of them has
    /// anything new. Measured against its own rhythm, the hourly one is a whole
    /// interval overdue and the daily one a twenty-fourth of one, which is the
    /// order the two should be asked in.
    ///
    /// One means exactly due. Below one is not due at all ; a feed nobody has
    /// ever fetched is the most overdue thing there is and comes first.
    static func lateness(_ feed: Feed, now: Date = Date(), stagger: TimeInterval = 0) -> Double {
        guard let last = feed.lastFetchAt else { return .greatestFiniteMagnitude }

        let interval = feed.refreshInterval ?? feed.observedInterval ?? defaultInterval
        let due = nextRefresh(after: last, interval: interval, failures: feed.failureCount, stagger: stagger)
        let waited = now.timeIntervalSince(last)
        let owed = due.timeIntervalSince(last)

        guard owed > 0 else { return .greatestFiniteMagnitude }
        return waited / owed
    }
}

/// Spreads a reader's devices apart in time.
///
/// The offset is derived rather than random, so one device always lands on the
/// same side of the interval and a feed is not asked twice in a row by the same
/// machine.
nonisolated enum DeviceStagger {
    private static let key = "flong.device-identifier"

    /// A stable identifier for this installation. It identifies nothing about
    /// the reader and never leaves the device.
    static func deviceIdentifier(in defaults: UserDefaults = .standard) -> UUID {
        if let stored = defaults.string(forKey: key), let identifier = UUID(uuidString: stored) {
            return identifier
        }
        let identifier = UUID()
        defaults.set(identifier.uuidString, forKey: key)
        return identifier
    }

    /// A share of the interval, between zero and a third of it.
    static func offset(for feedID: UUID, interval: TimeInterval, device: UUID) -> TimeInterval {
        var hasher = Hasher()
        hasher.combine(feedID)
        hasher.combine(device)

        let fraction = Double(UInt64(bitPattern: Int64(hasher.finalize())) % 1000) / 1000
        return interval / 3 * fraction
    }
}
