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

    @Test("Subjects for English headlines are named in the reader's language")
    func subjectsOfEnglishHeadlines() async throws {
        let stories = english.map { (id: UUID.v7(), title: $0) }

        let assigned = try #require(await TopicNamer(locale: Locale(identifier: "fr_FR")).topics(of: stories))
        let names = Set(assigned.values.flatMap { $0 }).joined(separator: ". ")

        #expect(!names.isEmpty)
        #expect(Self.language(of: names) == .french)
    }

    private static func language(of text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }

    @Test("Every headline the model is shown comes back under a subject")
    func everyHeadlineIsSorted() async throws {
        let stories = headlines.map { (id: UUID.v7(), title: $0) }

        let assigned = try #require(await TopicNamer(locale: Locale(identifier: "fr_FR")).topics(of: stories))

        // The model chooses how many subjects it finds and which headlines fall
        // under them, and it is entitled to. What is asserted is that the page
        // is not left with nothing : a subject covering a single story used to
        // be dropped, which on a page of three stories dropped all three.
        #expect(!assigned.isEmpty)
        #expect(assigned.count * 2 >= stories.count)
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
