//
//  SyncStatusTests.swift
//  FlongTests
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CloudKit
import Foundation
import Testing

@testable import Flong

@Suite("Synchronization failures")
struct SyncStatusTests {
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    private func error(_ code: CKError.Code, retryAfter: TimeInterval? = nil) -> CKError {
        var info: [String: Any] = [:]
        if let retryAfter { info[CKErrorRetryAfterKey] = retryAfter }
        return CKError(code, userInfo: info)
    }

    @Test("A full iCloud is the reader's to fix, and is said so")
    func quota() {
        #expect(SyncFailure.status(for: error(.quotaExceeded), now: now) == .quotaExceeded)
    }

    @Test("Rate limiting arrives under two names, and both are honoured")
    func rateLimiting() {
        // Section 7 : serviceUnavailable, code 6, is the frequent one in
        // practice, and treating only the documented name is how a client ends
        // up hammering a service that already told it to stop.
        let limited = SyncFailure.status(for: error(.requestRateLimited, retryAfter: 120), now: now)
        let unavailable = SyncFailure.status(for: error(.serviceUnavailable, retryAfter: 120), now: now)

        #expect(limited == .waiting(until: now.addingTimeInterval(120)))
        #expect(unavailable == .waiting(until: now.addingTimeInterval(120)))
        #expect(SyncFailure.isTransient(error(.requestRateLimited)))
        #expect(SyncFailure.isTransient(error(.serviceUnavailable)))
    }

    @Test("A service that names no moment is still waited for")
    func rateLimitingWithoutADate() {
        #expect(SyncFailure.status(for: error(.zoneBusy), now: now) == .waiting(until: nil))
        #expect(SyncFailure.retryDate(after: error(.serviceUnavailable), now: now) == nil)
    }

    @Test("No account is not a failure")
    func noAccount() {
        #expect(SyncFailure.status(for: error(.notAuthenticated), now: now) == .unavailable)
        #expect(SyncFailure.status(for: error(.managedAccountRestricted), now: now) == .unavailable)
        #expect(!SyncFailure.isTransient(error(.notAuthenticated)))
    }

    @Test("A network that is not there is waited for, not complained about")
    func network() {
        #expect(SyncFailure.status(for: error(.networkUnavailable), now: now) == .waiting(until: nil))
        #expect(SyncFailure.isTransient(error(.networkFailure)))
    }

    @Test("Anything else is reported as itself")
    func other() {
        let status = SyncFailure.status(for: error(.badContainer), now: now)

        guard case .failed(let reason) = status else {
            Issue.record("Expected a failure, got \(status)")
            return
        }
        #expect(reason.contains("\(CKError.Code.badContainer.rawValue)"))
    }
}
