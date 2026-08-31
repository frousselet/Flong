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
    /// What it does not do is invent. The schema is an enumeration of the names
    /// it was given, so it cannot answer something that is not one of them.
    /// Inventing is the second pass and is deliberately separate.
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

    /// A subject of the model's own for a story, beside the settled one it was
    /// already filed under.
    ///
    /// **Every story gets one, not only the ones that fit nothing.** The
    /// standard sections say what kind of news a story is ; this says what the
    /// story is actually about, which is the finer thing a reader following a
    /// subject is following. `Politique` and `Réforme des retraites` are both
    /// true of one story and only the second is worth a pill of its own.
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
                    It must tell this story apart from the rest of the news.
                    Never a word that would fit every article ever published, such as news or information.
                    One or two words, each carrying information. Never the headline, never a name, never a date.
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
            // the time. `Les macros Swift` is not a field ; `Logiciel` is. And
            // asked not to do that, it reaches for `Actualité`, which is the
            // opposite fault and needs the opposite thing said about it.
            if let fault = Self.fault(in: name, of: headline, locale: locale) {
                response = try await session.respond(
                    to: Self.complaint(about: fault),
                    generating: GeneratedTopic.self,
                    options: OnDeviceModel.options(maximumTokens: Self.namingTokens)
                )
                name = response.content.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            OnDeviceModel.succeeded()
            guard let fault = Self.fault(in: name, of: headline, locale: locale) else { return name }

            // Twice is enough. The story keeps the section it was filed under,
            // which is a real subject a reader recognizes ; a second one of the
            // model's own is a nicety, and a bad one is worse than none.
            Log.enrich.notice("The model would not name a subject : \(String(describing: fault), privacy: .public)")
            return nil
        } catch {
            OnDeviceModel.refused(error)
            return nil
        }
    }

    /// Why a proposed subject is not one.
    ///
    /// Two faults, and they need different things said about them : a model
    /// that answered with the headline has to be told to step back, and one
    /// that answered with a word for news itself has to be told to step in.
    /// Telling it the wrong one of those gets the other fault back.
    nonisolated enum NotASubject: Sendable {
        /// The headline again, or something too long to be a field.
        case theStoryItself
        /// A word that would fit every article ever published.
        case theWholePage
    }

    /// What is wrong with a proposed subject, or nothing.
    ///
    /// **Short, and not lifted out of the headline.** A model asked for a field
    /// and given one headline answers with that headline about half the time,
    /// and a vocabulary of headlines is a vocabulary with one story in each.
    ///
    /// **And narrower than the page.** `Actualité` is true of every story there
    /// is, so filing under it sorts nothing and a pill wearing it says
    /// `everything`. It is the same rule that governs a headline, that every
    /// word must carry information, applied to a single word where it is at its
    /// sharpest. Whole names only : `Actualité internationale` is narrower than
    /// the page and is left alone.
    static func fault(in name: String, of headline: String, locale: Locale = .current) -> NotASubject? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 30 else { return .theStoryItself }

        let folded = TopicPreferences.fold(name)
        guard (1...3).contains(folded.split(separator: " ").count) else { return .theStoryItself }
        guard !TopicPreferences.fold(headline).contains(folded) else { return .theStoryItself }

        let general = StandardTopics.generalNames(for: locale).map(TopicPreferences.fold)
        guard !general.contains(folded) else { return .theWholePage }

        return nil
    }

    /// Whether a proposed subject is one at all.
    static func isField(_ name: String, of headline: String, locale: Locale = .current) -> Bool {
        fault(in: name, of: headline, locale: locale) == nil
    }

    /// What to tell the model about the subject it just proposed.
    private static func complaint(about fault: NotASubject) -> String {
        switch fault {
        case .theStoryItself:
            "That is the story, not the field it belongs to. Answer with the field."
        case .theWholePage:
            """
            That word fits every article ever published, so it sorts nothing. \
            Answer with the field this story belongs to and no other.
            """
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
