//
//  PrivateCloudConversation.swift
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

/// An exchange with Apple's own larger model, with this device behind it.
///
/// **The rung drops on the model and never on the story.** A refusal is about
/// what the model was shown, and the caller's own second voice is what answers
/// that ; a quota, a network failure or a service that is down says nothing
/// about the story, and those hand the same question to the device inside the
/// same call, so a story is never left wearing its own article's headline over
/// something that was not about it.
///
/// **A conversation that drops a rung starts the device's exchange fresh.** The
/// two models keep their own transcripts and there is no carrying one across,
/// so what the device is put is the question and not the thread. It happens at
/// most once per exchange and only after a failure.
@available(iOS 27.0, macOS 27.0, *)
nonisolated final class PrivateCloudConversation: ModelConversation {
    private let instructions: String
    private let task: ModelTask
    private let local: LocalProvider
    private let standing: PrivateCloudStanding
    private let log: ProviderCallLog?
    private let session: LanguageModelSession

    /// Whether the exchange has already come back to the device.
    private var fallen = false
    private var device: (any ModelConversation)?

    /// What the model said the transcript cost, once it has said. A fact where
    /// there is one and an estimate until then, exactly as the cloud path does.
    private var spent: Int?
    private var asked = 0
    private var turns = 0

    init(
        instructions: String,
        task: ModelTask,
        local: LocalProvider,
        standing: PrivateCloudStanding,
        log: ProviderCallLog?
    ) {
        self.instructions = instructions
        self.task = task
        self.local = local
        self.standing = standing
        self.log = log
        self.session = LanguageModelSession(
            model: PrivateCloudComputeLanguageModel(),
            instructions: instructions
        )
    }

    /// Nothing. A warming request to a model at a distance buys nothing
    /// measured here and may spend a quota. An exchange that was always going
    /// to be the device's never gets this far : the provider hands back a
    /// `LocalConversation`, which prewarms as it always did.
    func prewarm() {}

    /// **Estimated, never measured, and the reason is the framework.**
    /// `tokenCount(for:)` is a `SystemLanguageModel` member and this model has
    /// none ; its own `contextSize` is `async throws` and what a read of it
    /// costs is not documented, so it is not called per question. The window is
    /// the one the cloud path already assumes, which is conservative for a
    /// larger model, and from the second turn on the real figure arrives free
    /// on the answer.
    func hasRoom(for question: String, keeping budget: Int) async -> Bool {
        if fallen { return await onTheDevice().hasRoom(for: question, keeping: budget) }
        guard turns < CloudConversation.mostTurns else { return false }

        let already = spent ?? CloudConversation.estimate(instructions) + asked
        return already + CloudConversation.estimate(question) + budget < CloudConversation.assumedWindow
    }

    func answer(to question: String, shaped: ResponseShape, keeping budget: Int) async throws(ModelFault) -> Answer {
        guard !fallen, standing.reading.isReady else {
            return try await onTheDevice().answer(to: question, shaped: shaped, keeping: budget)
        }
        // Built before the question is put, and its failure is neither the
        // model's nor this story's.
        guard let schema = try? shaped.schema() else {
            Log.enrich.error("A shape would not build into a schema : \(shaped.name, privacy: .public)")
            throw .unusable(.misconfigured)
        }

        asked += CloudConversation.estimate(question)
        turns += 1
        let started = Date()

        do {
            let response = try await session.respond(
                to: question,
                schema: schema,
                options: LocalProvider.options(maximumTokens: budget)
            )
            let prompt = response.usage.input.totalTokenCount
            let written = response.usage.output.totalTokenCount
            spent = prompt + written
            standing.answered()
            await record(.answered, from: started, prompt: prompt, answer: written)
            return Answer(response.content)
        } catch {
            let fault = PrivateCloudProvider.fault(of: error)
            await record(.failed(fault), from: started, prompt: nil, answer: nil)
            standing.failed(fault)

            // The reader left. Nothing stands in for that.
            if case .unusable(.cancelled) = fault { throw fault }
            // About the story and not the model : the caller's own second voice
            // is what answers a refusal, and a cross-model retry is machinery
            // nothing here has measured.
            guard fault.isTheModelItself else { throw fault }

            fallen = true
            return try await onTheDevice().answer(to: question, shaped: shaped, keeping: budget)
        }
    }

    /// The device's exchange, opened once and kept for the rest of this one.
    private func onTheDevice() -> any ModelConversation {
        if let device { return device }
        let opened = local.conversation(saying: instructions)
        device = opened
        return opened
    }

    /// One row per request that actually left, and only for that rung : a
    /// question the device answered is not something that was sent away, and a
    /// log that said otherwise would be worse than no log.
    private func record(
        _ outcome: ProviderCallOutcome,
        from started: Date,
        prompt: Int?,
        answer: Int?
    ) async {
        guard let log else { return }

        let call = ProviderCall(
            startedAt: started,
            providerID: PrivateCloudProvider.identifier,
            providerName: "Private Cloud Compute",
            kind: .privateCloudCompute,
            // No host : there is no address, and inventing one would put a lie
            // in the one record that exists to be checked.
            host: "",
            task: task,
            // The framework names no model.
            model: "",
            outcome: outcome,
            promptTokens: prompt,
            answerTokens: answer,
            duration: Date().timeIntervalSince(started),
            // No HTTP status, there being no HTTP.
            status: nil
        )
        try? await log.write(call)
    }
}
