//
//  TopicNamer.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import OSLog

/// What came of asking the model to file one story.
///
/// **Three answers, not two.** The first version gave back an optional list,
/// which folded a model that chose nothing into a model that could not be
/// asked. The caller then stamped the story as asked either way, so one
/// guardrail refusal, one rate limit or one moment with the assets unloaded
/// left a story unfiled for good : it is never asked again, and the reader sees
/// a fil with no thématique and no way to give it one.
///
/// It is ``Answered`` now, and the two other callers draw the same three : the
/// distinction was written out three times in three files, and derived from the
/// same line of triage each time.
typealias Filing = Answered<[String]>

/// Files stories under the subjects the reader already has.
///
/// A story is one event ; a subject is the field several events belong to. The
/// difference is what makes the pills worth having : filtering by `Éducation`
/// says something the list of stories underneath does not already say, whereas
/// a pill per story would be the same page twice.
///
/// **One story per call, and the answer chosen from a list.** The first version
/// showed the model thirty numbered headlines and asked which numbers fell under
/// which subjects. That is index bookkeeping, which a small model does badly :
/// it filed wildfires under `Sport` and a page of security advisories under
/// `Économie · Sport · Politique`, every number in range and every one wrong.
/// Asked about one headline at a time, against a list it must choose from, it
/// has nothing to keep track of and cannot answer something that is not a
/// subject.
///
/// **The list is the whole of the vocabulary and there is no way out of it.**
/// The model used to be allowed one subject of its own where nothing it was
/// shown fitted, and what came of that was a drift of near synonyms : `Science`
/// beside `Sciences`, `Sports` beside `Sport`, the English word for a section
/// the reader already had. It names nothing now. The catalogue of sections and
/// whatever the reader wrote is what there is, and a story is filed under one
/// or two of those or under none.
nonisolated struct TopicNamer: Sendable {
    /// How many subjects a story is allowed.
    ///
    /// Two. Given more, the model uses more : the page that prompted this
    /// carried four subjects on one story, of which one was right.
    static let subjectsPerStory = 2

    /// What a filing answer is allowed to cost.
    ///
    /// Two short labels chosen from a list. The cap is loose enough that a
    /// structured answer is never cut off in the middle, which would come back
    /// as a `decodingFailure` and read as a refusal.
    static let filingTokens = 128

    let locale: Locale

    /// Who answers this question, and how patient to be with them.
    let hand: ModelHand

    init(locale: Locale = .current, hand: ModelHand = ModelDesk.shared.hand(for: .subjects)) {
        self.locale = locale
        self.hand = hand
    }

    private var instructions: String {
        """
        You file one news headline under the subjects a reader already has.
        A subject is a field of interest, not a single event.
        Choose only from the subjects you are given. Choose the fewest that fit.
        Prefer the most exact subject over a broader one that would also do.
        Every headline belongs under at least one of them : choose the closest \
        when none is exact, and never answer with nothing.
        Never mention that you are a model or that you were asked anything.
        """
    }

    /// The subjects one story belongs to, chosen from the vocabulary.
    ///
    /// **There is no way out of this one.** The list it is shown is the
    /// sections every newspaper has plus whatever the reader wrote, and a news
    /// headline that belongs under none of `Politique`, `Économie`,
    /// `International`, `Société` and the rest is rare enough that offering an
    /// escape costs more than it saves : the model took it constantly, and a
    /// page where half the stories are filed under nothing is a page whose
    /// pills say nothing.
    ///
    /// What it does not do is invent, and there is no longer a pass in which it
    /// may. The schema is an enumeration of the names it was given, so it
    /// cannot answer something that is not one of them, and nothing else writes
    /// to the vocabulary : it is the seeded catalogue and the reader's own, and
    /// nothing else.
    func file(_ headline: String, summary: String?, into vocabulary: [String]) async -> Filing {
        guard hand.isAvailable else { return .unusable }

        // **An empty vocabulary is not an answer about this story.** It used to
        // give back an empty choice, which reads as the model having considered
        // the story and placed it under nothing : the caller stamped it as
        // asked and never came back to it. Nothing had been asked at all. A
        // migration that left every existing subject marked as the model's own
        // emptied this list for one run, and a whole page of stories was
        // stamped as answered by a question nobody ever put.
        guard !vocabulary.isEmpty else {
            Log.enrich.notice("There is no subject to file a story under yet")
            return .unusable
        }

        // The general model, and not `contentTagging`, which looks like the
        // obvious choice and was measured to be worse. See
        // ``LocalProvider/model(for:)``.
        let conversation = hand.conversation(saying: instructions)

        do {
            let answer = try await conversation.answer(
                to: Self.prompt(headline, summary: summary),
                shaped: Self.shape(for: vocabulary),
                keeping: Self.filingTokens
            )
            let chosen = try answer.strings(Called.subjects)
            hand.patience.succeeded()

            return .wrote(chosen.filter { vocabulary.contains($0) })
        } catch let fault as ModelFault {
            hand.patience.refused(fault)
            return Filing(failing: fault)
        } catch {
            // The answer was not the shape asked for, which is this headline
            // and not the model.
            return .declined
        }
    }

    /// A shape the model cannot answer outside of.
    ///
    /// The subjects are the choices of the answer rather than words in a
    /// prompt, so `Cybersécurité` cannot come back as `Cyber sécurité` and a
    /// subject nobody has cannot come back at all.
    ///
    /// **Read back through the vocabulary all the same.** A shape is a promise
    /// about the form of an answer and not about its values, and a service that
    /// honours a schema loosely will send a word that was never offered. The
    /// filter below is what makes that harmless, and it is why it stays.
    static func shape(for vocabulary: [String]) -> ResponseShape {
        .object(
            named: "Filing",
            fields: [
                .init(
                    Called.subjects,
                    "The subjects this headline is about",
                    .list(
                        of: .oneOf(named: "Subject", choices: vocabulary),
                        least: 1,
                        most: subjectsPerStory
                    )
                )
            ]
        )
    }

    /// The name of the one field, written once and read once.
    private enum Called {
        static let subjects = "subjects"
    }

    private static func prompt(_ headline: String, summary: String?) -> String {
        guard let summary, !summary.isEmpty else { return "Headline : \(headline)" }
        return "Headline : \(headline)\n\(String(summary.prefix(240)))"
    }
}
