//
//  PrivateCloudStanding.swift
//  Flong
//
//  Created by François Rousselet on 21/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import FoundationModels
import OSLog
import Synchronization

/// What the system last said about Apple's own larger model.
///
/// **A plain value this deployment target can name.** Nothing in it is an
/// iOS 27 type, so it crosses the availability guard and everything downstream
/// reads a boolean rather than asking the framework. A screen that asked the
/// framework directly would need `#available` in a `body`, which is how a view
/// ends up with two versions of itself.
nonisolated struct PrivateCloudReading: Hashable, Sendable {
    nonisolated enum Reason: Hashable, Sendable {
        /// The system is older than the model.
        case notThisSystem
        /// This build does not carry Apple's entitlement, so it may not ask.
        case notEntitled
        case deviceNotEligible
        case systemNotReady
        case limitReached
        case unreachable
    }

    /// Whether this device could ever reach it : a system new enough, a build
    /// allowed to ask, and a device Apple says is eligible.
    ///
    /// A fact that changes with the hardware and the system rather than with
    /// the hour, which is why the picker reads this one : a quota that runs out
    /// at three in the morning must not rewrite on screen the answer the reader
    /// gave.
    var isEligible = false

    /// Whether it would answer right now. The quota and any rest are in it.
    var isReady = false

    var reason: Reason? = .notThisSystem
    var isApproachingLimit = false

    /// When the quota comes back, where the system said so.
    var resetDate: Date?

    /// Whether Apple offers a way of asking for a higher limit.
    var canAskForMore = false

    /// When this was taken. `distantPast` where it never was.
    var checkedAt = Date.distantPast
}

/// Where Apple's own larger model stands, held rather than asked.
///
/// **Asked once and held, because the answer is not free and not momentary.**
/// A reading is taken when the application comes forward, at the head of a
/// pass, and when the reader opens the models screen. Nothing takes one per
/// story and nothing takes one from a `body`.
nonisolated final class PrivateCloudStanding: Sendable {
    /// Whether this build may speak to Apple's larger model at all.
    ///
    /// **A constant, because there is nothing to ask.** Apple gates the model
    /// behind a managed entitlement, `com.apple.developer.private-cloud-compute`,
    /// granted on request rather than declared. Without it the framework does
    /// not throw : it calls `fatalError` on the first request, so there is no
    /// catching it and no probing for it. `availability` answers `available`
    /// all the same and `contextSize` answers a real number, so nothing the
    /// framework says can be used to tell whether asking is safe. Measured on
    /// iOS 27.0 rather than read anywhere.
    ///
    /// So the question is answered at build time and in one place. Turning it
    /// on is two deliberate steps once Apple has granted the request : add
    /// `com.apple.developer.private-cloud-compute` to `Config/Flong.entitlements`,
    /// and add `FLONG_PRIVATE_CLOUD` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS`.
    /// Until both are done every reading is `.notEntitled`, nothing is ever
    /// ready, and no request is ever made.
    static var isEntitled: Bool {
        #if FLONG_PRIVATE_CLOUD
            true
        #else
            false
        #endif
    }

    /// How long a rest lasts where the system did not say when the quota comes
    /// back.
    static let blindRest: TimeInterval = 15 * 60

    private struct Held {
        var reading: PrivateCloudReading?
        var restsUntil: Date?
    }

    private let held: Mutex<Held>

    /// A reading given rather than taken, which is the only way a test running
    /// on iOS 26 can walk both sides of the ladder.
    private let pretended: PrivateCloudReading?

    init() {
        self.held = Mutex(Held())
        self.pretended = nil
    }

    init(pretending reading: PrivateCloudReading) {
        self.held = Mutex(Held())
        self.pretended = reading
    }

    /// What the system last said, taking a first reading where none has been
    /// taken, and with any rest laid over it.
    var reading: PrivateCloudReading { reading(now: Date()) }

    func reading(now: Date) -> PrivateCloudReading {
        held.withLock { held in
            var reading = held.reading ?? pretended ?? Self.take(now: now)
            held.reading = reading

            // A rest is the quota's and not the model's : the reading itself is
            // whatever it was, and this lays the wait over it without losing
            // why it was laid.
            if let until = held.restsUntil {
                if now < until {
                    reading.isReady = false
                    if reading.reason == nil { reading.reason = .limitReached }
                    reading.resetDate = reading.resetDate ?? until
                } else {
                    held.restsUntil = nil
                }
            }
            return reading
        }
    }

    /// Asks the system again, at the three moments the answer can change.
    func refresh(now: Date = Date()) {
        guard pretended == nil else { return }
        let taken = Self.take(now: now)
        held.withLock { $0.reading = taken }
    }

    /// Records that it would not answer, and stops the asking where that is
    /// what the failure means.
    ///
    /// **The quota needs a mechanism of its own, and ``ModelPatience`` is the
    /// wrong one.** A `.busy` counts towards nothing there, which is right and
    /// must stay right, a background pass being rate-limited hard enough that
    /// three of those once silenced the model for a whole night. But it means
    /// nothing would ever stop the asking, and a pass over five hundred stories
    /// would put five hundred round trips to a limit that is already reached.
    /// So the same failure lays a rest here, until the system's own date or for
    /// a quarter of an hour where it named none.
    func failed(_ fault: ModelFault, now: Date = Date()) {
        switch fault {
        case .busy(let retryAfter):
            // A date already past is no date at all : floored to zero it would
            // defeat the fallback below and lay a rest the next read lifts.
            let waiting = retryAfter.flatMap { $0 > 0 ? $0 : nil } ?? Self.blindRest
            rest(until: now.addingTimeInterval(waiting))
        case .unusable(.cancelled):
            // The reader left. That says nothing about anything.
            return
        case .unusable:
            // **A network that is not there needs a rest as much as a spent
            // quota does, and used to get none.** The conversation answers from
            // the device and returns normally, so the call counts as a success
            // and ``ModelPatience`` never sees the failure ; nothing else
            // watches. A pass over five hundred stories then paid five hundred
            // timeouts before the device wrote, every one of them a row in the
            // reader's own log. Both brakes were unreachable and this is the
            // one that can reach.
            rest(until: now.addingTimeInterval(Self.blindRest))
        case .declined, .unreadable, .tooLong:
            // About the story it was shown, which says nothing about the model.
            return
        }
    }

    private func rest(until: Date) {
        held.withLock { $0.restsUntil = until }
        Log.enrich.notice("Private Cloud Compute is resting, and this device is writing meanwhile")
    }

    /// Forgets any rest, an answer being proof the limit is behind us.
    func answered() {
        held.withLock { $0.restsUntil = nil }
    }

    /// The same, for the head of a pass and the reader coming back.
    func reconsider() {
        held.withLock { $0.restsUntil = nil }
        refresh()
    }

    /// Opens Apple's own way of asking for a higher limit, where there is one.
    ///
    /// It presents an interface, so it is called from the main actor : the only
    /// caller is a button.
    @MainActor
    func askForAHigherLimit() {
        guard #available(iOS 27.0, macOS 27.0, *), Self.isEntitled else { return }
        PrivateCloudComputeLanguageModel().quotaUsage.limitIncreaseSuggestion?.show()
    }

    /// One reading of the system, and the one place `#available` is written.
    private static func take(now: Date) -> PrivateCloudReading {
        guard isEntitled else {
            return PrivateCloudReading(reason: .notEntitled, checkedAt: now)
        }
        guard #available(iOS 27.0, macOS 27.0, *) else {
            return PrivateCloudReading(reason: .notThisSystem, checkedAt: now)
        }

        let model = PrivateCloudComputeLanguageModel()
        let quota = model.quotaUsage

        var reading = PrivateCloudReading(checkedAt: now)
        reading.resetDate = quota.resetDate
        reading.canAskForMore = quota.limitIncreaseSuggestion != nil
        if case .belowLimit(let below) = quota.status { reading.isApproachingLimit = below.isApproachingLimit }

        switch model.availability {
        case .available:
            reading.isEligible = true
            reading.isReady = !quota.isLimitReached
            reading.reason = quota.isLimitReached ? .limitReached : nil
        case .unavailable(let why):
            switch why {
            case .systemNotReady:
                // Eligible and not ready : the picker goes on saying what the
                // reader chose, and a line under it says who is writing.
                reading.isEligible = true
                reading.reason = .systemNotReady
            case .deviceNotEligible:
                reading.reason = .deviceNotEligible
            @unknown default:
                reading.reason = .unreachable
            }
        }
        return reading
    }
}
