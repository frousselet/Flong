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

/// A subject the model proposes when nothing it was shown fits.
@Generable
nonisolated struct GeneratedTopic {
    @Guide(description: "The subject, one or two words, capitalized as a title")
    var name: String
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
/// The list is the reader's vocabulary, its own past answers and the reader's
/// own additions alike, plus one way out. Taking that way out is the only time
/// it is asked to name anything.
nonisolated struct TopicNamer: Sendable {
    /// How many subjects a story is allowed.
    ///
    /// Two. Given more, the model uses more : the page that prompted this
    /// carried four subjects on one story, of which one was right.
    static let subjectsPerStory = 2

    /// What the model picks when the vocabulary has nothing for this story.
    static let noneOfThese = "None of these"

    /// What a filing answer is allowed to cost.
    ///
    /// Two short labels chosen from a list. The cap is loose enough that a
    /// structured answer is never cut off in the middle, which would come back
    /// as a `decodingFailure` and read as a refusal.
    static let filingTokens = 128
    /// A field is one or two words, and the check that follows rejects more.
    static let namingTokens = 64

    let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    private var instructions: String {
        """
        You file one news headline under the subjects a reader already has.
        A subject is a field of interest, not a single event.
        Choose only from the subjects you are given. Choose the fewest that fit.
        Choose \(Self.noneOfThese) when none of them is about this headline.
        Never mention that you are a model or that you were asked anything.
        """
    }

    /// The subjects one story belongs to, chosen from the vocabulary.
    ///
    /// An empty choice is the model saying this story falls under nothing it
    /// was shown, which is what `newSubject` is for. A vocabulary with nothing
    /// in it is the same answer reached without asking.
    func file(_ headline: String, summary: String?, into vocabulary: [String]) async -> Filing {
        guard OnDeviceModel.isAvailable else { return .unusable }
        guard !vocabulary.isEmpty else { return .chosen([]) }

        do {
            let schema = try Self.schema(for: vocabulary)
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

            // The way out is not a subject, and choosing it beside real ones
            // means it fits those.
            return .chosen(chosen.filter { $0 != Self.noneOfThese && vocabulary.contains($0) })
        } catch {
            OnDeviceModel.refused(error)
            return OnDeviceModel.isTheModelItself(error) ? .unusable : .declined
        }
    }

    /// A subject for a story that fits nothing the reader has.
    ///
    /// Free text, and the only time the model is allowed to name anything. What
    /// it answers is folded against the vocabulary before it is kept, so a
    /// second spelling of a subject that exists is not a second subject.
    func newSubject(for headline: String, summary: String?) async -> String? {
        guard OnDeviceModel.isAvailable else { return nil }

        do {
            let session = LanguageModelSession(
                // Naming is writing, not tagging : the general model, which is
                // the one that writes the reader's language.
                model: OnDeviceModel.model(),
                instructions: """
                    You name the field of interest a news headline belongs to.
                    A field is what a section of a newspaper is called : it outlives any one story.
                    One or two words. Never the headline, never a name, never a date.
                    \(OnDeviceModel.languageInstruction(for: locale))
                    Answer with the field and nothing else.
                    """
            )
            let asked = """
                \(Self.prompt(headline, summary: summary))

                \(OnDeviceModel.languageReminder(for: locale))
                """

            var response = try await session.respond(
                to: asked,
                generating: GeneratedTopic.self,
                options: OnDeviceModel.options(maximumTokens: Self.namingTokens)
            )
            var name = response.content.name.trimmingCharacters(in: .whitespacesAndNewlines)

            // Measured : asked once, it answers with the headline about half
            // the time. `Les macros Swift` is not a field ; `Logiciel` is.
            if !Self.isField(name, of: headline) {
                response = try await session.respond(
                    to: "That is the story, not the field it belongs to. Answer with the field.",
                    generating: GeneratedTopic.self,
                    options: OnDeviceModel.options(maximumTokens: Self.namingTokens)
                )
                name = response.content.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            OnDeviceModel.succeeded()
            guard Self.isField(name, of: headline) else {
                Log.enrich.notice("The model named a story rather than a subject, twice")
                return nil
            }
            return name
        } catch {
            OnDeviceModel.refused(error)
            return nil
        }
    }

    /// Whether a proposed subject is a field rather than the story itself.
    ///
    /// Short, and not lifted out of the headline. A model asked for a field
    /// and given one headline answers with that headline about half the time,
    /// and a vocabulary of headlines is a vocabulary with one story in each.
    static func isField(_ name: String, of headline: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 30 else { return false }

        let words = TopicPreferences.fold(name).split(separator: " ")
        guard (1...3).contains(words.count) else { return false }

        // Nothing the headline already says.
        let folded = TopicPreferences.fold(headline)
        return !folded.contains(TopicPreferences.fold(name))
    }

    /// A schema the model cannot answer outside of.
    ///
    /// The subjects are the values of an enumeration rather than words in a
    /// prompt, so `Cybersécurité` cannot come back as `Cyber sécurité` and a
    /// subject nobody has cannot come back at all.
    static func schema(for vocabulary: [String]) throws -> GenerationSchema {
        let choice = DynamicGenerationSchema(name: "Subject", anyOf: vocabulary + [noneOfThese])
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
