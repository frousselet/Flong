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
import NaturalLanguage
import OSLog

/// What a story is called, and what it says in one line.
nonisolated struct StoryBrief: Hashable, Sendable {
    let title: String
    let summary: String?
    /// Whether a model wrote it, which the card says out loud.
    let isGenerated: Bool

    /// The language the model was asked in, when it was asked at all.
    ///
    /// It is what stops a story being asked about for ever. A model that was
    /// never consulted leaves it empty, so the story is asked as soon as one
    /// appears ; a model that answered, refused, or answered in the wrong
    /// language has been asked, in this language, and asking again in the same
    /// one would get the same answer.
    var askedIn: Locale?

    init(title: String, summary: String?, isGenerated: Bool, askedIn: Locale? = nil) {
        self.title = title
        self.summary = summary
        self.isGenerated = isGenerated
        self.askedIn = askedIn
    }

    /// The same brief, marked as one the model has already been asked for.
    func asked(in locale: Locale) -> StoryBrief {
        var brief = self
        brief.askedIn = locale
        return brief
    }
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
        Never write a date, a year or a day of the week. Say what happened, not when.
        Never mention that you are a model or that you were asked anything.
        """
    }

    /// The brief for a story, from the model when there is one.
    func brief(forArticles articles: [(title: String, excerpt: String?)]) async -> StoryBrief {
        let fallback = Self.fallback(for: articles)
        guard OnDeviceModel.isAvailable, !articles.isEmpty else { return fallback }

        do {
            let session = LanguageModelSession(instructions: instructions)
            // The language is said twice, in the instructions and again beside
            // the articles. A small model answers in the language of the words
            // nearest its answer, and three English headlines are nearer than
            // an instruction at the top : that is how a French reader of the
            // English security press ended up with English headlines.
            let prompt = Self.prompt(for: articles, language: OnDeviceModel.languageReminder(for: locale))

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
            guard !title.isEmpty else { return fallback.asked(in: locale) }

            OnDeviceModel.succeeded()

            // A headline in the wrong language is worse than the article's own,
            // which is at least the language somebody chose to write it in.
            // Asked again in the same language it would answer the same way, so
            // the fallback is kept and the story is not asked about again until
            // the reader changes language.
            // A year the articles never mention is a year the model made up.
            // It has nothing to date anything by : what it is shown is
            // headlines and standfirsts, and a model of this size fills the
            // gap rather than leaving it.
            if let invented = Self.inventedYear(title: title, summary: summary, from: articles) {
                Log.enrich.notice("A brief carried a year nothing said : \(invented, privacy: .public)")
                return await retry(
                    in: session,
                    saying: "That answer gave a date. Write it again with no date, no year and no day.",
                    fallback: fallback
                )
            }

            guard Self.isWritten(in: locale, title: title, summary: summary) else {
                // Asked once more, in the same session so the model can see what
                // it just wrote. Measured : the first answer comes back in the
                // language of the articles about half the time whatever the
                // prompt says, and being told so fixes most of those.
                return await retry(
                    in: session,
                    saying: "That answer was not in the right language. \(OnDeviceModel.languageReminder(for: locale))",
                    fallback: fallback
                )
            }

            return StoryBrief(
                title: title,
                summary: summary.isEmpty ? fallback.summary : summary,
                isGenerated: true,
                askedIn: locale
            )
        } catch {
            OnDeviceModel.refused(error)

            // A model that will not write about this story will not write about
            // it next time either, so the asking stops. A model that is broken
            // may well be working at the next launch, so it does not.
            return OnDeviceModel.isTheModelItself(error) ? fallback : fallback.asked(in: locale)
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

    /// Asks again, saying what was wrong with the first answer.
    ///
    /// One retry and no more : a model that answers in the wrong language
    /// twice is a model that will not answer in that language today, and the
    /// article's own headline is a better use of the next second than a third
    /// try. It is at least in a language somebody chose.
    private func retry(in session: LanguageModelSession, saying complaint: String, fallback: StoryBrief) async
        -> StoryBrief
    {
        do {
            let response = try await session.respond(to: complaint, generating: GeneratedBrief.self)
            let title = response.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = response.content.summary.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty, Self.isWritten(in: locale, title: title, summary: summary) else {
                Log.enrich.notice("A brief came back wrong twice and was left to its article")
                return fallback.asked(in: locale)
            }

            return StoryBrief(
                title: title,
                summary: summary.isEmpty ? fallback.summary : summary,
                isGenerated: true,
                askedIn: locale
            )
        } catch {
            OnDeviceModel.refused(error)
            return fallback.asked(in: locale)
        }
    }

    /// A four-digit year the articles never mention.
    ///
    /// **The model is shown no dates at all**, only headlines and standfirsts,
    /// so it has nothing to date anything by. Asked what happened, a model of
    /// this size fills that gap rather than leaving it, and the year it fills
    /// it with is one it read in some other article or simply invented. The
    /// instructions forbid dates ; this is what checks.
    ///
    /// Only a year that appears nowhere in the sources counts. One the articles
    /// themselves carry is one the model copied rather than made up, and a
    /// story genuinely about a year should be allowed to say it.
    ///
    /// The page already says when a story arrived, to the minute, so nothing is
    /// lost by the line above it not saying so too.
    static func inventedYear(
        title: String,
        summary: String,
        from articles: [(title: String, excerpt: String?)]
    ) -> String? {
        let written = years(in: [title, summary].joined(separator: " "))
        guard !written.isEmpty else { return nil }

        let sources = years(in: articles.map { "\($0.title) \($0.excerpt ?? "")" }.joined(separator: " "))
        return written.subtracting(sources).sorted().first
    }

    /// The four-digit years in a piece of text, as a set.
    ///
    /// Bounded to the years a news article plausibly names, so a page number, a
    /// price or a count of casualties is not mistaken for a date.
    private static func years(in text: String) -> Set<String> {
        var found: Set<String> = []
        var digits = ""

        for character in text + " " {
            if character.isNumber {
                digits.append(character)
                continue
            }
            if digits.count == 4, let value = Int(digits), (1000...2999).contains(value) {
                found.insert(digits)
            }
            digits = ""
        }
        return found
    }

    /// Whether what came back is in the language it was asked for.
    ///
    /// Judged by the system's own recognizer rather than by looking for words :
    /// a headline is a handful of them, and half of those are proper nouns that
    /// belong to no language at all. Too short to judge counts as right, since
    /// refusing a two-word headline for want of evidence would refuse most of
    /// them.
    static func isWritten(in locale: Locale, title: String, summary: String) -> Bool {
        guard let wanted = locale.language.languageCode?.identifier else { return true }

        let text = ([title, summary].filter { !$0.isEmpty }).joined(separator: ". ")
        guard text.count >= 24 else { return true }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let found = recognizer.dominantLanguage else { return true }

        return found.rawValue.hasPrefix(wanted)
    }

    private static func prompt(for articles: [(title: String, excerpt: String?)], language: String) -> String {
        let lines = articles.prefix(articlesShown).map { article in
            let excerpt = article.excerpt.map { String($0.prefix(240)) } ?? ""
            return "- \(article.title)\(excerpt.isEmpty ? "" : " : \(excerpt)")"
        }

        return """
            These articles are about the same event. Name it and say what happened.

            \(lines.joined(separator: "\n"))

            \(language)
            """
    }
}
