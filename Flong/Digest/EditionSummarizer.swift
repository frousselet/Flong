//
//  EditionSummarizer.swift
//  Flong
//
//  Created by François Rousselet on 04/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import FoundationModels
import NaturalLanguage
import OSLog

/// What an edition is called, and what it says in a few lines.
nonisolated struct EditionBrief: Hashable, Sendable {
    let title: String
    let summary: String
    /// The language the model was asked in, which is what stops an edition
    /// being asked about for ever. A refusal has no language of its own, so it
    /// is the language asked in and never the language written in.
    let askedIn: Locale
}

/// The lines alone, where the name is settled and the lines are not.
///
/// A shape of its own rather than ``GeneratedEdition`` with its first field
/// thrown away : a model asked to name the page names it again, and a name
/// written a second time may not be the one already accepted.
@Generable
nonisolated struct GeneratedEditionLine {
    @Guide(
        description:
            "What is happening, in two or three whole sentences, naming the two or three things that matter most"
    )
    var summary: String
}

/// The shape the model fills in for a whole page.
@Generable
nonisolated struct GeneratedEdition {
    @Guide(
        description:
            "The name of this edition : what the day amounts to, in at most ten words, every one carrying information"
    )
    var title: String

    @Guide(
        description:
            "What is happening, in two or three sentences, naming the two or three things that matter most"
    )
    var summary: String
}

/// Writes the headline and the line an edition wears over its ten stories.
///
/// **A different question from the one a story is asked.** A story is one event
/// said in a few words, and the model is shown the articles about it. An
/// edition is ten events, and what it is asked for is what the page amounts
/// to : which two or three of the ten matter, and what a reader would say if
/// somebody asked them what was going on. Asked with the story instructions it
/// picked the first headline and rewrote it, which is a page named after its
/// lead and not a page named.
///
/// Everything else is the story's own machinery, deliberately : the same
/// guardrails, the same greedy sampling, the same two voices, the same length
/// checks, the same demand for the reader's language said twice, and the same
/// three outcomes. A second set of rules for the same job is a second set to
/// keep true.
nonisolated struct EditionSummarizer: Sendable {
    /// How many words the name of an edition may run to.
    ///
    /// The same twelve a headline is held to. It is the same piece of
    /// furniture at the same size, above a page rather than above a story.
    static let maximumTitleWords = StorySummarizer.maximumTitleWords

    /// How many words the lines under it may run to.
    ///
    /// **Twice a story's forty-five, and it was measured rather than guessed.**
    /// A story's line states one angle and is over ; this one stands over as
    /// many as ten stories, and what the model actually writes for a real
    /// morning is a clause apiece for the four or five that matter. Sixty was
    /// the first guess and every real page overran it, so every real page was
    /// asked again twice and kept its first answer anyway : a ceiling nothing
    /// passes is not a ceiling, it is three wasted calls to the model.
    ///
    /// Ninety is still a ceiling. What it is for is the model that writes the
    /// page out in full, and past that it is not a summary of the page, it is
    /// the page.
    static let maximumSummaryWords = 90

    /// What is kept for the answer, whatever the prompt costs.
    static let reservedTokens = 500

    /// And what is kept for an answer that is the lines alone.
    static let reservedLineTokens = 300

    /// How much of a story's own line is shown.
    ///
    /// Ten headlines and ten lines is the whole prompt, so each line is cut
    /// where a story's articles are cut : enough to say what the angle was, not
    /// enough to spend the window on one of the ten.
    static let lineShown = 160

    let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    /// What one ask came to.
    ///
    /// The same three the stories are told apart by, and told apart in the same
    /// place : the model wrote something, this page was declined under this
    /// voice, or the model itself is unusable and nothing may be stamped.
    enum Outcome {
        case wrote(EditionBrief)
        case declined
        case unusable
    }

    /// Names the page and says what is happening on it.
    ///
    /// Both voices are tried, exactly as they are for a story and for the same
    /// measured reason : a third of a news reader's pages carry a war, a flood
    /// or a court report, and the writing voice refuses those outright. A page
    /// of ten published headlines said in three sentences is a transformation
    /// of published text, and saying so is what gets it written.
    func brief(over stories: [(title: String, summary: String?)], of slot: EditionSlot) async -> Outcome {
        guard OnDeviceModel.isAvailable, stories.count > 1 else { return .unusable }

        for voice in [Self.instructions, Self.condensing] {
            switch await attempt(stories, of: slot, saying: voice) {
            case .wrote(let brief): return .wrote(brief)
            case .unusable: return .unusable
            case .declined: continue
            }
        }
        return .declined
    }

    private func attempt(
        _ stories: [(title: String, summary: String?)],
        of slot: EditionSlot,
        saying voice: String
    ) async -> Outcome {
        do {
            let model = OnDeviceModel.model()
            let session = LanguageModelSession(model: model, instructions: voice)
            session.prewarm()

            let prompt = Self.prompt(
                for: stories, language: OnDeviceModel.languageReminder(for: locale))

            if #available(iOS 26.4, macOS 26.4, *) {
                let cost = try await model.tokenCount(for: prompt)
                guard cost + Self.reservedTokens < model.contextSize else {
                    Log.enrich.notice("An edition was too long to name, and was left unwritten")
                    return .unusable
                }
            }

            let generated = try await session.respond(
                to: prompt,
                generating: GeneratedEdition.self,
                options: OnDeviceModel.options(maximumTokens: Self.reservedTokens)
            ).content

            let title = generated.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = generated.summary.trimmingCharacters(in: .whitespacesAndNewlines)

            // An empty answer is the model answering nothing about this page,
            // which is not the model being unusable.
            guard !title.isEmpty, !summary.isEmpty else { return .declined }

            OnDeviceModel.succeeded()

            let written = EditionBrief(title: title, summary: summary, askedIn: locale)

            // The checks a story's brief is held to, asked over a page, and one
            // asked for again rather than thrown away : the session still holds
            // what it just wrote, so putting the fault to it once is the
            // cheapest question there is.
            guard let fault = Self.fault(title: title, summary: summary, in: locale, over: stories) else {
                return .wrote(written)
            }

            // **And the answer stands if the asking does not improve it.**
            // These checks are style and the rule above them is not : every
            // edition carries a headline and a line the model wrote, without
            // exception, and an edition declined is a front page that does not
            // exist. Measured on a real morning, the model named six unrelated
            // stories with a list of two of them and wrote the same list again
            // underneath ; asked twice more it wrote it a third time. A page
            // whose line reads like its name is a worse page. A reader with no
            // page at all is worse than that.
            switch await retry(in: session, of: model, over: stories, saying: fault) {
            case .wrote(let better): return .wrote(better)
            case .unusable: return .unusable
            case .declined: return .wrote(written)
            }
        } catch {
            // A rate limit, an asset still downloading or a language this model
            // does not write says nothing about this page, and stamping the
            // edition would leave it unwritten for good on a device that was
            // busy for a second.
            if OnDeviceModel.isTheModelItself(error) {
                OnDeviceModel.refused(error)
                return .unusable
            }
            OnDeviceModel.refused(error)
            return .declined
        }
    }

    /// One more ask, in the same session, about the one thing that was wrong ;
    /// and then, if that is still wrong, the lines on their own.
    ///
    /// **The single field is the move that actually works**, and the story
    /// briefs found it first. The whole brief asked again puts an approved name
    /// back in play and, sampling being greedy, very often comes back word for
    /// word the same : the first real page named here answered `Deux ouvriers
    /// sauvés au Népal, Gaël Monfils éliminé, et plus` twice, was asked again,
    /// and answered it a third time. What is left to ask by then is two
    /// sentences, which is the cheapest question there is to put and the one
    /// the session already has everything it needs to answer.
    private func retry(
        in session: LanguageModelSession,
        of model: SystemLanguageModel,
        over stories: [(title: String, summary: String?)],
        saying fault: String
    ) async -> Outcome {
        do {
            let generated = try await session.respond(
                to: fault,
                generating: GeneratedEdition.self,
                options: OnDeviceModel.options(maximumTokens: Self.reservedTokens)
            ).content

            let title = generated.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = generated.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !summary.isEmpty, Self.isShort(title) else { return .declined }

            OnDeviceModel.succeeded()
            guard Self.fault(title: title, summary: summary, in: locale, over: stories) != nil else {
                return .wrote(EditionBrief(title: title, summary: summary, askedIn: locale))
            }

            // The name is settled by now and accepted twice over. What is left
            // wrong is the lines, so the lines are what is asked for. Whatever
            // that comes back with, the answer already in hand stands rather
            // than the page being left unwritten.
            switch await line(under: title, in: session, over: stories) {
            case .wrote(let better): return .wrote(better)
            case .unusable: return .unusable
            case .declined: return .wrote(EditionBrief(title: title, summary: summary, askedIn: locale))
            }
        } catch {
            OnDeviceModel.refused(error)
            return OnDeviceModel.isTheModelItself(error) ? .unusable : .declined
        }
    }

    /// The lines on their own, under a name that is settled.
    private func line(
        under title: String,
        in session: LanguageModelSession,
        over stories: [(title: String, summary: String?)]
    ) async -> Outcome {
        do {
            let generated = try await session.respond(
                to: "Keep that name. Write only the lines under it, in two or three whole sentences, "
                    + "saying what happened in the two or three stories that matter most. "
                    + "Do not repeat the name.",
                generating: GeneratedEditionLine.self,
                options: OnDeviceModel.options(maximumTokens: Self.reservedLineTokens)
            ).content

            let summary = generated.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else { return .declined }
            guard Self.fault(title: title, summary: summary, in: locale, over: stories) == nil else {
                return .declined
            }

            OnDeviceModel.succeeded()
            return .wrote(EditionBrief(title: title, summary: summary, askedIn: locale))
        } catch {
            OnDeviceModel.refused(error)
            return OnDeviceModel.isTheModelItself(error) ? .unusable : .declined
        }
    }

    /// The first thing wrong with an answer, said as the sentence that asks for
    /// it again.
    static func fault(
        title: String,
        summary: String,
        in locale: Locale,
        over stories: [(title: String, summary: String?)]
    ) -> String? {
        let sources = stories.map { ($0.title, $0.summary) }
        if StorySummarizer.inventedYear(
            title: title, summary: summary, from: sources.map { (title: $0.0, excerpt: $0.1) }) != nil
        {
            return "That answer gave a date. Write it again with no date, no year and no day."
        }
        if !isShort(title) {
            return "That name is too long. Write it again in at most ten words."
        }
        // **The page is not its lead.** The instruction says so and a model of
        // this size does not hold it : shown six headlines it hands back the
        // first one, and the page then reads the same sentence twice over, once
        // as the name of the edition and again as the headline directly under
        // it. It is checked against the headlines it was actually shown, which
        // is exact, cheap, and says nothing about any language.
        if stories.contains(where: { StorySummarizer.repeats($0.title, in: title) }) {
            return "That name is one of the headlines. Write a name for the whole page instead, saying what "
                + "these stories add up to."
        }
        if !isBrief(summary) {
            return "That summary is too long. Write it again in two or three sentences."
        }
        // **A line that repeats the name has spent the only lines the page
        // gets saying nothing new.** The story briefs have checked this from
        // the beginning and the edition did not, and the model does exactly
        // what it does there : the first real page it named came back with the
        // name and the summary word for word the same, `Deux ouvriers sauvés au
        // Népal, Gaël Monfils éliminé, et plus`, twice over.
        if StorySummarizer.repeats(title, in: summary) {
            return "That summary repeats the name. Write it again, saying what happened in the two or three "
                + "stories that matter most."
        }
        if OnDeviceModel.writes(locale), !StorySummarizer.isWritten(in: locale, title: title, summary: summary) {
            return OnDeviceModel.languageReminder(for: locale)
        }
        return nil
    }

    static func isShort(_ title: String) -> Bool {
        title.split(whereSeparator: \.isWhitespace).count <= maximumTitleWords
    }

    static func isBrief(_ summary: String) -> Bool {
        summary.split(whereSeparator: \.isWhitespace).count <= maximumSummaryWords
    }

    /// What the model is shown : the ten heads, in the order the page shows
    /// them, and nothing else.
    ///
    /// **No dates, exactly as for a story.** The model has nothing to date
    /// anything by and fills the gap rather than leaving it, and the page
    /// already says when every story on it arrived.
    static func prompt(for stories: [(title: String, summary: String?)], language: String) -> String {
        let lines = stories.map { story in
            guard let line = story.summary.map({ String($0.prefix(lineShown)) }), !line.isEmpty else {
                return "- \(story.title)"
            }
            return "- \(story.title) : \(line)"
        }

        return """
            These are the stories on the reader's front page, in the order the page shows them. \
            Name this page, and say what is happening.

            \(lines.joined(separator: "\n"))

            \(language)
            """
    }

    /// The writing voice.
    ///
    /// The rules a headline is held to, said over a page rather than over one
    /// story, and one rule of its own : the page is not its lead. A name that
    /// rewrites the first headline is a page named after one story, which the
    /// reader can already see at the top of it.
    static let instructions = """
        You are the editor of a daily digest, writing the name of one edition and the few lines under it.

        The name says what the day amounts to. At most ten words, every one of them carrying information : \
        a fact, a figure, a named actor or a verb of action. No jargon, no abstraction, no wordplay. \
        It is read in a list with no page around it, so the words a reader would look for go at the front.

        The name is not the first headline rewritten. It stands over all of these stories, so it names \
        what they add up to, or the two things a reader would mention first.

        The lines under it say what is happening : two or three whole sentences, naming the two or three \
        stories that matter most and what happened in them. Prefer a fact, a figure or a named actor to a \
        general statement. They are not the name again in other words, and they never end with `and more` \
        or anything like it.

        Never say more than these stories say. Never give a date, a year or a day.
        """

    /// The condensing voice, for a page the first one will not touch.
    ///
    /// Word for word the same rules. What changes is the description of the
    /// work : ten published headlines said in three sentences is a
    /// transformation of published text and not an opinion about a war, and
    /// saying so is what gets a page of ordinary news written at all.
    static let condensing = """
        You are given headlines that have already been published, by news organizations the reader subscribes to. \
        Your task is to condense them : to say in a few sentences what these published headlines say together. \
        You are not writing about the events. You are restating what has already been written.

        The name says what these headlines amount to. At most ten words, every one of them carrying \
        information. No jargon, no wordplay. It is not the first headline rewritten : it stands over all of them.

        The lines under it restate the two or three headlines that matter most, in two or three whole \
        sentences. They are not the name again in other words, and they never end with `and more` or \
        anything like it.

        Never say more than these headlines say. Never give a date, a year or a day.
        """
}
