//
//  LocalConversation.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import FoundationModels
import OSLog

/// An exchange with the model on this device.
///
/// The session does the remembering, which is most of what this is for : a
/// headline asked for again has to be asked of a model that can see the one it
/// just wrote, and a standfirst asked for third has to be asked with everything
/// already said still in front of it.
nonisolated final class LocalConversation: ModelConversation {
    private let model: SystemLanguageModel
    private let session: LanguageModelSession

    init(model: SystemLanguageModel, instructions: String) {
        self.model = model
        self.session = LanguageModelSession(model: model, instructions: instructions)
    }

    /// Free, and the one place it buys anything : the assets load while the
    /// prompt is being measured, which is a real await rather than a wait
    /// invented to give this something to overlap with.
    func prewarm() {
        session.prewarm()
    }

    /// Whether one more question fits beside everything already said.
    ///
    /// **The transcript and the question, and it used to be one or the other.**
    /// A fresh session was measured on its prompt alone and a session already
    /// under way on its transcript alone, which meant the first measurement
    /// quietly ignored the instructions and the second quietly ignored the
    /// question. Measuring both is slightly more prudent than either, and the
    /// budgets it is compared against are documented as generous on purpose.
    ///
    /// Counting them exactly needs a system a little newer than the one Flong
    /// requires. Where it is not there, the prompt is already bounded by what
    /// goes into it : six articles and two hundred and forty characters each.
    func hasRoom(for question: String, keeping budget: Int) async -> Bool {
        guard #available(iOS 26.4, macOS 26.4, *) else { return true }

        do {
            let spent = try await model.tokenCount(for: session.transcript)
            let asked = try await model.tokenCount(for: question)
            return spent + asked + budget < model.contextSize
        } catch {
            // Not being able to measure is not a reason to refuse to ask : the
            // cost of asking anyway is one refusal, and the cost of not asking
            // is a story that never gets a headline.
            Log.enrich.debug("The window could not be measured, so the question was put anyway")
            return true
        }
    }

    func answer(to question: String, shaped: ResponseShape, keeping budget: Int) async throws(ModelFault) -> Answer {
        // Built before the question is put, and its failure is neither the
        // model's nor this story's : a shape that will not build is a mistake
        // here, and it used to be thrown where anything that is not a
        // `GenerationError` counted as the model being unusable.
        guard let schema = try? shaped.schema() else {
            Log.enrich.error("A shape would not build into a schema : \(shaped.name, privacy: .public)")
            throw .unusable(.misconfigured)
        }

        do {
            let response = try await session.respond(
                to: question,
                schema: schema,
                options: LocalProvider.options(maximumTokens: budget)
            )
            return Answer(response.content)
        } catch {
            throw LocalProvider.fault(of: error)
        }
    }
}
