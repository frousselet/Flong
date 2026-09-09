//
//  ModelPatience.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import OSLog
import Synchronization

/// How much failure one model is given before it is left alone for a while.
///
/// **One of these per provider, and it used to be one for the whole process.**
/// That was right while there was one model. With more than one it is wrong in
/// the way that matters : a key that expired at a service would silence the
/// model on the device as well, and a reader would lose their front page over
/// an account they could have fixed in a minute.
nonisolated final class ModelPatience: Sendable {
    /// How many refusals in a row before the model is left alone.
    ///
    /// It answers `available` and then fails on every call, which happens on a
    /// simulator and on a device where the assets are not there yet. Asking a
    /// fourth time costs a quarter of a second to learn what the third already
    /// said, and the digest is perfectly good without it.
    static let refusalsBeforeGivingUp = 3

    /// How long the model is left alone once it has been given up on.
    ///
    /// **A pause, and not the one-way latch it was.** Nothing cleared the count
    /// except a success, and no success is possible while every caller asks
    /// whether the model is available first : three failures and the model was
    /// off for the whole life of the process, which on a Mac is days. The
    /// reasons it fails are mostly temporary, and every one of them is a reason
    /// to try again later : assets still downloading, a reader switching Apple
    /// Intelligence on, a rate limit lifting, a card renewed.
    static let refusalPause: TimeInterval = 10 * 60

    /// Whose patience this is, for the log line and for nothing else.
    let provider: String

    /// The failures in a row, and when they added up to giving up.
    private nonisolated struct Refusals: Sendable {
        var count = 0
        var gaveUpAt: Date?
        /// The last thing that went wrong with the model itself, which is what
        /// a settings row says out loud : a key that expired must be visible
        /// rather than silently costing the reader the better half of a page.
        var lastFault: ModelFault?
    }

    private let refusals = Mutex(Refusals())

    init(with provider: String) {
        self.provider = provider
    }

    /// Whether the model is still being left alone after a run of failures.
    ///
    /// The pause expiring forgets the failures outright rather than allowing
    /// one more call : what follows is a fresh run of three, so a model that is
    /// genuinely broken is asked three times every ten minutes and no more.
    func hasGivenUp(now: Date = Date()) -> Bool {
        refusals.withLock { refusals in
            guard let gaveUpAt = refusals.gaveUpAt else { return false }
            guard now.timeIntervalSince(gaveUpAt) < Self.refusalPause else {
                refusals = Refusals()
                return false
            }
            return true
        }
    }

    /// What went wrong last, where anything did.
    var trouble: ModelFault? {
        refusals.withLock { $0.lastFault }
    }

    func succeeded() {
        refusals.withLock { $0 = Refusals() }
    }

    /// Records a failure, and says so once rather than once per story.
    ///
    /// A model that will not write about one story is not a model that has
    /// stopped working, and only the second is worth giving up on.
    ///
    /// **Nor is a model that is merely busy.** A rate limit and a clash of
    /// concurrent requests are the system saying to come back, which is the
    /// opposite of a reason to stop coming back. They still stop this
    /// particular call, so nothing is stamped as answered, and they count
    /// towards nothing : a background pass is rate-limited hard, and three of
    /// those used to silence the model for the rest of the process, which is
    /// how a night of writing headlines ended with no subjects filed.
    func refused(_ fault: ModelFault, now: Date = Date()) {
        let kind = LocalProvider.kind(of: fault)

        guard fault.isTheModelItself else {
            Log.enrich.notice(
                "\(self.provider, privacy: .public) would not write about one story : \(kind, privacy: .public)")
            return
        }
        guard !fault.isBusy else {
            Log.enrich.info("\(self.provider, privacy: .public) is busy : \(kind, privacy: .public)")
            return
        }

        let count = refusals.withLock { refusals -> Int in
            refusals.lastFault = fault
            refusals.count += 1
            if refusals.count == Self.refusalsBeforeGivingUp { refusals.gaveUpAt = now }
            return refusals.count
        }
        guard count == Self.refusalsBeforeGivingUp else { return }
        Log.enrich.notice(
            "\(self.provider, privacy: .public) failed \(count) times and is left alone for a while : \(kind, privacy: .public)"
        )
    }

    /// Forgets the refusals, for the next launch or a deliberate retry.
    ///
    /// Called when the reader comes back to the application and at the head of
    /// the full pass. Both are moments when what made the model fail an hour
    /// ago may well have changed, and neither costs anything if it has not :
    /// the count simply builds again.
    func reconsider() {
        refusals.withLock { $0 = Refusals() }
    }
}
