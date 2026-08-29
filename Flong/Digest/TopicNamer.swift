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

/// The subjects the model finds across a page of stories.
@Generable
nonisolated struct GeneratedTopics {
    @Guide(description: "The subjects these headlines fall under", .count(2...6))
    var topics: [GeneratedTopic]
}

@Generable
nonisolated struct GeneratedTopic {
    @Guide(description: "The subject, one or two words, capitalized as a title")
    var name: String

    @Guide(description: "The numbers of the headlines that fall under this subject")
    var headlines: [Int]
}

/// Groups the stories of the page under a handful of named subjects.
///
/// A story is one event ; a topic is the subject several events belong to. The
/// difference is what makes the pills worth having : filtering by `Éducation`
/// says something the list of stories underneath does not already say, whereas
/// a pill per story would be the same page twice.
///
/// This is one call for the whole page rather than one per story. The model is
/// given the headlines, numbered, and answers with the subjects and which
/// numbers fall under each, which is a far smaller thing to ask than naming a
/// subject for a story in isolation, where it has nothing to compare against.
///
/// Where there has never been a model there are no subjects, and the page is
/// the front page. Section 14 asks for the path without the model to be
/// entire, and a front page is entire : the pills are a way of narrowing it,
/// never the only way in.
nonisolated struct TopicNamer: Sendable {
    /// How many headlines the model is shown.
    ///
    /// The window is four thousand tokens for the prompt and the answer
    /// together. Thirty headlines of a dozen words sit well inside it, and a
    /// page showing more than thirty stories has a bigger problem than its
    /// pills.
    static let headlinesShown = 30

    /// What is left for the answer, whatever the prompt turns out to cost.
    static let reservedTokens = 500

    /// How many stories a page needs before its subjects are worth asking for.
    ///
    /// A page of one story has one subject, and a filter with one thing on
    /// each side of it is not a filter.
    ///
    /// A subject covering a single story is kept, though. Dropping those was
    /// measured against the real model and threw away everything : with three
    /// stories on a page the model gives three subjects, each covering one,
    /// and a rule that wants two per subject leaves no subjects at all.
    static let minimumStories = 2

    let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    private var instructions: String {
        """
        You group news headlines under a few broad subjects.
        A subject is a field of interest, not a single event.
        \(OnDeviceModel.languageInstruction(for: locale))
        Never invent a headline, and never use a number you were not given.
        Never mention that you are a model or that you were asked anything.
        """
    }

    /// The subject of each story, for the stories the model put under one, or
    /// `nil` when the model said nothing at all.
    ///
    /// The difference matters. An empty answer is the model saying these
    /// stories fall under no common subject, and the pills go. No answer is
    /// the model being unavailable, or refusing, or the page being too long to
    /// show it, and the subjects already on the page are the best reading
    /// anyone has : blanking them because Apple Intelligence was switched off
    /// for an afternoon would be losing work to a transient.
    ///
    /// Stories the model leaves out keep no subject, which is right : they are
    /// still on the front page, they are simply on no pill.
    func topics(of stories: [(id: UUID, title: String)]) async -> [UUID: String]? {
        guard OnDeviceModel.isAvailable, stories.count >= Self.minimumStories else { return nil }

        let shown = Array(stories.prefix(Self.headlinesShown))
        do {
            let session = LanguageModelSession(instructions: instructions)
            // The language is said twice, in the instructions and again beside
            // the task. A small model asked once at the top answers in the
            // language of the words nearest its answer, and the headlines are
            // nearer than the instructions.
            let prompt = Self.prompt(for: shown, language: OnDeviceModel.languageReminder(for: locale))

            if #available(iOS 26.4, macOS 26.4, *) {
                let model = SystemLanguageModel.default
                let cost = try await model.tokenCount(for: prompt)

                guard cost + Self.reservedTokens < model.contextSize else {
                    Log.enrich.notice("The page was too long to sort into subjects")
                    return nil
                }
            }

            let response = try await session.respond(to: prompt, generating: GeneratedTopics.self)
            OnDeviceModel.succeeded()
            return Self.assign(response.content, to: shown)
        } catch {
            OnDeviceModel.refused(error)
            return nil
        }
    }

    /// Reads the answer back, keeping only what it is entitled to say.
    ///
    /// A model asked for numbers returns numbers, and now and then returns one
    /// that was never on the list. A story named twice keeps the first subject
    /// that claimed it, so that every story ends up under exactly one, and a
    /// subject left holding nothing is dropped.
    static func assign(_ generated: GeneratedTopics, to stories: [(id: UUID, title: String)]) -> [UUID: String] {
        var assigned: [UUID: String] = [:]

        for topic in generated.topics {
            let name = topic.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let claimed =
                topic.headlines
                .compactMap { number -> UUID? in
                    let index = number - 1
                    guard stories.indices.contains(index) else { return nil }
                    return stories[index].id
                }
                .filter { assigned[$0] == nil }

            guard !claimed.isEmpty else { continue }
            for id in claimed { assigned[id] = name }
        }
        return assigned
    }

    private static func prompt(for stories: [(id: UUID, title: String)], language: String) -> String {
        let lines = stories.enumerated().map { index, story in
            "\(index + 1). \(story.title)"
        }

        return """
            Group these headlines under a few broad subjects.
            \(language)

            \(lines.joined(separator: "\n"))
            """
    }
}
