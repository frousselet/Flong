//
//  PrivateCloudProvider.swift
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

/// What Private Cloud Compute's own failures mean, said in a form this
/// deployment target can name.
///
/// **The judgement is here and the framework's types are not**, so the mapping
/// is a pure function a test can walk on iOS 26, which is the system the tests
/// run on.
nonisolated enum PrivateCloudTrouble: Hashable, Sendable {
    case network
    case quota(resetDate: Date?)
    case unavailable
}

/// Apple's own larger model, as one provider among the ones a reader may point
/// a task at.
///
/// **Two rungs and not one.** ``ModelDesk/hand(for:)`` is a default argument
/// evaluated once per job and held for a whole pass, and a hand that answers
/// `isAvailable == false` costs a story its written headline rather than
/// handing it to the device. So the fallback lives here and in the
/// conversation, where it is decided per story and per turn.
nonisolated struct PrivateCloudProvider: ModelProvider {
    /// Not an account, and never one. There is nothing for the reader to
    /// configure, so the log's column carries a constant rather than an
    /// identifier pointing at nothing.
    static let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    let task: ModelTask
    let local: LocalProvider
    let standing: PrivateCloudStanding
    let log: ProviderCallLog?

    init(task: ModelTask, local: LocalProvider, standing: PrivateCloudStanding, log: ProviderCallLog?) {
        self.task = task
        self.local = local
        self.standing = standing
        self.log = log
    }

    /// Not translated : Apple does not translate it, and it goes into a log row
    /// and onto the record of what wrote a headline.
    let name = "Private Cloud Compute"

    /// Never `apple-intelligence`. ``ModelDesk`` keys the circuit breaker on
    /// this, and sharing it would mean a run of failures against Apple's
    /// servers silencing the model on the device, on the one path whose whole
    /// point is that it always works.
    let identity = "private-cloud-compute"

    /// **Nothing, and it is not a host.** There is no address a reader could
    /// check, and a fabricated one would be a lie in the one record that exists
    /// to be checked. That this leaves the device is said by
    /// ``leavesTheDevice`` instead.
    let host: String? = nil

    /// True where either rung will answer, and it has to be : a story whose
    /// hand is unavailable keeps its own article's headline rather than being
    /// written by the device.
    var isAvailable: Bool { standing.reading.isReady || local.isAvailable }

    /// Nothing where either rung will write, so a front page is never promised
    /// an edition that does not come and never warned off one that does.
    var absence: LocalizedStringResource? { standing.reading.isReady ? nil : local.absence }

    /// Whether what is asked is about to leave this device.
    ///
    /// Read rather than declared, because it changes : the same provider writes
    /// at a distance when the model is ready and on the device when it is not,
    /// and a consent that said one thing while the other happened would be a
    /// defective consent.
    var leavesTheDevice: Bool { standing.reading.isReady }

    /// One at a time where a call is a round trip, three where it is a tenth of
    /// a second.
    var batch: Int { standing.reading.isReady ? 1 : local.batch }

    /// **False where Apple's larger model is answering, and the device's own
    /// answer where it is not.** The second voice is a measured recovery
    /// against the guardrails on this device ; Private Cloud Compute exposes no
    /// guardrails parameter at all and its refusals have not been measured, and
    /// a second call spends a quota shared with everything else the reader
    /// uses. `docs/technical/digest.md` records that this is unmeasured rather
    /// than settled.
    var triesASecondVoice: Bool { standing.reading.isReady ? false : local.triesASecondVoice }

    /// The device's answer, which is a floor rather than a dodge : this gates
    /// the check on the answer rather than whether to ask, and a larger model's
    /// languages are at least the smaller one's. `supportsLocale` is
    /// `async throws` on that model and this member is neither.
    func writes(_ locale: Locale) -> Bool { local.writes(locale) }

    func conversation(saying instructions: String) -> any ModelConversation {
        guard #available(iOS 27.0, macOS 27.0, *), standing.reading.isReady else {
            return local.conversation(saying: instructions)
        }
        return PrivateCloudConversation(
            instructions: instructions,
            task: task,
            local: local,
            standing: standing,
            log: log
        )
    }

    // MARK: - What a failure means

    /// What one of its own failures means. The mapping, and not the reading.
    static func fault(of trouble: PrivateCloudTrouble) -> ModelFault {
        switch trouble {
        case .quota(let resetDate):
            // Busy, exactly as a rate limit already is : a limit says in so
            // many words when to come back, and ``ModelPatience`` must count it
            // towards nothing. What stops the asking is the rest laid on
            // ``PrivateCloudStanding``, which is a different instrument for a
            // different reason.
            .busy(retryAfter: resetDate.map { max(0, $0.timeIntervalSinceNow) })
        case .network, .unavailable:
            .unusable(.unreachable)
        }
    }

    /// Its own family, or nothing where the error is none of them.
    @available(iOS 27.0, macOS 27.0, *)
    static func trouble(of error: Error) -> PrivateCloudTrouble? {
        guard let error = error as? PrivateCloudComputeLanguageModel.Error else { return nil }
        switch error {
        case .quotaLimitReached(let reached): return .quota(resetDate: reached.resetDate)
        case .networkFailure: return .network
        case .serviceUnavailable: return .unavailable
        // A failure a later system adds is still its failure and still not the
        // story's, so it drops the rung rather than stamping the article.
        @unknown default: return .unavailable
        }
    }

    /// Its own family first, then the device's reading of everything else.
    ///
    /// **Without the first half every quota limit reads as the model being
    /// broken.** ``LocalProvider/fault(of:)`` ends by answering
    /// `.unusable(.unreachable)` to anything it does not recognize, and three
    /// of those leave the model alone for ten minutes over a wait that may be a
    /// month. The delegation is not laziness : a session over this model throws
    /// `LanguageModelError`, `GeneratedContent.ParsingError` and
    /// `LanguageModelSession.Error` too, for guardrails, decoding and the
    /// window, and the device already reads all three correctly.
    static func fault(of error: Error) -> ModelFault {
        if #available(iOS 27.0, macOS 27.0, *), let trouble = trouble(of: error) {
            return fault(of: trouble)
        }
        return LocalProvider.fault(of: error)
    }
}
