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

/// What an edition says : a few points, and nothing over them.
nonisolated struct EditionBrief: Hashable, Sendable {
    let points: [String]
    /// The language the model was asked in, which is what stops an edition
    /// being asked about for ever. A refusal has no language of its own, so it
    /// is the language asked in and never the language written in.
    let askedIn: Locale
}

/// The shape the model fills in for a whole page.
@Generable
nonisolated struct GeneratedEditionPoints {
    @Guide(description: EditionSummarizer.pointGuide, .maximumCount(EditionSummarizer.mostPoints))
    var points: [String]
}

/// Writes the few points an edition wears over its ten stories.
///
/// **There is no headline over them, and there was.** An edition carried a name
/// of its own, and every real page showed the same thing : the name was the
/// list said again in fewer words. Asked to say what the stories added up to it
/// reached for an abstraction, `Le monde en mouvement` over a rescue in Nepal
/// and a migration policy ; refused that, it welded two of them into one
/// sentence, which claims a connection the page does not make ; refused that,
/// it wrote the lead's own headline, which the page then read twice. Three
/// rules, three checks, three single-field asks, and a mend by hand at the end
/// of it, all to produce a line that said what the three lines under it already
/// said.
///
/// A front page has never had a name. The masthead says which paper and the
/// dateline says which edition, and what is on the page is what is on the page.
/// So the dateline says `Édition du matin, 07:00` and the list says the rest.
///
/// What is left is one question to the model, and the checks that survive are
/// the two that are about the reader rather than about style : the list is a
/// list, and it is in the language they read in.
nonisolated struct EditionSummarizer: Sendable {
    /// How many points an edition ever carries.
    ///
    /// **Three, and it was a paragraph.** Asked for two or three sentences
    /// over ten stories the model wrote one clause per story and joined them
    /// with commas : seven items and eight lines of type under the headline,
    /// which is the shape a reader's eye slides off. It was cut to five, which
    /// was still most of a screen before the first headline. Three is what an
    /// edition is actually about, and what is left is on the page underneath.
    static let mostPoints = 3

    /// The fewest worth calling a list.
    ///
    /// Two. One point on its own is a standfirst written the long way, and a
    /// page that came back with one is a page to ask about again.
    static let leastPoints = 2

    /// What the model is asked for, written once.
    ///
    /// **Interpolated rather than typed out.** The guide said `at most 100
    /// characters` as a literal while the constant under it said a hundred and
    /// the page's own doc comment said a hundred and twenty : a bound written in
    /// three places is a bound that stopped agreeing with itself the first time
    /// one of the three was changed, and it had.
    static let pointGuide =
        "The two or three things worth knowing, one short sentence of at most "
        + "\(maximumPointWords) words each, no numbering"

    /// How many words one point may run to.
    ///
    /// **Words and not characters, because the page has stopped counting
    /// lines.** The old bound was a hundred characters and its argument was
    /// sound as far as it went : a point stood on three lines at most, and what
    /// fills a line is letters. The premise was measured across the six hundred
    /// and eighty point measure, where three lines of body hold about two
    /// hundred characters and a hundred is comfortable. The page it shipped to
    /// was a phone, where the same three lines hold about a hundred and ten and
    /// the bound sat exactly at the edge ; and then the reader turns their type
    /// up, and at the largest of the ordinary sizes three lines hold about
    /// seventy-five. So the bound was reasoned against an iPad and shipped to a
    /// pocket, and what a reader above the default size met was a sentence
    /// ending in an ellipsis, which is the one thing the bound existed to stop.
    ///
    /// A line count is a promise the writing cannot keep : it depends on the
    /// column, the face, the type size and the platform, none of which the model
    /// can be told and all of which the reader may change while the edition is
    /// on the screen. So the words bound the thought and the lines are left to
    /// the layout, which is the only thing that knows how wide the page is.
    /// Nothing truncates a point anywhere now, so there is no third line left to
    /// protect : see ``EditionPoints``.
    ///
    /// **And a bound in characters was quietly two different bounds.** A word
    /// and the space after it come to about six characters in French and five
    /// and a half in English, so a hundred characters was sixteen French words
    /// and seventeen or eighteen English ones : the same rule gave a French
    /// reader less to be told than an English one, for no reason anybody chose.
    ///
    /// **Eighteen, and the arithmetic is the old bound's own.** A hundred
    /// characters was about sixteen or seventeen words all along, so this is the
    /// same length said in the unit that survives a change of column, with a
    /// word of slack on top : rejecting a good point of seventeen words costs
    /// the reader a real line for nothing, since what replaces a rejected point
    /// is a worse one. It is the generosity ``StorySummarizer/maximumSummaryWords``
    /// is set with, and for that reason.
    ///
    /// It also sits where a point belongs. A headline is held to twelve words
    /// and says one thing ; a standfirst of one or two sentences to forty-five.
    /// A point is one sentence saying what happened and the circumstance that
    /// makes it worth knowing, which is a headline and a clause : `A Russian
    /// drone hit the SBU headquarters in Kyiv` is nine words and `Une attaque
    /// russe a frappé le siège du SBU à Kiev` is eleven, and eighteen leaves
    /// either of them the clause. Past eighteen a sentence has stopped being one
    /// thing said and become two joined with a comma, which is the paragraph
    /// this whole list was made to replace.
    ///
    /// It is still the model that is held to it rather than the page : a page
    /// that cut a point to fit would be a page throwing away the end of a
    /// sentence, and one that set it smaller to fit would be a page whispering
    /// the news.
    static let maximumPointWords = 18

    /// What is kept for the answer, whatever the prompt costs.
    static let reservedTokens = 500

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

    /// Says what is on the page, in a few points.
    ///
    /// Both voices are tried, exactly as they are for a story and for the same
    /// measured reason : a third of a news reader's pages carry a war, a flood
    /// or a court report, and the writing voice refuses those outright. A page
    /// of ten published headlines said in five lines is a transformation of
    /// published text, and saying so is what gets it written.
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

            let prompt = Self.prompt(for: stories, language: OnDeviceModel.languageReminder(for: locale))

            if #available(iOS 26.4, macOS 26.4, *) {
                let cost = try await model.tokenCount(for: prompt)
                guard cost + Self.reservedTokens < model.contextSize else {
                    Log.enrich.notice("An edition was too long to write, and was left unwritten")
                    return .unusable
                }
            }

            let generated = try await session.respond(
                to: prompt,
                generating: GeneratedEditionPoints.self,
                options: OnDeviceModel.options(maximumTokens: Self.reservedTokens)
            ).content

            let points = Self.tidied(generated.points)

            // An empty answer is the model answering nothing about this page,
            // which is not the model being unusable.
            guard !points.isEmpty else { return .declined }
            OnDeviceModel.succeeded()

            // One ask about what is wrong, and never a second : sampling is
            // greedy, and a model asked a third time answers what it answered
            // the first, the session holding the two asks that did not work.
            var list = points
            if Self.fault(list, over: stories) != nil,
                let better = await listed(again: list, in: session, over: stories)
            {
                list = better
            }

            // **What is in hand stands if the asking did not improve it.** The
            // length of a point is style, and the rule over it is not : every
            // edition carries a list the model wrote, without exception, and an
            // edition declined is a front page that does not exist.
            //
            // The language is the one that is not style. A page in a language
            // the reader does not read is not a page they can use, and there is
            // no floor under it to fall back to : an edition exists only where
            // the model wrote it.
            guard Self.languageFault(list, in: locale) == nil else { return .declined }

            return .wrote(EditionBrief(points: list, askedIn: locale))
        } catch {
            // A rate limit, an asset still downloading or a language this model
            // does not write says nothing about this page, and stamping the
            // edition would leave it unwritten for good on a device that was
            // busy for a second.
            OnDeviceModel.refused(error)
            return OnDeviceModel.isTheModelItself(error) ? .unusable : .declined
        }
    }

    /// The list asked for again, once.
    private func listed(
        again points: [String],
        in session: LanguageModelSession,
        over stories: [(title: String, summary: String?)]
    ) async -> [String]? {
        guard let fault = Self.fault(points, over: stories) else { return nil }

        do {
            let generated = try await session.respond(
                to: "\(fault) Write only the points : two or three things worth knowing, one short sentence "
                    + "each, no numbering.",
                generating: GeneratedEditionPoints.self,
                options: OnDeviceModel.options(maximumTokens: Self.reservedTokens)
            ).content

            let better = Self.tidied(generated.points)
            guard !better.isEmpty, Self.fault(better, over: stories) == nil else { return nil }

            OnDeviceModel.succeeded()
            return better
        } catch {
            OnDeviceModel.refused(error)
            return nil
        }
    }

    /// The first thing wrong with a list, said as the sentence that asks for it
    /// again.
    static func fault(_ points: [String], over stories: [(title: String, summary: String?)]) -> String? {
        let sources = stories.map { (title: $0.title, excerpt: $0.summary) }
        // The model is shown headlines and standfirsts and nothing else, so it
        // has nothing to date anything by, and a model of this size fills that
        // gap rather than leaving it. The page already says when every story on
        // it arrived, to the minute.
        if StorySummarizer.inventedYear(title: "", summary: points.joined(separator: " "), from: sources) != nil {
            return "One of those points gives a date. Write them again with no date, no year and no day."
        }
        if points.count < leastPoints {
            return "That is not a list. Write two or three things worth knowing, one short sentence each."
        }
        if repeated(points) {
            return
                "Two of those points say the same thing. Write them again, one thing to a point, with nothing said twice."
        }
        if let long = points.first(where: { !isBrief($0) }) {
            return
                "This point is too long : \(long). Write every point again in one sentence of at most \(maximumPointWords) words."
        }
        return nil
    }

    /// Whether what came back is in the language it was asked in.
    static func languageFault(_ points: [String], in locale: Locale) -> String? {
        guard OnDeviceModel.writes(locale) else { return nil }
        let written = StorySummarizer.isWritten(in: locale, title: "", summary: points.joined(separator: " "))
        return written ? nil : OnDeviceModel.languageReminder(for: locale)
    }

    /// Whether two points are about the same thing.
    ///
    /// **It happens, and it is the worst thing a list of three can do.** A page
    /// led by one story big enough to be written about twice came back with
    /// `Une attaque russe a frappé le siège du SBU à Kiev` and, under it, the
    /// same sentence in other words : a third of the edition spent saying one
    /// thing, and a reader who has to compare two lines to notice they are one.
    ///
    /// Compared by the words they are made of rather than by their letters,
    /// since the model rephrases rather than repeats. Two points sharing most
    /// of what either of them is about are one point.
    static func repeated(_ points: [String]) -> Bool {
        let spoken = points.map { Set(TextSignatures.terms(of: $0)) }

        for (index, terms) in spoken.enumerated() where terms.count >= 2 {
            for other in spoken[(index + 1)...] where other.count >= 2 {
                let shared = terms.intersection(other).count
                if Double(shared) / Double(min(terms.count, other.count)) >= sameThing { return true }
            }
        }
        return false
    }

    /// What share of the smaller point's words two points may share before they
    /// are the same point.
    ///
    /// Two thirds. Below that, two points about one subject still say two
    /// things : a strike and the arrests that followed it share the place and
    /// nothing else.
    static let sameThing = 0.66

    /// Whether one point has stayed one thing worth knowing.
    ///
    /// Counted on whitespace, exactly as a headline and a standfirst are, so an
    /// elision is the one word it is : `l'étude` is not two. Two bounds that
    /// counted differently would be counting two different things.
    static func isBrief(_ point: String) -> Bool {
        point.split(whereSeparator: \.isWhitespace).count <= maximumPointWords
    }

    /// What comes back, put in the shape the page draws.
    ///
    /// **Bounded here as well as asked for.** `maximumCount` guides the model
    /// and does not bind it, and a page drawn from an answer that ignored the
    /// guide would be the paragraph this replaced with rules in front of it.
    ///
    /// The numbering a model puts in front of its own list items comes off :
    /// asked for a list it writes `1. ` or `- ` about half the time, and the
    /// page draws its own marks.
    static func tidied(_ points: [String]) -> [String] {
        points
            .map { point in
                var text = point.trimmingCharacters(in: .whitespacesAndNewlines)
                while let first = text.first, first.isNumber || first == "." || first == "-" || first == ")" {
                    text.removeFirst()
                    text = text.trimmingCharacters(in: .whitespaces)
                }
                return text
            }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { kept, point in
                // **Asked for again, and dropped if it comes back.** The model
                // is told when two of its points say one thing, and it usually
                // writes them again ; when it does not, the page shows what is
                // left rather than the same news twice. Two points is still a
                // list, and one thing said twice is not.
                guard !repeated(kept + [point]) else { return }
                kept.append(point)
            }
            .prefix(mostPoints)
            .map { $0 }
            .withinTheBound()
    }

    /// What the model is shown : the ten heads, in the order the page shows
    /// them, and nothing else.
    static func prompt(for stories: [(title: String, summary: String?)], language: String) -> String {
        let lines = stories.map { story in
            guard let line = story.summary.map({ String($0.prefix(lineShown)) }), !line.isEmpty else {
                return "- \(story.title)"
            }
            return "- \(story.title) : \(line)"
        }

        return """
            These are the stories on the reader's front page, in the order the page shows them. \
            List the two or three things worth knowing.

            \(lines.joined(separator: "\n"))

            \(language)
            """
    }

    /// The writing voice.
    ///
    /// The rules a headline is held to, said over a list rather than over one
    /// story. There is no name to write, so there is nothing here about naming
    /// one : a front page has never had a name, and every attempt at one said
    /// what the list already said.
    static let instructions = """
        You are the editor of a daily digest, writing the few lines that stand at the top of one edition.

        Two or three things worth knowing, one short sentence each, one thing to a line, in the order they \
        matter. Every word carries information : a fact, a figure, a named actor or a verb of action. \
        No jargon, no abstraction, no wordplay.

        Say what happened, not who said it. Write `A Russian drone hit the SBU headquarters in Kyiv`, \
        never `The president says a Russian drone hit the SBU headquarters in Kyiv`. Name the speaker only \
        where the speaking is itself the news, as in a resignation, a denial or a decision announced.

        No numbering and no bullet characters, the page draws its own. Never say more than these stories \
        say. Never give a date, a year or a day. Never end a line with `and more` or anything like it.
        """

    /// The condensing voice, for a page the first one will not touch.
    ///
    /// Word for word the same rules. What changes is the description of the
    /// work : ten published headlines said in five lines is a transformation of
    /// published text and not an opinion about a war, and saying so is what
    /// gets a page of ordinary news written at all.
    static let condensing = """
        You are given headlines that have already been published, by news organizations the reader subscribes \
        to. Your task is to condense them : to say in a few lines what these published headlines say. \
        You are not writing about the events. You are restating what has already been written.

        Two or three of them, restated, one short sentence each, one to a line, in the order they matter. \
        Restate what happened rather than who reported it : `A Russian drone hit the SBU headquarters in \
        Kyiv`, never `The president says a Russian drone hit the SBU headquarters in Kyiv`. Name the \
        speaker only where the speaking is itself the news. No numbering and no bullet characters. Never \
        say more than these headlines say. Never give a date, a year or a day.
        """
}

nonisolated extension Array where Element == String {
    /// The points that fit, unless dropping the rest would leave no list.
    ///
    /// **It was a safety valve and it is a courtesy.** The page held a point to
    /// three lines and never cut one, so a point the model would not shorten had
    /// to be left out : shown, it reached the cap and was drawn with its last
    /// words missing, which is the one thing this list must not do. That made
    /// this escape hatch the dangerous part of the arrangement, since it is
    /// exactly what let an over-long point through. The page caps no lines now,
    /// so what gets through here is a point running a line further down the
    /// pane, whole, which is a worse point and not a broken one.
    ///
    /// The rule still gives way rather than the page, for the reason it always
    /// did : a bound set a few words too tight would take every point of an
    /// edition out at once and show the reader a pane with nothing on it. Where
    /// what fits is not a list any more, what came back stands as it came back,
    /// at whatever length it came back, and it is drawn whole.
    func withinTheBound() -> [String] {
        let fitting = filter(EditionSummarizer.isBrief)
        return fitting.count >= EditionSummarizer.leastPoints ? fitting : self
    }
}
