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
///
/// **It runs on the simulator, and it used to refuse to.** A simulator was held
/// to answer `available` and then fail every call, so the suite skipped itself
/// there ; since every test of this project runs on a simulator, it skipped
/// itself everywhere and nothing has been checked against a real model for as
/// long as that has been true. A simulator borrows the Mac's own Apple
/// Intelligence and answers exactly as a device does, which is measurable and
/// was measured : thirty real stories written on one. So the question is the
/// only one worth asking, which is whether there is a model here.
private var hasWorkingModel: Bool {
    LocalProvider().isAvailable
}

@Suite("The digest, against the real model", .enabled(if: hasWorkingModel), .serialized)
struct TopicNamerLiveTests {
    /// Whether the model is still there, asked after the call rather than
    /// before it.
    ///
    /// **A model can go away in the middle of a suite.** Hundreds of calls in a
    /// row and the system unloads the assets : `assetsUnavailable` three times
    /// over, and ``ModelPatience`` leaves it alone for a while, exactly as it
    /// does on a device. Every answer after that is the path without a model,
    /// which is the right behaviour and not something to assert against. What
    /// these tests are for is what a working model writes, so they say so and
    /// stop rather than reporting the machine's mood as a fault in the code.
    private func modelIsStillThere(_ what: String) async -> Bool {
        guard LocalProvider().isAvailable else {
            print("=== the model went away while checking \(what), so nothing was judged")
            return false
        }
        guard await Self.modelAnswers() else {
            print("=== the model here says it is there and answers nothing, so \(what) was not judged")
            return false
        }
        return true
    }

    /// Whether the model answers, which is not what `availability` says.
    ///
    /// **A machine can hold a model that says `available` and fails every
    /// call.** The models are a downloaded asset set, and an operating system
    /// upgrade can leave the catalogue empty behind an availability that never
    /// stopped saying `available` : every request then comes back
    /// `ModelManagerError`, three of them leave the model alone for a while,
    /// and a suite gated on availability alone runs to the end and reports the
    /// state of the machine as a fault in the code. That is the one thing the
    /// note above says this suite exists not to do.
    ///
    /// One question of a few tokens tells the two apart, and only `unusable`
    /// counts : a model that read the question and declined it, or that was
    /// busy, is a model that is here.
    private static func modelAnswers() async -> Bool {
        do {
            _ = try await LocalProvider()
                .conversation(saying: "Answer in one word.")
                .answer(to: "Name a colour.", shaped: .words, keeping: 16)
            return true
        } catch {
            guard case .unusable = error else { return true }
            return false
        }
    }

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
        guard await modelIsStillThere("a brief") else { return }

        let summary = try #require(brief.summary)
        #expect(brief.isGenerated)

        // Judged by the system's own language recognizer rather than by the
        // wording, which the model is entitled to choose. Three English
        // headlines used to pull the answer into English whatever the
        // instructions said.
        #expect(Self.language(of: brief.title) == .french)
        #expect(Self.language(of: summary) == .french)
    }

    /// Our own instructions, put to the model over articles with nothing in
    /// them to object to.
    ///
    /// **This is the test that tells the two failures apart.** One story
    /// refused is ordinary, is what the second voice exists for, and costs a
    /// headline. Every story refused, a village library included, is our own
    /// prompt being refused, and it costs the whole page : nothing is
    /// generated, so no story is eligible and no edition comes out. From the
    /// reader's side the two look the same, a paper wearing its publishers'
    /// own headlines, which is precisely the outcome section 14 was rewritten
    /// to stop happening silently.
    ///
    /// iOS 27 decides this refusal after the answer has been written, over a
    /// transcript that holds the instructions, so a word chosen to illustrate
    /// a rule is enough to stop the digest outright. One did, in both voices
    /// at once, which is why the second could not rescue the first.
    /// `docs/technical/digest.md` carries the measurement.
    @Test("Our own instructions are not what the model refuses")
    func ourOwnVoiceIsAnswerable() async throws {
        let harmless: [(title: String, excerpt: String?)] = [
            (
                "La bibliothèque municipale ouvrira le dimanche",
                "Le conseil a voté l'ouverture dominicale à partir de septembre."
            ),
            ("Horaires élargis pour la bibliothèque", "Les lecteurs pourront emprunter sept jours sur sept."),
            (
                "La médiathèque recrute deux bibliothécaires",
                "Deux postes sont ouverts pour tenir les nouveaux horaires."
            ),
        ]

        let brief = await StorySummarizer(locale: Locale(identifier: "fr_FR")).brief(forArticles: harmless)
        guard await modelIsStillThere("our own instructions") else { return }

        #expect(
            brief.isGenerated,
            """
            Both voices refused a story about library opening hours, so what is being refused is our \
            own prompt rather than the news. Look for a word in the instructions of StorySummarizer \
            before looking at the articles.
            """
        )
        #expect(brief.summary != nil)
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
            guard case .wrote(let filed) = await namer.file(headline, summary: nil, into: vocabulary) else {
                if await modelIsStillThere("a filing") { Issue.record("The model would not file \(headline)") }
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
        // either, which is why the catalogue is fifty-two names deep : what a
        // reader actually follows should be in it.
        guard
            case .wrote(let filed) = await namer.file(
                "Les macros Swift, deux ans après",
                summary: "Ce que les macros ont changé au code que nous écrivons.",
                into: ["Jardinage", "Cuisine"]
            )
        else {
            if await modelIsStillThere("a filing with nothing that fits") {
                Issue.record("The model would not file the headline")
            }
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
            try await database.writer.write { [entry] db in
                try entry.insert(db)
                try EntryBody(entryID: entry.id, plainText: title).insert(db)
            }
        }

        // The sections every reader has, which the window writes down at
        // launch and a service built by hand does not : a story cannot be filed
        // under a vocabulary nobody has written yet.
        try await TopicPreferences(database).seedStandards(at: now)

        // One edition a day, coming out just before the oldest of these, so
        // that the seven are one period's news. A story belongs to one
        // edition, and a fixture spread over six hours of the standard four
        // would be cut wherever the hour of the run happens to fall.
        let opened = Calendar.current.dateComponents(
            [.hour, .minute], from: now.addingTimeInterval(-Double(headlines.count) * 3600))
        let schedule = EditionSchedule(hours: [.morning: opened.hour! * 60 + opened.minute!])

        let service = DigestService(database, locale: Locale(identifier: "fr_FR"))
        _ = await service.rebuild(now: now, schedule: schedule)

        let page = try await service.digest(now: now)
        let stories = try await database.writer.read { db in try Story.fetchAll(db) }
        guard await modelIsStillThere("a whole page") else { return }

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
