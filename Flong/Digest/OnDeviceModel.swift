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
    private static let refusals = Mutex(0)

    static var isAvailable: Bool {
        guard refusals.withLock({ $0 }) < refusalsBeforeGivingUp else { return false }
        return SystemLanguageModel.default.availability == .available
    }

    /// Why the model cannot be used, when it cannot, in the system's own terms.
    static var unavailableReason: String? {
        guard case .unavailable(let reason) = SystemLanguageModel.default.availability else { return nil }
        return String(describing: reason)
    }

    static func succeeded() {
        refusals.withLock { $0 = 0 }
    }

    /// Records a failure, and says so once rather than once per story.
    ///
    /// A model that will not write about one story is not a model that has
    /// stopped working, and only the second is worth giving up on.
    static func refused(_ error: Error) {
        guard isTheModelItself(error) else {
            Log.enrich.notice("The model would not write about one story : \(Self.kind(of: error), privacy: .public)")
            return
        }

        let count = refusals.withLock { count -> Int in
            count += 1
            return count
        }
        guard count == refusalsBeforeGivingUp else { return }
        Log.enrich.notice(
            "The model failed \(count) times and will not be asked again this run : \(Self.kind(of: error), privacy: .public)"
        )
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
    static func reconsider() {
        refusals.withLock { $0 = 0 }
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
