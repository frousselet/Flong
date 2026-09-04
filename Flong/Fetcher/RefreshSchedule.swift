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

import CryptoKit
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
    /// Doubling, and nothing random about it. It took a fresh
    /// `Double.random(in: 0.8...1.2)` on every call, which spread a thousand
    /// readers who had all failed during one outage and, in exchange, made a
    /// feed's next moment a different answer every time it was asked for : two
    /// evaluations a second apart disagreed by minutes, so nothing could sleep
    /// until the moment a feed became due, only poll for it.
    ///
    /// The spread is kept and comes from the device stagger below, which is
    /// derived from the feed and the installation rather than drawn afresh. It
    /// is now applied on the failure path too, where it used to be dropped :
    /// two devices of one reader backed off a failing publisher in lockstep.
    static func backoff(afterFailures failures: Int, jitter: Double = 1) -> TimeInterval {
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
        guard failures == 0 else {
            return date.addingTimeInterval(backoff(afterFailures: failures) + stagger)
        }
        return date.addingTimeInterval(min(max(interval, minimumInterval), maximumInterval) + stagger)
    }

    /// The interval this feed is held to : the reader's own if they set one,
    /// otherwise the rhythm the feed itself shows, otherwise an hour.
    static func interval(of feed: Feed) -> TimeInterval {
        feed.refreshInterval ?? feed.observedInterval ?? defaultInterval
    }

    /// The moment this feed is next worth asking, or `nil` where it is never
    /// worth asking again.
    ///
    /// **A moment rather than a yes or a no**, which is the whole of what lets
    /// the collection sleep until a feed is due instead of asking every five
    /// minutes whether one is. `.distantPast` is a feed nobody has ever
    /// fetched, which is due now and has been since it was subscribed to.
    ///
    /// It is a pure function of what the store holds, so two evaluations a
    /// second apart give the same answer, which is what a sleeping clock has to
    /// be able to rely on.
    static func due(_ feed: Feed, stagger: TimeInterval = 0) -> Date? {
        guard feed.quarantinedAt == nil else { return nil }
        guard let last = feed.lastFetchAt else { return .distantPast }
        return nextRefresh(after: last, interval: interval(of: feed), failures: feed.failureCount, stagger: stagger)
    }

    /// Whether a feed is due, taking the reader's own setting first.
    ///
    /// The same question as ``due(_:stagger:)`` asked of one moment, and asked
    /// through it so the two cannot come to disagree.
    static func isDue(_ feed: Feed, now: Date = Date(), stagger: TimeInterval = 0) -> Bool {
        guard let due = due(feed, stagger: stagger) else { return false }
        return now >= due
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

        let due = nextRefresh(
            after: last, interval: interval(of: feed), failures: feed.failureCount, stagger: stagger)
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
///
/// **Derived by a digest and not by `Hasher`**, which is the same mistake the
/// system index made and records. `Hasher` is seeded afresh in every process,
/// so the offset this claimed to derive was in fact drawn again at every
/// launch : a device landed on a different side of the interval every time it
/// started, two devices could still ask together, and a feed's next moment was
/// a different answer after every relaunch. Nothing can sleep until a moment
/// that moves when nothing about the feed has.
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
        var digest = SHA256()
        withUnsafeBytes(of: feedID.uuid) { digest.update(bufferPointer: $0) }
        withUnsafeBytes(of: device.uuid) { digest.update(bufferPointer: $0) }

        let bytes = Array(digest.finalize().prefix(8))
        let value = bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let fraction = Double(value % 1000) / 1000
        return interval / 3 * fraction
    }
}
