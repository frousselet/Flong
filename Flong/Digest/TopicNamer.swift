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
import FoundationModels
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
/// ``OnDeviceModel/isTheModelItself(_:)`` already draws exactly this line, and
/// the summarizer already acts on it. This is the same distinction, carried far
/// enough to be acted on here too.
nonisolated enum Filing: Sendable {
    /// The model answered. Possibly with nothing, which is an answer : this
    /// story falls under none of the subjects it was shown.
    case chosen([String])
    /// The model would not write about this story. It will not next time
    /// either, so there is no point asking again.
    case declined
    /// The model could not be used at all : unloaded, rate limited, busy. The
    /// next pass may well find it working, so the story keeps its place in the
    /// queue.
    case unusable
}

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

    init(locale: Locale = .current) {
        self.locale = locale
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
        guard OnDeviceModel.isAvailable else { return .unusable }

        // **An empty vocabulary is not an answer about this story.** It used to
        // give back `.chosen([])`, which reads as the model having considered
        // the story and placed it under nothing : the caller stamped it as
        // asked and never came back to it. Nothing had been asked at all. A
        // migration that left every existing subject marked as the model's own
        // emptied this list for one run, and a whole page of stories was
        // stamped as answered by a question nobody ever put.
        guard !vocabulary.isEmpty else {
            Log.enrich.notice("There is no subject to file a story under yet")
            return .unusable
        }

        // Built before the session, and its failure is neither the model's nor
        // this story's : a schema that will not build is a mistake here. It
        // used to be thrown inside the same `do`, where anything that is not a
        // `GenerationError` counts as the model being unusable, so three
        // stories in a row silenced the model for the rest of the run, briefs
        // included.
        guard let schema = try? Self.schema(for: vocabulary) else {
            Log.enrich.error("The filing schema could not be built from \(vocabulary.count) subjects")
            return .unusable
        }

        do {
            // The general model, and not `contentTagging`, which looks like the
            // obvious choice and was measured to be worse. See
            // ``OnDeviceModel/model(for:)``.
            let session = LanguageModelSession(model: OnDeviceModel.model(), instructions: instructions)
            let response = try await session.respond(
                to: Self.prompt(headline, summary: summary),
                schema: schema,
                options: OnDeviceModel.options(maximumTokens: Self.filingTokens)
            )

            let chosen = try response.content.value([String].self, forProperty: "subjects")
            OnDeviceModel.succeeded()

            return .chosen(chosen.filter { vocabulary.contains($0) })
        } catch {
            OnDeviceModel.refused(error)
            return OnDeviceModel.isTheModelItself(error) ? .unusable : .declined
        }
    }

    /// A schema the model cannot answer outside of.
    ///
    /// The subjects are the values of an enumeration rather than words in a
    /// prompt, so `Cybersécurité` cannot come back as `Cyber sécurité` and a
    /// subject nobody has cannot come back at all.
    static func schema(for vocabulary: [String]) throws -> GenerationSchema {
        let choice = DynamicGenerationSchema(name: "Subject", anyOf: vocabulary)
        let list = DynamicGenerationSchema(arrayOf: choice, minimumElements: 1, maximumElements: subjectsPerStory)
        let root = DynamicGenerationSchema(
            name: "Filing",
            properties: [
                .init(name: "subjects", description: "The subjects this headline is about", schema: list)
            ]
        )
        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func prompt(_ headline: String, summary: String?) -> String {
        guard let summary, !summary.isEmpty else { return "Headline : \(headline)" }
        return "Headline : \(headline)\n\(String(summary.prefix(240)))"
    }
}
