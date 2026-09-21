//
//  PrivateCloudTests.swift
//  FlongTests
//
//  Created by François Rousselet on 21/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

/// Apple's own larger model, and everything about it that can be held to
/// account without asking it anything.
///
/// **The one thing these cannot walk is the request itself.** Apple gates the
/// model behind an entitlement granted on request, and without it the framework
/// does not throw, it calls `fatalError` on the first request. So the request
/// is the one step no test can take here, and everything leading to it is
/// walked instead : who is preferred, what is written down, what a failure
/// means, and above all that nothing is asked before the reader has agreed.
@Suite("Apple's own larger model")
struct PrivateCloudTests {
    private static func eligible(ready: Bool = true) -> PrivateCloudStanding {
        PrivateCloudStanding(pretending: PrivateCloudReading(isEligible: true, isReady: ready, reason: nil))
    }

    // MARK: - Who is preferred, and who is never preferred

    /// The promise this whole feature is held to : nothing leaves before the
    /// reader has said it may.
    @Test("Nothing is preferred before the reader has agreed")
    func nothingBeforeConsent() {
        var settings = ProviderSettings()
        #expect(settings.privateCloud == .unasked)

        for task in ModelTask.allCases {
            #expect(settings.choice(for: task, withPrivateCloud: true) == .onDevice)
        }

        settings.privateCloud = .declined
        for task in ModelTask.allCases {
            #expect(settings.choice(for: task, withPrivateCloud: true) == .onDevice)
        }
    }

    @Test("A task nobody pointed anywhere goes to Apple's model once it may")
    func anUnpointedTaskIsPreferred() {
        var settings = ProviderSettings()
        settings.privateCloud = .agreed

        for task in ModelTask.allCases {
            #expect(settings.choice(for: task, withPrivateCloud: true) == .privateCloud)
        }
    }

    /// The consent travels between devices and eligibility never does, so a
    /// device that cannot reach it goes on writing exactly as it did.
    @Test("A device that cannot reach it is unchanged by the consent")
    func anIneligibleDeviceIsUnchanged() {
        var settings = ProviderSettings()
        settings.privateCloud = .agreed

        for task in ModelTask.allCases {
            #expect(settings.choice(for: task, withPrivateCloud: false) == .onDevice)
        }
    }

    /// Consent moves what was never decided. It never overrides a decision.
    @Test("A task the reader put somewhere stays there")
    func adecisionIsNotOverridden() {
        var settings = ProviderSettings()
        settings.privateCloud = .agreed
        let account = UUID()

        settings = settings.pointing(.headlines, at: .onDevice)
        settings = settings.pointing(.subjects, at: .provider(account))
        settings = settings.pointing(.editions, at: .nothing)

        #expect(settings.choice(for: .headlines, withPrivateCloud: true) == .onDevice)
        #expect(settings.choice(for: .subjects, withPrivateCloud: true) == .provider(account))
        #expect(settings.choice(for: .editions, withPrivateCloud: true) == .nothing)
        // The one nobody spoke about.
        #expect(settings.choice(for: .search, withPrivateCloud: true) == .privateCloud)
    }

    // MARK: - What is written down, and what is not

    /// **Preferring it stores nothing**, which is what makes a device that has
    /// never heard of it safe : there is no word for it to fail to read.
    @Test("Pointing a task at it unpoints the task, and writes no new word")
    func pointingWritesNothing() throws {
        var settings = ProviderSettings()
        settings.privateCloud = .agreed
        settings = settings.pointing(.headlines, at: .onDevice)
        #expect(settings.choice(for: .headlines, withPrivateCloud: true) == .onDevice)

        settings = settings.pointing(.headlines, at: .privateCloud)
        #expect(settings.choice(for: .headlines, withPrivateCloud: true) == .privateCloud)

        let written = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        #expect(!written.contains("privateCloud\":{"))
        // The consent is a scalar an older build reads as a word it can ignore,
        // rather than a shape it cannot parse.
        #expect(written.contains("\"privateCloud\":\"agreed\""))
    }

    @Test("A blob written before the consent existed still reads")
    func anOlderBlobStillReads() throws {
        let older = #"{"accounts":[],"assignment":[],"sendsToProviders":true}"#
        let read = try JSONDecoder().decode(ProviderSettings.self, from: Data(older.utf8))

        #expect(read.privateCloud == .unasked)
        #expect(read.sendsToProviders)
        #expect(read.choice(for: .headlines, withPrivateCloud: true) == .onDevice)
    }

    // MARK: - What a failure means

    /// A limit says in so many words when to come back, so it is the model
    /// asking for a moment rather than the model being broken. Counted by the
    /// circuit breaker it would silence a month's wait in ten minutes.
    @Test("A quota that is spent is busy and never counts against the model")
    func aSpentQuotaIsBusy() {
        let comesBack = Date().addingTimeInterval(600)
        let fault = PrivateCloudProvider.fault(of: .quota(resetDate: comesBack))

        guard case .busy(let retryAfter) = fault else {
            Issue.record("A limit is the model asking for a moment")
            return
        }
        #expect(fault.isBusy)
        #expect(retryAfter.map { $0 > 0 && $0 <= 600 } == true)

        // And with no date, still busy and still counting towards nothing.
        #expect(PrivateCloudProvider.fault(of: .quota(resetDate: nil)).isBusy)
    }

    @Test("A network that is not there is the model itself")
    func aNetworkFailureIsTheModel() {
        for trouble: PrivateCloudTrouble in [.network, .unavailable] {
            let fault = PrivateCloudProvider.fault(of: trouble)
            #expect(fault == .unusable(.unreachable))
            #expect(fault.isTheModelItself)
            #expect(!fault.isBusy)
        }
    }

    /// Everything that is not its own family is read exactly as the device
    /// reads it, guardrails and decoding and the window alike.
    @Test("Anything else is read the way the device reads it")
    func anythingElseIsTheDevicesReading() {
        #expect(PrivateCloudProvider.fault(of: CancellationError()) == .unusable(.cancelled))
    }

    // MARK: - The rest a spent quota lays

    /// The circuit breaker counts a busy model towards nothing, which is right
    /// and must stay right, so something else has to stop a night's pass from
    /// putting five hundred round trips to a limit that is already reached.
    @Test("A spent quota rests until the system says it is back")
    func aSpentQuotaRests() {
        let standing = Self.eligible()
        let now = Date()
        #expect(standing.reading(now: now).isReady)

        standing.failed(.busy(retryAfter: 600), now: now)
        #expect(!standing.reading(now: now).isReady)
        #expect(standing.reading(now: now).reason == .limitReached)

        // And it comes back on its own rather than needing anything.
        #expect(standing.reading(now: now.addingTimeInterval(601)).isReady)
    }

    @Test("A limit that named no date rests for a quarter of an hour")
    func ablindRest() {
        let standing = Self.eligible()
        let now = Date()

        standing.failed(.busy(retryAfter: nil), now: now)
        #expect(!standing.reading(now: now.addingTimeInterval(60)).isReady)
        #expect(standing.reading(now: now.addingTimeInterval(PrivateCloudStanding.blindRest + 1)).isReady)
    }

    @Test("An answer proves the limit is behind us")
    func ananswerEndsTheRest() {
        let standing = Self.eligible()
        let now = Date()

        standing.failed(.busy(retryAfter: 600), now: now)
        #expect(!standing.reading(now: now).isReady)

        standing.answered()
        #expect(standing.reading(now: now).isReady)
    }

    /// A refusal is about the story, so it says nothing about the model and
    /// must not rest it.
    @Test("A story it would not write about rests nothing")
    func arefusalRestsNothing() {
        let standing = Self.eligible()
        let now = Date()

        standing.failed(.declined, now: now)
        standing.failed(.unreadable, now: now)
        standing.failed(.tooLong, now: now)
        #expect(standing.reading(now: now).isReady)
    }

    // MARK: - The two rungs

    @Test("The device writes where Apple's model is not ready")
    func thedeviceWritesWhenNotReady() {
        let provider = PrivateCloudProvider(
            task: .headlines,
            local: LocalProvider(),
            standing: Self.eligible(ready: false),
            log: nil
        )

        #expect(!provider.leavesTheDevice)
        // The second voice comes back with the device, since it is the device's
        // measured recovery against the device's own guardrails.
        #expect(provider.triesASecondVoice)
        #expect(provider.batch == LocalProvider().batch)
    }

    @Test("Nothing leaves while Apple's model is writing anything but a request")
    func whatLeavesIsSaidTruthfully() {
        let ready = PrivateCloudProvider(
            task: .headlines, local: LocalProvider(), standing: Self.eligible(), log: nil)

        #expect(ready.leavesTheDevice)
        // There is no address, and a fabricated one would be a lie in the one
        // record that exists to be checked.
        #expect(ready.host == nil)
        #expect(ready.identity == "private-cloud-compute")
        // Never the device's own, or a run of failures against Apple's servers
        // would silence the one path whose point is that it always works.
        #expect(ready.identity != LocalProvider().identity)
    }

    // MARK: - The gate that keeps this inert

    /// Until Apple grants the entitlement, no reading is ever eligible and no
    /// request is ever made. Without it the framework does not throw, it calls
    /// `fatalError`, so this is the difference between shipped and crashing.
    @Test("Without Apple's entitlement nothing is eligible and nothing is asked")
    func theEntitlementGateHolds() {
        guard !PrivateCloudStanding.isEntitled else {
            // The build carries it : then the gate is open, which is the whole
            // point, and this test has nothing to hold.
            return
        }

        let standing = PrivateCloudStanding()
        let reading = standing.reading

        #expect(!reading.isEligible)
        #expect(!reading.isReady)
        #expect(reading.reason == .notEntitled)

        // And a reader who agreed still gets the device, on every task.
        var settings = ProviderSettings()
        settings.privateCloud = .agreed
        for task in ModelTask.allCases {
            #expect(settings.choice(for: task, withPrivateCloud: reading.isEligible) == .onDevice)
        }
    }
}
