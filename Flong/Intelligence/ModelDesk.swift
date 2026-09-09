//
//  ModelDesk.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Synchronization

/// Who answers which question, and how patient to be with each of them.
///
/// **The four things a model does here are four decisions and not one.** A
/// reader may want the sentence they type read on the device, where the answer
/// is instant and free, and the headlines over a night's stories written
/// somewhere better. Nothing in the four callers knows that : each asks the
/// desk for the hand that answers its own question, and what comes back is a
/// model, the patience that goes with it, and the rules for reading its
/// failures.
nonisolated final class ModelDesk: Sendable {
    /// The one every caller reaches by default.
    ///
    /// A default argument and never a reference inside a type : a test builds
    /// its own desk, and a test that reached for this one would be sharing a
    /// circuit breaker with every other test in the process.
    static let shared = ModelDesk()

    private let local: LocalProvider
    private let patiences: Mutex<[String: ModelPatience]>

    init(local: LocalProvider = LocalProvider()) {
        self.local = local
        self.patiences = Mutex([:])
    }

    /// The model that answers one question, with everything that goes with it.
    func hand(for task: ModelTask) -> ModelHand {
        let provider = self.provider(for: task)
        return ModelHand(task: task, provider: provider, patience: patience(with: provider.name))
    }

    /// Why one task will not be done, or nothing where it will.
    func absence(of task: ModelTask) -> LocalizedStringResource? {
        provider(for: task).absence
    }

    /// Forgets every run of failures, everywhere.
    ///
    /// Called when the reader comes back to the application and at the head of
    /// the full pass. Both are moments when what made a model fail an hour ago
    /// may well have changed, and neither costs anything if it has not.
    func reconsiderEverything() {
        patiences.withLock { patiences in
            for patience in patiences.values { patience.reconsider() }
        }
    }

    /// Which model answers a task.
    ///
    /// The one on the device, for all four, until a reader has said otherwise.
    private func provider(for task: ModelTask) -> any ModelProvider {
        local
    }

    /// One patience per model, made once and kept.
    ///
    /// Keyed by the model's own name, so two tasks pointed at one model share a
    /// circuit breaker : a model that has stopped answering has stopped
    /// answering both of them, and learning that twice would cost six failures
    /// rather than three.
    private func patience(with provider: String) -> ModelPatience {
        patiences.withLock { patiences in
            if let held = patiences[provider] { return held }
            let made = ModelPatience(with: provider)
            patiences[provider] = made
            return made
        }
    }
}

/// The model that answers one task, with the patience that goes with it.
nonisolated struct ModelHand: Sendable {
    let task: ModelTask
    let provider: any ModelProvider
    let patience: ModelPatience

    /// Whether it is worth asking at all.
    var isAvailable: Bool { provider.isAvailable && !patience.hasGivenUp() }

    var batch: Int { provider.batch }
    var triesASecondVoice: Bool { provider.triesASecondVoice }

    func writes(_ locale: Locale) -> Bool { provider.writes(locale) }

    func conversation(saying instructions: String) -> any ModelConversation {
        provider.conversation(saying: instructions)
    }

    /// One ask, with the patience and the triage already round it.
    ///
    /// **Every call site used to do the same four things by hand** : ask, say
    /// it worked, say it did not, and read what the failure meant about the
    /// thing it was shown. Eleven copies of four lines, and the copy that
    /// forgets to say it worked is how a good run still ends up giving up.
    func asking<A: ModelAnswer>(
        _ conversation: any ModelConversation,
        _ question: String,
        as type: A.Type = A.self,
        keeping budget: Int
    ) async -> Answered<A> {
        do {
            let answer = try await conversation.answer(to: question, as: type, keeping: budget)
            patience.succeeded()
            return .wrote(answer)
        } catch {
            patience.refused(error)
            return Answered(failing: error)
        }
    }
}
