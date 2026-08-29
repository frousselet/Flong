//
//  SyncStatus.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CloudKit
import Foundation

/// What synchronization is doing, in terms a reader can act on.
nonisolated enum SyncStatus: Hashable, Sendable {
    /// No iCloud account, which is not an error : section 3 says Flong works
    /// perfectly well on one device without one.
    case unavailable
    case idle(lastSynchronized: Date?)
    case working
    /// The reader's iCloud storage is full, and only they can fix it.
    case quotaExceeded
    /// The service asked to be left alone, or could not be reached.
    case waiting(until: Date?)
    case failed(reason: String)
}

/// How CloudKit's answers map onto that.
///
/// Rate limiting does not always arrive as `requestRateLimited` : section 7 of
/// the specification names `serviceUnavailable`, code 6, as the frequent case in
/// practice, and both carry the moment to come back in `CKErrorRetryAfterKey`.
/// Treating only the documented one is how a client ends up hammering a service
/// that already told it to stop.
nonisolated enum SyncFailure {
    static func status(for error: any Error, now: Date = Date()) -> SyncStatus {
        guard let error = error as? CKError else {
            return .failed(reason: String(describing: type(of: error)))
        }

        switch error.code {
        case .quotaExceeded:
            return .quotaExceeded

        case .requestRateLimited, .serviceUnavailable, .zoneBusy:
            return .waiting(until: retryDate(after: error, now: now))

        case .networkUnavailable, .networkFailure:
            return .waiting(until: nil)

        case .notAuthenticated, .accountTemporarilyUnavailable, .managedAccountRestricted:
            return .unavailable

        default:
            return .failed(reason: "CloudKit error \(error.errorCode)")
        }
    }

    /// When the service said to come back, when it said anything.
    static func retryDate(after error: CKError, now: Date = Date()) -> Date? {
        guard let seconds = error.retryAfterSeconds else { return nil }
        return now.addingTimeInterval(seconds)
    }

    /// Whether the answer means "later", rather than "no".
    static func isTransient(_ error: any Error) -> Bool {
        guard let error = error as? CKError else { return false }

        switch error.code {
        case .requestRateLimited, .serviceUnavailable, .zoneBusy, .networkUnavailable, .networkFailure,
            .serverResponseLost, .internalError:
            return true
        default:
            return false
        }
    }
}
