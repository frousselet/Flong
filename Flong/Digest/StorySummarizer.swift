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
    @Guide(description: "The headline : what happened, in at most ten words, every one of them carrying information")
    var title: String

    @Guide(description: "The standfirst : the angle, in one or two sentences, answering what the headline left out")
    var summary: String
}

/// The headline alone, where the story is settled and its length is not.
@Generable
nonisolated struct GeneratedHeadline {
    @Guide(description: "The headline : what happened, in at most ten words, every one of them carrying information")
    var title: String
}

/// The standfirst alone, where the headline is already settled.
///
/// A shape of its own rather than ``GeneratedBrief`` with its first field
/// thrown away : a model asked for a headline writes one, and one written for
/// the second time is a headline that may not be the one already accepted.
@Generable
nonisolated struct GeneratedLine {
    @Guide(description: "The standfirst : the angle, in one or two sentences, answering what the headline left out")
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
    /// **The window is the device's, and it says so itself.** A session holds
    /// the prompt and the answer together in `SystemLanguageModel.contextSize`,
    /// which is read at runtime rather than written down here : it is back
    /// deployed to the oldest system Flong runs on, where it answers the four
    /// thousand and ninety-six tokens the framework has always had, and on a
    /// newer one it answers whatever this device's model actually holds. Six
    /// titles and their standfirsts sit far inside the smallest of those, and
    /// reading the seventh would not change the headline.
    static let articlesShown = 6

    /// What is left for the answer, whatever the prompt turns out to cost.
    ///
    /// Twelve words of headline and forty-five of standfirst come to a couple
    /// of hundred tokens with the shape they are wrapped in ; the rest is room
    /// for a model that starts badly. Generous on purpose : the framework
    /// stops a response that reaches this and does not say so, so a budget cut
    /// close to the ideal answer buys a line that stops in the middle of a
    /// word rather than a shorter one.
    static let reservedTokens = 400

    /// And what is left for an answer that is one line rather than two fields.
    static let reservedLineTokens = 200

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

    /// What a headline is for, put to a model that has never worked on a desk.
    ///
    /// A headline does two things at once : it says in a few words what the
    /// piece contains, and it makes somebody want to read it. The second is
    /// worthless without the first, which is why almost every line here is
    /// about the first.
    ///
    /// **Every word carries information.** The headline holds the most
    /// important words of the story and no others. `Le numérique en question`
    /// says nothing : a fact, a figure, a named actor or a verb of action says
    /// something. Jargon is out.
    ///
    /// **Short.** Up to about ten words sits comfortably in a reader's
    /// immediate memory ; past twelve it is a sentence. ``isShort(_:)`` is what
    /// holds it there, since a small model asked for ten words gives fifteen
    /// about as often as not.
    ///
    /// **Clear before clever.** A plain headline barely trying to tempt anybody
    /// beats a pun nobody can parse. Wordplay is a legitimate craft and it
    /// needs a readership and an editorial line to land ; a model writing for
    /// one reader it has never met has neither.
    ///
    /// **Read out of context.** This is a list, and a headline in it arrives
    /// with no page around it and is often cut short, so the words a reader
    /// would look for go at the front.
    ///
    /// **And never more than the articles say.** The gap between what a
    /// headline promises and what the piece delivers is what destroys the
    /// credit of a publication over time, and the same is true of a reader's
    /// own front page : a page that oversells is a page they stop believing.
    ///
    /// **The headline and the line under it share the work.** They are one
    /// piece of furniture. The headline says what happened ; the standfirst
    /// states the angle, which is what this story is about of everything it
    /// could have been about, and answers what the headline had no room for :
    /// who, what, where and why. It is not the headline again in other words ;
    /// ``repeats(_:in:)`` is what checks.
    ///
    /// **Of the five, *when* is deliberately missing.** A chapeau normally
    /// answers it, and here it must not : the model is shown no dates at all,
    /// only headlines and standfirsts, so it has nothing to date anything by
    /// and fills the gap rather than leaving it. The page already says when a
    /// story arrived, to the minute, so nothing is lost. ``inventedYear(title:summary:from:)``
    /// is what catches it when the instruction does not hold.
    ///
    /// **One or two sentences.** Past that it is the article, and the article
    /// is one tap away. What is enforced is a ceiling in words rather than a
    /// count of sentences : a sentence tokenizer splits `M. Dupont` in two, and
    /// a standfirst rejected for naming somebody is a worse outcome than one
    /// that ran to three sentences. The ceiling is a backstop against a model
    /// writing a paragraph, not an attempt to enforce the ideal length.
    ///
    /// The picture cannot be taken into account, and that settles a question
    /// rather than leaving one open. A desk can let a headline lean on an
    /// explicit photograph and be more tempting for it ; here the row's picture
    /// is whatever the publisher happened to attach, so the headline has to
    /// carry the information every time.
    var instructions: String {
        """
        You write the headline and the standfirst for a group of news articles about one event.
        \(OnDeviceModel.languageInstruction(for: locale))

        The headline says what happened, in the fewest words that are still precise.
        Every word must carry information. No jargon, no abstractions.
        Name who did what. Prefer a fact, a figure or a verb of action to a general idea.
        Put the words a reader would look for first : it is read in a list and often cut short.
        Never a pun, never a play on words, never a tease, never a question.
        Never promise more than the articles say, and never exaggerate.

        The standfirst is one or two sentences and no more.
        It states the angle : what this story is about, of everything it could have been about.
        It answers what the headline left out : who, what, where, and why.
        Prefer a fact, a figure or a named actor to a general statement.
        Never write the headline again in other words.

        Be factual and plain. Never add an opinion, a judgement or a call to action.
        Never write a date, a year or a day of the week. Say what happened, not when.
        Never mention that you are a model or that you were asked anything.
        """
    }

    /// The same work, put as a transformation rather than as writing.
    ///
    /// **What a refusal is about.** The error carries `May contain sensitive
    /// content`, and the stories it carries it for are floods, a war, an
    /// election, a lawsuit : the news, in other words. The model is not
    /// objecting to the request, it is objecting to what it was shown, and no
    /// amount of asking more politely moves it.
    ///
    /// What does move it is what the task honestly is. A headline over six
    /// other headlines is not an opinion about a war ; it is six published
    /// sentences said in one. Put that way, four of the ten stories refused by
    /// the voice above answer, and answer in the reader's language rather than
    /// in the publisher's.
    ///
    /// **The rules are the same rules.** The guardrails are untouched, the
    /// answer goes through the same checks, and the mark on the page says the
    /// model wrote it exactly as it does for the first voice. What changes is
    /// the description of the work, which was inaccurate to begin with.
    var condensing: String {
        """
        You condense published news headlines into one headline and one standfirst.
        \(OnDeviceModel.languageInstruction(for: locale))

        What you are given has already been published by news organisations.
        You are not writing about the event : you are saying what these published headlines say, in fewer words.
        Never add anything they do not say. Never take a side, never judge, never advise.

        The headline says what happened, in the fewest words that are still precise.
        Every word must carry information. No jargon, no abstractions.
        Name who did what. Prefer a fact, a figure or a verb of action to a general idea.
        Never a pun, never a play on words, never a tease, never a question.

        The standfirst is one or two sentences and no more.
        It answers what the headline left out : who, what, where, and why.
        Never write the headline again in other words.

        Never write a date, a year or a day of the week. Say what happened, not when.
        Never mention that you are a model or that you were asked anything.
        """
    }

    /// The brief for a story, from the model when there is one.
    ///
    /// **Asked twice, in two voices, before the story is given back to its
    /// publisher.** A third of a news reader's stories come back refused, and
    /// the refusal says `May contain sensitive content` : it is about what the
    /// model was shown, not about how it was asked. Floods, a war, an election,
    /// a lawsuit. That is the news, and a digest that drops a third of it is
    /// not a digest.
    ///
    /// So a story the writing voice will not touch is put again as what it
    /// actually is : published headlines, condensed. Measured over thirty real
    /// stories, that recovers four of the ten it had just refused, and the four
    /// come back in the reader's own language rather than in the publisher's.
    /// Nothing is loosened to get them : the same guardrails, the same rules
    /// afterwards, and a story refused twice is still a story shown as its
    /// publisher wrote it.
    func brief(forArticles articles: [(title: String, excerpt: String?)]) async -> StoryBrief {
        let fallback = Self.fallback(for: articles, readIn: locale)
        guard OnDeviceModel.isAvailable, !articles.isEmpty else { return fallback }

        for voice in [instructions, condensing] {
            switch await attempt(articles, saying: voice, keeping: fallback) {
            case .wrote(let brief):
                return brief
            // The model itself, rather than this story : the fallback is left
            // unstamped so the story is asked about again another time.
            case .unusable:
                return fallback
            case .declined:
                continue
            }
        }

        return fallback.asked(in: locale)
    }

    /// What one ask came to.
    private enum Attempt {
        case wrote(StoryBrief)
        /// This story, under this voice. The other voice is worth a try.
        case declined
        /// The model, not the story : busy, or not there at all.
        case unusable
    }

    /// One ask, in one voice, with every rule the answer is held to.
    private func attempt(
        _ articles: [(title: String, excerpt: String?)],
        saying voice: String,
        keeping fallback: StoryBrief
    ) async -> Attempt {
        do {
            let model = OnDeviceModel.model()
            let session = LanguageModelSession(model: model, instructions: voice)
            // Free, and the one place it buys anything : the assets load while
            // the prompt is being measured below, which is a real await rather
            // than a wait invented to give this something to overlap with.
            session.prewarm()
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
                let cost = try await model.tokenCount(for: prompt)

                guard cost + Self.reservedTokens < model.contextSize else {
                    Log.enrich.notice("A story was too long to summarize, and kept its article's own title")
                    // Nothing to do with how it was asked, so the other voice
                    // is not tried and the story is left to be asked about
                    // again when its articles have moved on.
                    return .unusable
                }
            }

            let response = try await session.respond(
                to: prompt,
                generating: GeneratedBrief.self,
                options: OnDeviceModel.options(maximumTokens: Self.reservedTokens)
            )
            let generated = response.content

            let title = generated.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = generated.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            // An empty headline is the model answering nothing, which is not
            // the same as the model being unusable : the same rule as the two
            // catch blocks, said once.
            guard !title.isEmpty else { return .declined }

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
                    of: model,
                    saying: "That answer gave a date. Write it again with no date, no year and no day."
                )
            }

            // A headline of twenty words is a sentence, and the instruction
            // alone does not hold a small model to ten.
            guard Self.isShort(title) else {
                return await retry(
                    in: session,
                    of: model,
                    saying: """
                        That headline is too long. Write it again in at most \(Self.maximumTitleWords) words, \
                        keeping only the words that carry information.
                        """
                )
            }

            // The headline and the line under it are one piece of furniture and
            // divide the work between them. A standfirst that says the headline
            // again has spent the only line the story gets saying nothing.
            guard !Self.repeats(title, in: summary) else {
                return await retry(
                    in: session,
                    of: model,
                    saying: """
                        That standfirst repeats the headline. Write it again saying what the headline \
                        left out : who, what, where, why.
                        """
                )
            }

            // A standfirst that runs to a paragraph is the article, and the
            // article is one tap away.
            guard Self.isBrief(summary) else {
                return await retry(
                    in: session,
                    of: model,
                    saying: """
                        That standfirst is too long. Write it again in one or two sentences, \
                        keeping the angle and what the headline left out.
                        """
                )
            }

            // Only when the reader's language is what was asked for. A model
            // that does not write it is asked for the articles' language
            // instead, deliberately, and demanding the reader's language of an
            // answer nobody asked in that language rejected every brief and
            // left the whole page wearing its articles' own headlines.
            guard !OnDeviceModel.writes(locale) || Self.isWritten(in: locale, title: title, summary: summary) else {
                // Asked once more, in the same session so the model can see what
                // it just wrote. Measured : the first answer comes back in the
                // language of the articles about half the time whatever the
                // prompt says, and being told so fixes most of those.
                return await retry(
                    in: session,
                    of: model,
                    saying: "That answer was not in the right language. \(OnDeviceModel.languageReminder(for: locale))"
                )
            }

            // **An empty standfirst is half an answer, and the two guards
            // above let it through** : nothing repeats a headline, and nothing
            // runs to a paragraph. The headline is settled, so what is asked
            // for is the line and not the brief again.
            let line = summary.isEmpty ? await self.line(under: title, in: session, of: model) : summary

            return .wrote(
                StoryBrief(
                    title: title,
                    summary: line,
                    isGenerated: true,
                    askedIn: locale
                )
            )
        } catch {
            OnDeviceModel.refused(error)
            return Self.outcome(of: error)
        }
    }

    /// What a failure means about this story.
    ///
    /// **The model being unusable is not an answer about the story.** A rate
    /// limit, an asset still downloading, a language this model does not write :
    /// none of them says anything about these articles, and stamping the story
    /// would leave it wearing its own headline for ever on a device that was
    /// simply busy for a second. A refusal is different : the model has read
    /// these articles and will not write about them in this voice, which the
    /// other voice is given a chance to disprove.
    private static func outcome(of error: Error) -> Attempt {
        OnDeviceModel.isTheModelItself(error) ? .unusable : .declined
    }

    /// What a story is called when no model is available.
    ///
    /// The first article of the group, which is the one nearest its middle : the
    /// builder sorts members by how close they are to the centre.
    static func fallback(for articles: [(title: String, excerpt: String?)], readIn locale: Locale) -> StoryBrief {
        guard let first = articles.first else {
            return StoryBrief(title: "", summary: nil, isGenerated: false)
        }

        // **The headline and the line come from one article, or the line
        // does not come at all.** The line used to be taken from whichever
        // article in the story had one, under whichever headline came first :
        // on a real page that put `Donald Trump's shallow renaming of the Great
        // Lakes` over a line about a mapping application climbing the download
        // charts, and `Farewell Keir Starmer` over a by-election in a London
        // constituency. Each half was true and the pair was not about anything.
        //
        // So the whole head comes from the first article that has both, and a
        // story where no article carries a line the publisher wrote is a story
        // shown as a headline. Which headline moves with it : any member of the
        // group stands for the group, and one that arrives with its own line
        // stands for it better than one that does not.
        let complete = articles.compactMap { article -> (title: String, line: String)? in
            let title = Self.plainTitle(article.title)
            guard let line = Self.standfirst(from: article.excerpt, under: title) else { return nil }
            return (title, line)
        }

        // **And the reader's own language decides between them.** A story
        // nobody wrote a brief for is shown in the words its publishers used,
        // and a group about one event is regularly covered in two languages :
        // `Lac Ontario vs Lake America` ran in Le Monde and in the Guardian on
        // the same morning. Where one of the members is already in the language
        // the reader reads in, that is the member the page shows, and nothing
        // has to be translated to get there.
        let told = complete.first { Self.isWritten(in: locale, title: $0.title, summary: $0.line) } ?? complete.first

        return StoryBrief(
            title: told?.title ?? Self.plainTitle(first.title),
            summary: told?.line,
            isGenerated: false
        )
    }

    /// A publisher's own standfirst, where what is offered is one.
    ///
    /// **An excerpt is not a standfirst.** Where a publisher writes no summary,
    /// the excerpt is the top of the article body flattened and cut at three
    /// hundred characters on the nearest space : a sentence stopped in the
    /// middle, with whatever the feed staples underneath it. A release note
    /// went out as `Release: llm-gemini 0.34 New model ... #146 Fixed async
    /// responses ... #137 Tags: llm, gemini`, ticket numbers and all, under the
    /// heading the page gives a standfirst.
    ///
    /// So a line that only repeats the headline, that reads as a body rather
    /// than a summary, or that is a machine's footer is dropped. A story with
    /// no standfirst is a story shown as a headline, which is what a page of
    /// headlines is made of.
    static func standfirst(from excerpt: String?, under title: String) -> String? {
        guard var text = excerpt?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        // What a feed staples to the foot of an entry. Cut rather than
        // rejected : the sentence above it is often a real one.
        for marker in Self.footers {
            guard let found = text.range(of: marker, options: [.caseInsensitive]) else { continue }
            text = String(text[text.startIndex..<found.lowerBound]).trimmingCharacters(
                in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–|·"))
            )
        }

        // **It has to end.** A publisher's standfirst is a finished sentence ;
        // an excerpt is the top of the body flattened and cut at three hundred
        // characters on the nearest space, so it stops wherever it stopped. That
        // is the one signal that tells the two apart whatever language they are
        // in and whatever the article is about, and it is what a reader sees
        // first : a line trailing off mid-thought under a headline.
        guard let last = text.last, Self.ends.contains(last) else { return nil }
        guard !Self.repeats(title, in: text), Self.isBrief(text) else { return nil }

        return text
    }

    /// What the end of a sentence looks like, in the languages a feed arrives in.
    private static let ends: Set<Character> = [".", "!", "?", "…", "»", "\"", "”", "。", "！", "？"]

    /// What a feed writes under an entry rather than in it.
    private static let footers = ["Tags:", "Tagged:", "Filed under", "Read more", "Lire la suite", "The post "]

    /// Asks again, saying what was wrong with the first answer.
    ///
    /// One retry of the brief and no more : a model that answers in the wrong
    /// language twice is a model that will not answer in that language today,
    /// and the article's own headline is a better use of the next second than a
    /// third try. It is at least in a language somebody chose.
    ///
    /// The standfirst is the exception, and ``line(under:in:)`` says why.
    private func retry(
        in session: LanguageModelSession,
        of model: SystemLanguageModel,
        saying complaint: String
    ) async -> Attempt {
        do {
            let response = try await session.respond(
                to: complaint,
                generating: GeneratedBrief.self,
                options: OnDeviceModel.options(maximumTokens: Self.reservedTokens)
            )
            var title = response.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = response.content.summary.trimmingCharacters(in: .whitespacesAndNewlines)

            // **A headline still too long is asked for on its own.** Told twice
            // that a headline runs to a sentence, a model of this size writes
            // the sentence again : eight briefs in thirty died here, and half
            // of them were the condensing voice answering about a story the
            // writing voice had refused outright. The smaller question gets the
            // better answer, exactly as it does for the standfirst.
            if !title.isEmpty, !Self.isShort(title), let shorter = await headline(in: session, of: model) {
                title = shorter
            }

            // Said one rule at a time : `wrong twice` was true of eight briefs
            // in thirty and named none of the three things it could have been,
            // which is a measurement nobody can act on.
            guard !title.isEmpty else {
                Log.enrich.notice("A brief came back with no headline twice, so the other voice is tried")
                return .declined
            }
            guard Self.isShort(title) else {
                Log.enrich.notice("A headline stayed too long twice, so the other voice is tried")
                return .declined
            }
            guard !OnDeviceModel.writes(locale) || Self.isWritten(in: locale, title: title, summary: summary) else {
                Log.enrich.notice("A brief stayed in the wrong language twice, so the other voice is tried")
                return .declined
            }

            // A standfirst that is still the headline, or still a paragraph,
            // is asked for one more time, alone : the headline is settled by
            // here, and what is missing is the line under it.
            let usable = !summary.isEmpty && !Self.repeats(title, in: summary) && Self.isBrief(summary)
            let line = usable ? summary : await self.line(under: title, in: session, of: model)

            return .wrote(
                StoryBrief(
                    title: title,
                    summary: line,
                    isGenerated: true,
                    askedIn: locale
                )
            )
        } catch {
            OnDeviceModel.refused(error)
            return Self.outcome(of: error)
        }
    }

    /// Asks for the headline alone, once, where the story is settled and the
    /// length is not.
    ///
    /// The same move as ``line(under:in:)`` and for the same reason : the
    /// session already holds everything that was said, the question left is one
    /// line long, and a model that will not obey a word count inside a whole
    /// brief will often obey it on its own.
    private func headline(in session: LanguageModelSession, of model: SystemLanguageModel) async -> String? {
        do {
            if #available(iOS 26.4, macOS 26.4, *) {
                let spent = try await model.tokenCount(for: session.transcript)
                guard spent + Self.reservedLineTokens < model.contextSize else { return nil }
            }

            let response = try await session.respond(
                to: """
                    Now write the headline alone, and nothing else, \
                    in at most \(Self.maximumTitleWords) words. \
                    Keep only the words that carry information.
                    """,
                generating: GeneratedHeadline.self,
                options: OnDeviceModel.options(maximumTokens: Self.reservedLineTokens)
            )
            let title = response.content.title.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty, Self.isShort(title) else { return nil }
            return title
        } catch {
            OnDeviceModel.refused(error)
            return nil
        }
    }

    /// Asks for the line alone, once, where the headline is settled and the
    /// line is not.
    ///
    /// **A story with a headline and nothing under it is a hole on the page.**
    /// The two are one piece of furniture : the headline says what happened and
    /// the line says what it left out, and the lead of the page wearing the
    /// first half of that is the first thing a reader notices. It happens to
    /// about one story in fifty, which is often enough to land on the lead.
    ///
    /// **Only the line, which is what makes the call worth making.** Everything
    /// else has been settled and accepted, the session still holds what was
    /// written, and the answer is one or two sentences : it is the cheapest
    /// question there is to ask here, where asking for the brief again would
    /// put a headline already approved back in play.
    ///
    /// **And still nothing rather than the article's own** where the third
    /// answer is no better than the first two. Substituted, the story would go
    /// out marked as written by the model with a line the model did not write :
    /// the page draws that mark on the standfirst and nowhere else, and
    /// VoiceOver reads `Written by the model` over it. A headline the model
    /// wrote above no standfirst is the honest shape, and it is what is left
    /// after three tries rather than after two.
    private func line(
        under title: String,
        in session: LanguageModelSession,
        of model: SystemLanguageModel
    ) async -> String? {
        do {
            // **A third question has to fit in the window beside everything
            // already said.** A session carries its whole transcript into every
            // answer : the instructions, the articles, both briefs and both
            // complaints are all still in there, and this is the one call that
            // is optional. Where the window is the smallest the framework has
            // and the story was a long one, the honest answer is not to ask :
            // asked anyway and refused for want of room, the story is stamped
            // as answered and keeps no line at all.
            //
            // Counted where the system can count, and the window read from the
            // device either way.
            if #available(iOS 26.4, macOS 26.4, *) {
                let spent = try await model.tokenCount(for: session.transcript)
                guard spent + Self.reservedLineTokens < model.contextSize else {
                    Log.enrich.notice("No room left in the window to ask for a standfirst of its own")
                    return nil
                }
            }

            let response = try await session.respond(
                to: """
                    Now write the standfirst alone, and nothing else. \
                    One or two sentences, at most \(Self.maximumSummaryWords) words, \
                    saying what the headline left out : who, what, where, why. \
                    Never write the headline again in other words.
                    """,
                generating: GeneratedLine.self,
                options: OnDeviceModel.options(maximumTokens: Self.reservedLineTokens)
            )
            let line = response.content.summary.trimmingCharacters(in: .whitespacesAndNewlines)

            switch Self.fault(of: line, under: title, in: locale) {
            case nil:
                return line

            // Asked three times and long every time is a model writing the way
            // it writes, so what comes back is cut rather than refused again.
            case .tooLong:
                if let kept = Self.shortened(line), Self.fault(of: kept, under: title, in: locale) == nil {
                    return kept
                }
                Log.enrich.notice("A standfirst was a paragraph three times and would not cut to a line")
                return nil

            case .some(let wrong):
                Log.enrich.notice(
                    "A standfirst came back \(wrong.rawValue, privacy: .public) three times, so the story goes without one"
                )
                return nil
            }
        } catch {
            OnDeviceModel.refused(error)
            Log.enrich.notice("The model would not write a standfirst for a story it had already named")
            return nil
        }
    }

    /// What can be wrong with a standfirst.
    ///
    /// The rules are the ones the brief is held to ; what they gain by being
    /// gathered here is a name each. A story that ends up with no line under
    /// its headline is a hole on the page, and a log line saying only that one
    /// appeared says nothing about which rule to look at. One of the four is
    /// also worth doing something about rather than merely reporting : see
    /// ``shortened(_:)``.
    enum Fault: String {
        case empty
        case headlineAgain = "as the headline again"
        case tooLong = "too long"
        case wrongLanguage = "in the wrong language"
    }

    /// What is wrong with a standfirst, or nothing where it will do.
    static func fault(of summary: String, under title: String, in locale: Locale) -> Fault? {
        if summary.isEmpty { return .empty }
        if repeats(title, in: summary) { return .headlineAgain }
        if !isBrief(summary) { return .tooLong }
        if OnDeviceModel.writes(locale), !isWritten(in: locale, title: title, summary: summary) {
            return .wrongLanguage
        }
        return nil
    }

    /// A long answer cut back to the sentences of it that fit.
    ///
    /// **A desk cuts, and cutting is not writing.** These are the model's own
    /// words in its own order, stopped at a full stop : nothing is rephrased,
    /// nothing is joined, and what is dropped is dropped from the end. It is
    /// the last thing tried and not the first, since a model asked again for a
    /// shorter line writes a better one than any cut of the long one.
    ///
    /// **Whole sentences only.** A line stopped mid-thought under a headline is
    /// what a truncated excerpt looks like, which is the thing ``standfirst(from:under:)``
    /// exists to refuse. Where the first sentence alone is a paragraph there is
    /// nothing to keep, and the story goes without a line.
    ///
    /// The tokenizer takes `M. Dupont` for two sentences, as the note on the
    /// word ceiling says. It costs a cut in the wrong place at worst, and only
    /// on the line that was going to be thrown away entirely : a floor of a few
    /// words is what keeps a stray abbreviation from leaving three words under
    /// a headline.
    static func shortened(_ summary: String) -> String? {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = summary

        var kept = ""
        tokenizer.enumerateTokens(in: summary.startIndex..<summary.endIndex) { range, _ in
            let candidate = kept + summary[range]
            guard isBrief(candidate) else { return false }
            kept = candidate
            return true
        }

        let text = kept.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.split(whereSeparator: \.isWhitespace).count >= leastWordsWorthKeeping else { return nil }
        return text
    }

    /// What a cut line has to run to before it is worth putting on the page.
    private static let leastWordsWorthKeeping = 5

    /// How many words a headline may run to.
    ///
    /// Up to about ten sits comfortably in a reader's immediate memory, which
    /// is the length a desk aims for. Twelve is where the line is drawn rather
    /// than ten, so a good headline of eleven words is not thrown away for
    /// being one over the ideal ; past twelve it has stopped being a headline
    /// and become a sentence.
    static let maximumTitleWords = 12

    /// How many words a standfirst may run to.
    ///
    /// A chapeau of one or two sentences runs to about twenty-five or forty
    /// words. Forty-five is generous on purpose : what it is for is the model
    /// that writes a paragraph, and rejecting a good standfirst of forty-two
    /// words costs the reader a real line for nothing, since what replaces it
    /// is the article's own.
    static let maximumSummaryWords = 45

    /// Whether a standfirst has stayed a standfirst.
    static func isBrief(_ summary: String) -> Bool {
        summary.split(whereSeparator: \.isWhitespace).count <= maximumSummaryWords
    }

    /// Whether a headline is short enough to be one.
    ///
    /// Asked for ten words a small model gives fifteen about as often as not,
    /// and the instruction alone does not hold it. Counted on whitespace, so an
    /// elision is the one word it is : `l'étude` is not two.
    static func isShort(_ title: String) -> Bool {
        title.split(whereSeparator: \.isWhitespace).count <= maximumTitleWords
    }

    /// Whether the line under a headline is the headline again.
    ///
    /// The two are one piece of furniture and they divide the work between
    /// them : the headline says what happened, the standfirst says what the
    /// headline had no room for. A standfirst that restates it has spent the
    /// only line the story gets saying nothing new.
    ///
    /// Deliberately narrow. It catches the shape that actually comes back, the
    /// headline repeated with a clause bolted on, and leaves alone a standfirst
    /// that happens to name the same subject while going on to say something :
    /// `La réforme du calendrier scolaire` will and should appear in a line
    /// about the reform of the school calendar, and rejecting that would reject
    /// most of what the model writes correctly.
    static func repeats(_ title: String, in summary: String) -> Bool {
        if says(title, in: summary) { return true }

        // **And a line whose first sentence is the headline has already spent
        // itself**, whatever it goes on to say. `La Russie revendique des
        // frappes dans les régions de Kiev et d'Odessa. Vladimir Poutine
        // justifie les frappes de représailles.` came back from the model and
        // passed : the whole line adds enough words to look like it is saying
        // something, and the reader is still reading the headline twice before
        // reaching any of it.
        guard let stop = summary.firstIndex(where: { ends.contains($0) }) else { return false }
        return says(title, in: String(summary[summary.startIndex...stop]))
    }

    /// Whether one is the other with nothing worth reading added.
    private static func says(_ title: String, in text: String) -> Bool {
        let title = fold(title)
        let text = fold(text)
        guard !title.isEmpty, text.contains(title) else { return false }

        let added = text.split(separator: " ").count - title.split(separator: " ").count
        return added < wordsThatWouldBeWorthIt
    }

    /// How much a standfirst has to add before it has earned its line.
    private static let wordsThatWouldBeWorthIt = 5

    /// Case and accents away, so a repeat is caught however it was spelled.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// A headline without the furniture a template staples to it.
    ///
    /// `| Letters`, `| First Thing`, `| Polly Toynbee` : the section, the
    /// newsletter or the columnist, put after the headline by whichever system
    /// built the feed rather than by whoever wrote the piece. It says where the
    /// article ran and never what happened, and at the head of a story it is
    /// read as part of the headline.
    ///
    /// Only what follows the last pipe, only where that is short, and only
    /// where what stands before it is still a headline : a headline that
    /// happens to contain a pipe keeps it.
    static func plainTitle(_ title: String) -> String {
        guard let pipe = title.range(of: "|", options: .backwards) else { return title }

        let head = String(title[title.startIndex..<pipe.lowerBound]).trimmingCharacters(in: .whitespaces)
        let tail = String(title[pipe.upperBound...]).trimmingCharacters(in: .whitespaces)

        guard !tail.isEmpty, tail.split(whereSeparator: \.isWhitespace).count <= 5,
            head.split(whereSeparator: \.isWhitespace).count >= 4
        else { return title }

        return head
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

    static func prompt(for articles: [(title: String, excerpt: String?)], language: String) -> String {
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
