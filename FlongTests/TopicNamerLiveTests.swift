//
//  TopicNamerLiveTests.swift
//  FlongTests
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
import Testing

@testable import Flong

/// The digest against the system model itself, where there is one.
///
/// Everything else about the digest is tested without a model, which is what
/// section 14 asks for and what lets the suite run anywhere. This suite exists
/// because that is not enough : a page whose subjects were all dropped by a rule
/// of my own looked exactly like a page with no model at all, and no test
/// without a model could tell the two apart.
///
/// It asserts the shape of what comes back, never its wording : the model is
/// entitled to call a subject whatever it likes.
/// A simulator answers `available` and then fails every call, which is the very
/// case the refusal counter exists for, so it is not a machine this suite can
/// run on.
private var hasWorkingModel: Bool {
    #if targetEnvironment(simulator)
        false
    #else
        OnDeviceModel.isAvailable
    #endif
}

@Suite("The digest, against the real model", .enabled(if: hasWorkingModel), .serialized)
struct TopicNamerLiveTests {
    private let headlines = [
        "Une réforme du calendrier scolaire à l'étude",
        "Calendrier scolaire : trois académies pilotes dès l'an prochain",
        "Rentrée avancée : les syndicats enseignants demandent un report",
        "Les macros Swift, deux ans après",
        "Bilan des macros Swift dans les projets réels",
        "Pourquoi les caractères grotesques reviennent",
        "Le retour des grotesques dans la presse imprimée",
    ]

    /// English articles, a French reader : the case the screenshot showed.
    private let english = [
        "Microsoft releases security updates for SharePoint Server",
        "Citrix publishes advisories for NetScaler ADC and Gateway",
        "PaperCut warns of an active exploit in its print management software",
    ]

    @Test("A brief for English articles is written in the reader's language")
    func briefOfEnglishArticles() async throws {
        let articles = english.map { (title: $0, excerpt: Optional($0)) }
        let brief = await StorySummarizer(locale: Locale(identifier: "fr_FR")).brief(forArticles: articles)

        let summary = try #require(brief.summary)
        #expect(brief.isGenerated)

        // Judged by the system's own language recognizer rather than by the
        // wording, which the model is entitled to choose. Three English
        // headlines used to pull the answer into English whatever the
        // instructions said.
        #expect(Self.language(of: brief.title) == .french)
        #expect(Self.language(of: summary) == .french)
    }

    private static func language(of text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }

    @Test("A headline is filed under a subject that is about it")
    func filing() async throws {
        // The vocabulary a reader of the French press would have, including one
        // subject that has nothing to do with any of the headlines.
        let vocabulary = ["Éducation", "Logiciel", "Typographie", "Sport", "Cybersécurité"]
        let namer = TopicNamer(locale: Locale(identifier: "fr_FR"))

        let expected: [(headline: String, subject: String)] = [
            ("Une réforme du calendrier scolaire à l'étude", "Éducation"),
            ("Les macros Swift, deux ans après", "Logiciel"),
            ("Pourquoi les caractères grotesques reviennent", "Typographie"),
        ]

        for (headline, subject) in expected {
            guard case .chosen(let filed) = await namer.file(headline, summary: nil, into: vocabulary) else {
                Issue.record("The model would not file \(headline)")
                continue
            }
            print("=== \(headline) -> \(filed)")

            #expect(filed.contains(subject))
            // Two at most, and nothing that was never offered.
            #expect(filed.count <= TopicNamer.subjectsPerStory)
            #expect(filed.allSatisfy { vocabulary.contains($0) })
            // The page that prompted this filed wildfires under `Sport`.
            #expect(!filed.contains("Sport"))
        }
    }

    @Test("A headline is always filed under something it was shown")
    func alwaysSomething() async throws {
        let namer = TopicNamer(locale: Locale(identifier: "fr_FR"))

        // Nothing here is about macros. The list it is shown is the whole of
        // the vocabulary and there is no way out of it : offering an escape
        // cost more than it saved, the model taking it constantly, and a page
        // where half the stories are filed under nothing is a page whose pills
        // say nothing. There is no second pass to save this story any more
        // either, which is why the catalogue is fifty names deep : what a
        // reader actually follows should be in it.
        guard
            case .chosen(let filed) = await namer.file(
                "Les macros Swift, deux ans après",
                summary: "Ce que les macros ont changé au code que nous écrivons.",
                into: ["Jardinage", "Cuisine"]
            )
        else {
            Issue.record("The model would not file the headline")
            return
        }
        print("=== always something -> \(filed)")
        #expect(!filed.isEmpty)
        #expect(filed.allSatisfy { ["Jardinage", "Cuisine"].contains($0) })
    }

    @Test("The page the window builds comes out with briefs and pills")
    func theWholeRebuild() async throws {
        let database = try AppDatabase.inMemory()
        let now = Date()

        let feed = try await SubscriptionStore(database).subscribe(
            to: Subscription(address: "https://feeds.example.com/f.xml", title: "Le Quotidien")
        ).feed

        for (index, title) in headlines.enumerated() {
            let date = now.addingTimeInterval(-Double(index) * 3600)
            var entry = Entry(
                feedID: feed.id,
                guid: "urn:example:\(index)",
                title: title,
                excerpt: title,
                language: "fr",
                publishedAt: date,
                receivedAt: date
            )
            entry.hasMedia = false
            try await database.writer.write { db in
                try entry.insert(db)
                try EntryBody(entryID: entry.id, plainText: title).insert(db)
            }
        }

        let service = DigestService(database, locale: Locale(identifier: "fr_FR"))
        _ = await service.rebuild(now: now)

        let page = try await service.digest(now: now)
        let stories = try await database.writer.read { db in try Story.fetchAll(db) }

        // What a reader opening the window sees : stories, written briefs, and
        // pills to narrow them by.
        #expect(stories.count >= 2)
        #expect(stories.allSatisfy { $0.isGenerated })
        #expect(stories.allSatisfy { $0.briefLocale == "fr_FR" })

        // Not how many subjects, which is the model's to decide : that the
        // page comes out with any at all.
        #expect(!page.topics.isEmpty)
        #expect((page.live + page.stories).contains { !$0.topics.isEmpty })
    }
}
