//
//  Embedder.swift
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
import OSLog

/// Turns an article into a vector, on the device.
///
/// The system's own sentence embeddings do the work. They need no download, no
/// account and no Apple Intelligence, which matters : section 14 treats the
/// language model as a feature flag with a path that always works without it,
/// and the same reasoning applies here. Nothing an article says leaves the
/// device.
///
/// A language the system has no embedding for simply has no vector, and the
/// library search falls back on matching words. That is the whole failure mode.
nonisolated struct Embedder: Sendable {
    /// How much of an article is worth embedding.
    ///
    /// Sentence embeddings are built for sentences, not for essays. The title
    /// and the opening carry what an article is about ; feeding it ten thousand
    /// words of body would average the meaning away.
    static let textLimit = 600

    static func modelIdentifier(for language: NLLanguage) -> String { "nl.sentence.\(language.rawValue)" }

    /// The vector of an article, or `nil` when the system cannot make one.
    func vector(title: String?, text: String?, language: String?) -> ArticleVector? {
        let text = Self.text(title: title, text: text)
        guard !text.isEmpty else { return nil }

        let language = Self.language(of: text, stated: language)
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
            Log.enrich.debug("No sentence embedding for \(language.rawValue, privacy: .public)")
            return nil
        }
        guard let values = embedding.vector(for: text) else { return nil }

        return ArticleVector(
            model: Self.modelIdentifier(for: language),
            revision: NLEmbedding.currentSentenceEmbeddingRevision(for: language),
            values: values.map(Float.init)
        )
    }

    func vector(for item: LibraryItem) -> ArticleVector? {
        vector(title: item.title, text: item.plainText, language: item.language)
    }

    /// The vector of a phrase, in the language a given model speaks.
    ///
    /// A query is short and often has no language of its own to detect, so it is
    /// embedded once per model the library actually holds rather than once, in a
    /// language guessed from four words.
    func vector(text: String, model: String) -> ArticleVector? {
        guard let language = Self.language(ofModel: model) else { return nil }
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else { return nil }
        guard let values = embedding.vector(for: String(text.prefix(Self.textLimit))) else { return nil }

        return ArticleVector(
            model: Self.modelIdentifier(for: language),
            revision: NLEmbedding.currentSentenceEmbeddingRevision(for: language),
            values: values.map(Float.init)
        )
    }

    static func language(ofModel model: String) -> NLLanguage? {
        guard model.hasPrefix("nl.sentence.") else { return nil }
        return NLLanguage(String(model.dropFirst("nl.sentence.".count)))
    }

    /// The model this device would use for a language, so a vector that arrives
    /// from elsewhere can be checked before it is trusted.
    func isCurrent(model: String, revision: Int) -> Bool {
        guard let language = Self.language(ofModel: model) else { return false }
        guard NLEmbedding.sentenceEmbedding(for: language) != nil else { return false }
        return NLEmbedding.currentSentenceEmbeddingRevision(for: language) == revision
    }

    private static func text(title: String?, text: String?) -> String {
        let parts = [title, text].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        let joined = parts.filter { !$0.isEmpty }.joined(separator: ". ")
        return String(joined.prefix(textLimit))
    }

    private static func language(of text: String, stated: String?) -> NLLanguage {
        if let stated, !stated.isEmpty { return NLLanguage(stated) }
        guard let detected = LanguageDetection.language(of: text) else { return .english }
        return NLLanguage(detected)
    }
}
