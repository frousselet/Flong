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

    /// Records a refusal, and says so once rather than once per story.
    static func refused(_ error: Error) {
        let count = refusals.withLock { count -> Int in
            count += 1
            return count
        }
        guard count == refusalsBeforeGivingUp else { return }
        Log.enrich.notice(
            "The model refused \(count) times and will not be asked again this run : \(error.localizedDescription, privacy: .public)"
        )
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

    /// The language named in English, since the instructions are in English.
    private static func englishName(of locale: Locale) -> String? {
        guard let code = locale.language.languageCode?.identifier else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: code)
    }
}
