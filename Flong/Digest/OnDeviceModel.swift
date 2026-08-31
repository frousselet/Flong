//
//  OnDeviceModel.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import FoundationModels
import OSLog
import Synchronization

/// What everything that asks the system model shares.
///
/// Section 14 treats the model as a feature flag : the path without it is always
/// present and always tested. Two things follow that every caller needs, so they
/// live here rather than once per caller : when to stop asking, and what language
/// to ask for the answer in.
nonisolated enum OnDeviceModel {
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
    /// ``isAvailable`` first : three failures and the model was off for the
    /// whole life of the process, which on a Mac is days. The reasons it fails
    /// are mostly temporary, and every one of them is a reason to try again
    /// later : assets still downloading, a reader switching Apple Intelligence
    /// on, a rate limit lifting.
    static let refusalPause: TimeInterval = 10 * 60

    /// The failures in a row, and when they added up to giving up.
    private nonisolated struct Refusals: Sendable {
        var count = 0
        var gaveUpAt: Date?
    }

    private static let refusals = Mutex(Refusals())

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

    // MARK: - Whether to ask at all

    static var isAvailable: Bool {
        guard !hasGivenUp(now: Date()) else { return false }
        return SystemLanguageModel.default.availability == .available
    }

    /// Whether the model is still being left alone after a run of failures.
    ///
    /// The pause expiring forgets the failures outright rather than allowing
    /// one more call : what follows is a fresh run of three, so a model that is
    /// genuinely broken is asked three times every ten minutes and no more.
    static func hasGivenUp(now: Date) -> Bool {
        refusals.withLock { refusals in
            guard let gaveUpAt = refusals.gaveUpAt else { return false }
            guard now.timeIntervalSince(gaveUpAt) < refusalPause else {
                refusals = Refusals()
                return false
            }
            return true
        }
    }

    /// Whether the model writes the language the reader reads in.
    ///
    /// **Not a reason to stop asking.** A language the model does not write is
    /// one it is not asked for : ``languageInstruction(for:supports:)`` asks
    /// for the articles' own language instead, and the reader gets a written
    /// headline over an article in the language they were going to read anyway.
    /// That is worth having and is not what this gates.
    ///
    /// What it gates is the check on the answer. Demanding the reader's
    /// language of an answer that was never asked in it rejects every brief and
    /// leaves the whole page wearing its articles' own headlines, which is the
    /// one outcome both halves of this were written to avoid.
    static func writes(_ locale: Locale) -> Bool {
        SystemLanguageModel.default.supportsLocale(locale)
    }

    /// Why the model cannot be used, when it cannot, in the system's own terms.
    static var unavailableReason: String? {
        guard case .unavailable(let reason) = SystemLanguageModel.default.availability else { return nil }
        return String(describing: reason)
    }

    /// What to tell the reader when there is no model, or `nil` when there is.
    ///
    /// A page whose stories are all named after their own articles and which
    /// carries no subjects is a page working exactly as section 14 says it
    /// should, and it looks exactly like a page that is broken. One line is
    /// what separates the two, and it says what the reader can do about it,
    /// which for most of these is nothing.
    static var absence: LocalizedStringResource? {
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

    static func succeeded() {
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
    /// particular call, so nothing is stamped as answered, and they no longer
    /// count towards giving up : a background pass is rate-limited hard, and
    /// three of those used to silence the model for the rest of the process,
    /// which is how a night of writing headlines ended with no subjects filed.
    static func refused(_ error: Error, now: Date = Date()) {
        guard isTheModelItself(error) else {
            Log.enrich.notice("The model would not write about one story : \(Self.kind(of: error), privacy: .public)")
            return
        }
        guard !isBusy(error) else {
            Log.enrich.info("The model is busy : \(Self.kind(of: error), privacy: .public)")
            return
        }

        let count = refusals.withLock { refusals -> Int in
            refusals.count += 1
            if refusals.count == refusalsBeforeGivingUp { refusals.gaveUpAt = now }
            return refusals.count
        }
        guard count == refusalsBeforeGivingUp else { return }
        Log.enrich.notice(
            "The model failed \(count) times and is left alone for a while : \(Self.kind(of: error), privacy: .public)"
        )
    }

    /// Whether the answer is the system asking for a moment rather than saying
    /// it cannot help.
    static func isBusy(_ error: Error) -> Bool {
        guard let error = error as? LanguageModelSession.GenerationError else { return false }

        switch error {
        case .rateLimited, .concurrentRequests: return true
        default: return false
        }
    }

    /// Whether an error is the model being unusable, rather than the model
    /// declining to write about one particular thing.
    ///
    /// A page of security advisories trips the guardrail on some of its
    /// stories and not others. Counting those towards giving up meant three
    /// awkward headlines in a row silenced the model for the rest of the run,
    /// and every story after them kept whatever it already said, in whatever
    /// language it already said it. That is the mixture of French and English
    /// a reader of the security press was looking at.
    static func isTheModelItself(_ error: Error) -> Bool {
        guard let error = error as? LanguageModelSession.GenerationError else { return true }

        switch error {
        case .guardrailViolation, .refusal, .decodingFailure, .exceededContextWindowSize, .unsupportedGuide:
            // This story, not the model.
            return false
        case .assetsUnavailable, .unsupportedLanguageOrLocale, .rateLimited, .concurrentRequests:
            return true
        @unknown default:
            return true
        }
    }

    /// The name of what went wrong, without the article that caused it.
    private static func kind(of error: Error) -> String {
        guard let error = error as? LanguageModelSession.GenerationError else {
            return String(describing: type(of: error))
        }
        switch error {
        case .guardrailViolation: return "guardrailViolation"
        case .refusal: return "refusal"
        case .decodingFailure: return "decodingFailure"
        case .exceededContextWindowSize: return "exceededContextWindowSize"
        case .unsupportedGuide: return "unsupportedGuide"
        case .assetsUnavailable: return "assetsUnavailable"
        case .unsupportedLanguageOrLocale: return "unsupportedLanguageOrLocale"
        case .rateLimited: return "rateLimited"
        case .concurrentRequests: return "concurrentRequests"
        @unknown default: return "unknown"
        }
    }

    /// Forgets the refusals, for the next launch or a deliberate retry.
    ///
    /// Called when the reader comes back to the application and at the head of
    /// the full pass. Both are moments when what made the model fail an hour
    /// ago may well have changed, and neither costs anything if it has not :
    /// the count simply builds again.
    static func reconsider() {
        refusals.withLock { $0 = Refusals() }
    }

    // MARK: - The language of the answer

    /// What to tell the model about the language to answer in.
    ///
    /// The reader's language, not the articles'. Someone watching a subject
    /// follows whoever covers it, and a French reader on the English technical
    /// press wants a French headline over an English article : translating a
    /// headline is something the model does well, and it is most of the reason
    /// to have one here.
    ///
    /// A model asked for a language it does not speak answers in a mixture of
    /// that language and the one it was given, which is worse than either. So a
    /// locale the model does not support falls back to the articles' own
    /// language, and the reader gets a headline in the language they were going
    /// to read anyway.
    static func languageInstruction(
        for locale: Locale,
        supports isSupported: (Locale) -> Bool = { SystemLanguageModel.default.supportsLocale($0) }
    ) -> String {
        let articles = "Answer in the language the articles are written in."
        guard let name = englishName(of: locale), isSupported(locale) else { return articles }
        return "Answer in \(name), whatever language the articles are written in."
    }

    /// The same demand, written in the language it asks for.
    ///
    /// Measured against the model, on English articles with a French reader :
    ///
    /// | Where the demand is | What comes back |
    /// | ------------------- | --------------- |
    /// | in the instructions, in English | English |
    /// | there and again after the articles | French, clumsy |
    /// | there, and `not in English` after them | French, an English word left in |
    /// | **there, and the demand in French after them** | **French, and the best of the four** |
    ///
    /// A model answers in the language of the words nearest its answer, and a
    /// sentence in that language is worth more than any number of sentences
    /// about it. So the demand is a translated string like any other.
    ///
    /// `nil` for a language the application is not translated into, where the
    /// catalogue would hand back English and the demand would then ask for
    /// the wrong language altogether.
    static func demand(in locale: Locale) -> String? {
        guard let code = locale.language.languageCode?.identifier,
            Bundle.main.localizations.contains(where: { $0.hasPrefix(code) })
        else { return nil }

        return String(
            localized: "Answer in English. Write every word of your answer in English.",
            locale: locale,
            comment: "Sent to the on-device model, in the reader's own language, to make it answer in that language"
        )
    }

    /// What to put beside the text the model is given.
    ///
    /// The demand in the reader's own language when there is one, and the
    /// English sentence about it otherwise.
    static func languageReminder(for locale: Locale) -> String {
        demand(in: locale) ?? languageInstruction(for: locale)
    }

    /// The language named in English, since the instructions are in English.
    private static func englishName(of locale: Locale) -> String? {
        guard let code = locale.language.languageCode?.identifier else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: code)
    }
}
