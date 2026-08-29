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
/// Where there is no model there are no topics, and the page is the front page.
/// Section 14 asks for the path without the model to be entire, and a front page
/// is entire : the pills are a way of narrowing it, never the only way in.
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

    /// Under this many stories, a subject is not a subject.
    ///
    /// A pill covering one story is a pill that says what the story underneath
    /// already says, and six pills for six stories is a page of buttons.
    static let minimumStories = 2

    let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    private var instructions: String {
        """
        You group news headlines under a few broad subjects.
        \(OnDeviceModel.languageInstruction(for: locale))
        A subject is a field, not an event : `Education`, `Software`, `Typography`.
        Never invent a headline, and never use a number you were not given.
        Never mention that you are a model or that you were asked anything.
        """
    }

    /// The subject of each story, for the stories the model put under one.
    ///
    /// Stories it leaves out keep no topic, which is right : they are still on
    /// the front page, they are simply on no pill.
    func topics(of stories: [(id: UUID, title: String)]) async -> [UUID: String] {
        guard OnDeviceModel.isAvailable, stories.count >= Self.minimumStories else { return [:] }

        let shown = Array(stories.prefix(Self.headlinesShown))
        do {
            let session = LanguageModelSession(instructions: instructions)
            let prompt = Self.prompt(for: shown)

            if #available(iOS 26.4, macOS 26.4, *) {
                let model = SystemLanguageModel.default
                let cost = try await model.tokenCount(for: prompt)

                guard cost + Self.reservedTokens < model.contextSize else {
                    Log.enrich.notice("The page was too long to sort into subjects")
                    return [:]
                }
            }

            let response = try await session.respond(to: prompt, generating: GeneratedTopics.self)
            OnDeviceModel.succeeded()
            return Self.assign(response.content, to: shown)
        } catch {
            OnDeviceModel.refused(error)
            return [:]
        }
    }

    /// Reads the answer back, keeping only what it is entitled to say.
    ///
    /// A model asked for numbers returns numbers, and now and then returns one
    /// that was never on the list. A subject covering a single story is dropped
    /// with it, and a story named twice keeps the first subject that claimed it,
    /// so that every story ends up under exactly one.
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

            guard claimed.count >= minimumStories else { continue }
            for id in claimed { assigned[id] = name }
        }
        return assigned
    }

    private static func prompt(for stories: [(id: UUID, title: String)]) -> String {
        let lines = stories.enumerated().map { index, story in
            "\(index + 1). \(story.title)"
        }

        return """
            Group these headlines under a few broad subjects.

            \(lines.joined(separator: "\n"))
            """
    }
}
