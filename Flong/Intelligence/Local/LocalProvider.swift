//
//  LocalProvider.swift
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

/// The model on this device, as one provider among the ones a reader may have.
///
/// Everything here was a static on one shared namespace and is unchanged in
/// substance : the guardrails, the sampling, the cap, and the reading of what
/// the framework means by each of its failures. What changes is that it is a
/// value conforming to ``ModelProvider``, so a call site can be handed it or
/// something else and cannot tell.
nonisolated struct LocalProvider: ModelProvider {
    /// Not translated : it names the framework in a log line and in the record
    /// of what wrote a headline, and the screen has its own words for it.
    let name = "Apple Intelligence"

    let identity = "apple-intelligence"

    /// Nothing leaves the device, which is the whole of what this provider is
    /// for.
    let host: String? = nil

    /// Three at a time. A call is a tenth of a second and costs nothing, so a
    /// batch is sized by what fits in a slice of work rather than by what an
    /// overrun would cost.
    let batch = 3

    /// **A third of a news reader's stories come back refused**, and the
    /// refusal is about what the model was shown rather than about how it was
    /// asked. Putting the same story again as what it actually is, published
    /// headlines condensed, recovers four of every ten. That is worth a second
    /// call here, where a call is free.
    let triesASecondVoice = true

    /// Whether the system will answer at all.
    ///
    /// The run of failures that leaves a model alone for a while is not asked
    /// about here : that is ``ModelPatience``, which is per provider and lives
    /// beside the task rather than inside the model.
    var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    /// What to tell the reader when there is no model, or `nil` when there is.
    ///
    /// A page whose stories are all named after their own articles and which
    /// carries no subjects is a page working exactly as section 14 says it
    /// should, and it looks exactly like a page that is broken. One line is
    /// what separates the two, and it says what the reader can do about it,
    /// which for most of these is nothing.
    var absence: LocalizedStringResource? {
        guard case .unavailable(let reason) = SystemLanguageModel.default.availability else { return nil }

        switch reason {
        case .deviceNotEligible:
            return "Apple Intelligence is not available on this device. Stories keep the headline of their own article."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is switched off. Stories keep the headline of their own article."
        case .modelNotReady:
            return
                "Apple Intelligence is still downloading. Stories keep the headline of their own article until it is ready."
        @unknown default:
            return "Apple Intelligence is not available. Stories keep the headline of their own article."
        }
    }

    func writes(_ locale: Locale) -> Bool { Self.writes(locale) }

    /// Whether the model writes the language the reader reads in.
    ///
    /// **Not a reason to stop asking.** A language the model does not write is
    /// one it is not asked for : ``ModelLanguage/languageInstruction(for:supports:)``
    /// asks for the articles' own language instead, and the reader gets a
    /// written headline over an article in the language they were going to read
    /// anyway. That is worth having and is not what this gates.
    ///
    /// What it gates is the check on the answer. Demanding the reader's
    /// language of an answer that was never asked in it rejects every brief and
    /// leaves the whole page wearing its articles' own headlines, which is the
    /// one outcome both halves of this were written to avoid.
    static func writes(_ locale: Locale) -> Bool {
        SystemLanguageModel.default.supportsLocale(locale)
    }

    func conversation(saying instructions: String) -> any ModelConversation {
        LocalConversation(model: Self.model(), instructions: instructions)
    }

    // MARK: - The model, as a news reader needs it

    /// The model, configured once here rather than at each call site.
    ///
    /// **The guardrails are the permissive ones.** The default set is built for
    /// an application that generates content ; this one transforms content the
    /// reader already chose to receive, which is the case Apple provides
    /// ``SystemLanguageModel/Guardrails/permissiveContentTransformations`` for.
    /// The default set refuses a great deal of ordinary news : a court report,
    /// a war, a drug seizure, an epidemic. Every one of those refusals arrived
    /// as a `guardrailViolation`, and every one left a story wearing its own
    /// article's headline for no reason the reader could see.
    ///
    /// It is not a way round anything. What is asked of the model is a headline
    /// and one line about articles a publisher has already published and a
    /// reader has already subscribed to ; nothing is invented and nothing is
    /// sought out.
    ///
    /// **The use case stays `general`, and `contentTagging` was measured.**
    /// Filing one headline under a list of labels looks like exactly what
    /// `contentTagging` is tuned for, and it is worse at it. Against the same
    /// three headlines the live tests have always used :
    ///
    /// | Headline | `general` | `contentTagging` |
    /// | -------- | --------- | ---------------- |
    /// | `Une réforme du calendrier scolaire` | `Éducation` | nothing |
    /// | `Les macros Swift, deux ans après` | `Logiciel` | `Sport · Cybersécurité` |
    /// | shown only `Jardinage` and `Cuisine` | nothing | `Cuisine · Jardinage` |
    ///
    /// It extracts tags from a text rather than choosing among labels, so it
    /// answers with something whatever it is shown and never takes the way out.
    /// `Sport` is the same wrong answer the one-story-per-call design was
    /// written to stop. The parameter stays so the choice is visible and
    /// re-measurable, but nothing passes anything but the default.
    static func model(for useCase: SystemLanguageModel.UseCase = .general) -> SystemLanguageModel {
        SystemLanguageModel(useCase: useCase, guardrails: .permissiveContentTransformations)
    }

    /// How the model is asked to answer.
    ///
    /// **Greedy, and bounded.** A headline is not a place for invention : the
    /// same story asked twice should come back the same, or a rebuild rewrites
    /// a page the reader was reading. Greedy sampling is what makes it
    /// deterministic, and it is free.
    ///
    /// The cap is the answer's share of the window, which the prompt is already
    /// measured against. It is generous rather than tight : a structured answer
    /// cut off in the middle comes back as a `decodingFailure`, which is a
    /// worse outcome than a long one.
    static func options(maximumTokens: Int) -> GenerationOptions {
        GenerationOptions(sampling: .greedy, maximumResponseTokens: maximumTokens)
    }

    // MARK: - What a failure means

    /// What the framework's own failure says, in the terms every caller acts on.
    ///
    /// **A page of security advisories trips the guardrail on some of its
    /// stories and not others.** Counting those as the model being unusable
    /// meant three awkward headlines in a row silenced it for the rest of the
    /// run, and every story after them kept whatever it already said, in
    /// whatever language it already said it. That is the mixture of French and
    /// English a reader of the security press was looking at.
    static func fault(of error: Error) -> ModelFault {
        guard let error = error as? LanguageModelSession.GenerationError else {
            guard error is CancellationError else { return .unusable(.unreachable) }
            return .unusable(.cancelled)
        }

        switch error {
        case .guardrailViolation, .refusal:
            return .declined
        case .decodingFailure, .unsupportedGuide:
            return .unreadable
        case .exceededContextWindowSize:
            return .tooLong
        case .rateLimited, .concurrentRequests:
            return .busy(retryAfter: nil)
        case .assetsUnavailable:
            return .unusable(.absent)
        case .unsupportedLanguageOrLocale:
            return .unusable(.misconfigured)
        @unknown default:
            return .unusable(.unreachable)
        }
    }

    /// The name of what went wrong, without the thing that caused it.
    static func kind(of fault: ModelFault) -> String {
        switch fault {
        case .declined: "declined"
        case .unreadable: "unreadable"
        case .tooLong: "tooLong"
        case .busy: "busy"
        case .unusable(let reason): "unusable.\(reason)"
        }
    }
}
