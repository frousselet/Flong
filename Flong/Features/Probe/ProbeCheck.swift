//
//  ProbeCheck.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// One endpoint exercised against a live instance, and what came back.
nonisolated struct ProbeCheck: Identifiable, Sendable, Equatable {
    enum Outcome: Sendable, Equatable {
        case pending
        case running
        case passed(String)
        case failed(String)
        case skipped
    }

    let id: String
    let title: LocalizedStringResource
    /// The call being made, shown so a failure can be reproduced by hand.
    let endpoint: String
    var outcome: Outcome = .pending

    var isFailure: Bool {
        if case .failed = outcome { return true }
        return false
    }
}
