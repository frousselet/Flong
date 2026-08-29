//
//  LanguageDetection.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import NaturalLanguage

/// Works out what language an article is written in.
///
/// Section 11 of the specification asks for detection at ingestion, stored on
/// the article. A feed that states its language is believed ; the rest are read.
/// Everything happens on the device, as section 20 requires of anything touching
/// article content.
nonisolated enum LanguageDetection {
    /// Below this, a guess is not worth making : a three word headline is as
    /// likely to be one language as another.
    static let minimumLength = 40

    /// Under this confidence the answer is no answer, since a wrong language is
    /// worse than none : it would send the article to the wrong stemmer for good.
    static let minimumConfidence = 0.6

    /// The language of a text, as a BCP 47 code, or `nil` when it cannot be told.
    static func language(of text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= minimumLength else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let language = recognizer.dominantLanguage else { return nil }
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0
        guard confidence >= minimumConfidence else { return nil }

        return language.rawValue
    }

    /// The language of an article, believing what the feed says first.
    static func language(stated: String?, title: String?, body: String?) -> String? {
        if let stated, !stated.isEmpty { return normalized(stated) }

        let text = [title, body].compactMap { $0 }.joined(separator: " ")
        return language(of: text)
    }

    /// `fr-FR` and `FR` both mean French.
    private static func normalized(_ code: String) -> String {
        let language = Locale.Language(identifier: code)
        return language.languageCode?.identifier ?? code.lowercased()
    }
}
