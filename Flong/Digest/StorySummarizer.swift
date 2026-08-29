//
//  StorySummarizer.swift
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
import GRDB
import OSLog

/// What a story is called, and what it says in one line.
nonisolated struct StoryBrief: Hashable, Sendable {
    let title: String
    let summary: String?
    /// Whether a model wrote it, which the card says out loud.
    let isGenerated: Bool
}

/// The shape the model is asked to fill in.
///
/// Guided generation rather than free text : a model asked for prose returns
/// prose, sometimes with an apology or a preamble in it. Asked for two fields,
/// it returns two fields.
@Generable
nonisolated struct GeneratedBrief {
    @Guide(description: "A short neutral headline for the group, at most eight words")
    var title: String

    @Guide(description: "One sentence saying what happened, at most thirty words")
    var summary: String
}

/// Names and summarizes stories, on the device.
///
/// Section 14 treats the model as a feature flag : the path without it is always
/// present and always tested. Without it a story is named after its most central
/// article and summarized by that article's own standfirst, which is a worse
/// digest and a digest all the same. Nothing about an article ever leaves the
/// device either way.
nonisolated struct StorySummarizer: Sendable {
    /// How many articles of a story the model is shown.
    ///
    /// The window is four thousand tokens for the prompt and the answer
    /// together. Six titles and their standfirsts sit far inside it, and reading
    /// the seventh would not change the headline.
    static let articlesShown = 6

    /// What is left for the answer, whatever the prompt turns out to cost.
    static let reservedTokens = 400

    /// The language the reader reads in.
    ///
    /// Not the language of the articles. Someone watching a subject follows the
    /// press that covers it, whatever language it is written in, and a digest
    /// that answers half in French and half in English is a digest they have to
    /// translate themselves. Writing the line above an article in the reader's
    /// own language is most of what a model is for here.
    ///
    /// The articles are untouched : only the headline and the one line the model
    /// writes are in the reader's language.
    let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    private var instructions: String {
        """
        You name and summarize groups of news articles about the same event.
        \(OnDeviceModel.languageInstruction(for: locale))
        Be factual and plain. Never add an opinion, a judgement or a call to action.
        Never mention that you are a model or that you were asked anything.
        """
    }

    /// The brief for a story, from the model when there is one.
    func brief(forArticles articles: [(title: String, excerpt: String?)]) async -> StoryBrief {
        let fallback = Self.fallback(for: articles)
        guard OnDeviceModel.isAvailable, !articles.isEmpty else { return fallback }

        do {
            let session = LanguageModelSession(instructions: instructions)
            let prompt = Self.prompt(for: articles)

            // The window is four thousand tokens for the prompt and the answer
            // together, and a prompt that leaves no room for an answer is not
            // sent : the cost of asking anyway is a refusal, and the cost of a
            // refusal is a story with no headline.
            //
            // Counting them exactly needs a system a little newer than the one
            // Flong requires. Where it is not there, the prompt is already
            // bounded by the six articles and the two hundred and forty
            // characters each that go into it.
            if #available(iOS 26.4, macOS 26.4, *) {
                let model = SystemLanguageModel.default
                let cost = try await model.tokenCount(for: prompt)

                guard cost + Self.reservedTokens < model.contextSize else {
                    Log.enrich.notice("A story was too long to summarize, and kept its article's own title")
                    return fallback
                }
            }

            let response = try await session.respond(to: prompt, generating: GeneratedBrief.self)
            let generated = response.content

            let title = generated.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = generated.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return fallback }

            OnDeviceModel.succeeded()
            return StoryBrief(title: title, summary: summary.isEmpty ? fallback.summary : summary, isGenerated: true)
        } catch {
            OnDeviceModel.refused(error)
            return fallback
        }
    }

    /// What a story is called when no model is available.
    ///
    /// The first article of the group, which is the one nearest its middle : the
    /// builder sorts members by how close they are to the centre.
    static func fallback(for articles: [(title: String, excerpt: String?)]) -> StoryBrief {
        guard let first = articles.first else {
            return StoryBrief(title: "", summary: nil, isGenerated: false)
        }

        let summary = first.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines)
        return StoryBrief(
            title: first.title,
            summary: (summary?.isEmpty ?? true) ? nil : summary,
            isGenerated: false
        )
    }

    private static func prompt(for articles: [(title: String, excerpt: String?)]) -> String {
        let lines = articles.prefix(articlesShown).map { article in
            let excerpt = article.excerpt.map { String($0.prefix(240)) } ?? ""
            return "- \(article.title)\(excerpt.isEmpty ? "" : " : \(excerpt)")"
        }

        return """
            These articles are about the same event. Name it and say what happened.

            \(lines.joined(separator: "\n"))
            """
    }
}
