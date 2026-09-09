//
//  Language.swift
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

/// What language to ask the answer in, and how to ask for it.
///
/// Beside the providers rather than inside one of them : the reader reads in
/// one language whoever writes for them, and a rule about that is not a fact
/// about a model. The one thing here that does ask the system is the check on
/// whether a locale is supported, and it is a default a caller may replace.
nonisolated enum ModelLanguage {
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
