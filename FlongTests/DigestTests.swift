//
//  DigestTests.swift
//  FlongTests
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import NaturalLanguage
import Testing

@testable import Flong

private var hasFrench: Bool { NLEmbedding.sentenceEmbedding(for: .french) != nil }

/// A newsroom's worth of articles about three events, and a few about nothing
/// in particular.
///
/// The point of the corpus is that a reader would group them the same way
/// without hesitating. If the builder does not, the builder is wrong.
private enum Corpus {
    struct Article {
        let feed: String
        let title: String
        let excerpt: String
        let hours: Double
    }

    static let calendar = [
        Article(
            feed: "Le Quotidien",
            title: "Une réforme du calendrier scolaire à l'étude",
            excerpt: "Le ministère envisage de décaler la rentrée de septembre à la mi-août dans trois académies.",
            hours: 5
        ),
        Article(
            feed: "L'Agence",
            title: "Calendrier scolaire : trois académies pilotes dès l'an prochain",
            excerpt: "La rentrée serait avancée à la mi-août pour les élèves de trois académies pilotes.",
            hours: 4
        ),
        Article(
            feed: "Le Soir",
            title: "Rentrée avancée : les syndicats enseignants demandent un report",
            excerpt: "Les syndicats jugent le calendrier de la réforme scolaire intenable pour les enseignants.",
            hours: 2
        ),
        Article(
            feed: "La Gazette",
            title: "Ce que changerait une rentrée scolaire à la mi-août",
            excerpt: "Décaler la rentrée bouleverserait les vacances d'été et l'organisation des académies.",
            hours: 1
        ),
    ]

    static let swift = [
        Article(
            feed: "Swift au quotidien",
            title: "Les macros Swift, deux ans après",
            excerpt: "Ce que les macros ont changé au code que nous écrivons, et ce qu'elles n'ont pas résolu.",
            hours: 30
        ),
        Article(
            feed: "Journal du code",
            title: "Bilan des macros Swift dans les projets réels",
            excerpt: "Deux ans de macros dans le code de production : ce que les équipes en retiennent.",
            hours: 28
        ),
    ]

    static let typography = [
        Article(
            feed: "L'Atelier typographique",
            title: "Pourquoi les caractères grotesques reviennent",
            excerpt: "Les sans empattement de la fin du dix-neuvième siècle reprennent leur place dans la presse.",
            hours: 50
        ),
        Article(
            feed: "Caractères",
            title: "Le retour des grotesques dans la presse imprimée",
            excerpt: "Les caractères sans empattement du dix-neuvième siècle reviennent dans les journaux.",
            hours: 48
        ),
    ]

    /// Three articles that belong to nothing.
    static let loose = [
        Article(
            feed: "Notes de terrain",
            title: "Carnet : trois jours en Cévennes",
            excerpt: "Des notes prises au fil du sentier, entre Florac et le mont Lozère.",
            hours: 10
        ),
        Article(
            feed: "Le Quotidien",
            title: "Le pont de la Roquette rouvre lundi",
            excerpt: "Après dix-huit mois de travaux, la circulation reprendra dans les deux sens.",
            hours: 20
        ),
        Article(
            feed: "La Gazette",
            title: "Une fondeuse de caractères raconte son métier",
            excerpt: "Elle dessine des empattements depuis vingt ans et n'a jamais vendu une police.",
            hours: 60
        ),
    ]

    static var all: [Article] { calendar + swift + typography + loose }
}

@Suite("Digest")
struct DigestTests {
    private let database: AppDatabase
    private let service: DigestService
    private let now = Date(timeIntervalSince1970: 1_787_646_600)
    private var feeds: [String: Feed] = [:]

    init() async throws {
        database = try AppDatabase.inMemory()
        service = DigestService(database)

        let subscriptions = SubscriptionStore(database)
        for name in Set(Corpus.all.map(\.feed)) {
            let address = "https://\(abs(name.hashValue)).example.com/f.xml"
            feeds[name] = try await subscriptions.subscribe(to: Subscription(address: address, title: name)).feed
        }

        for (index, article) in Corpus.all.enumerated() {
            let date = now.addingTimeInterval(-article.hours * 3600)
            var entry = Entry(
                feedID: feeds[article.feed]!.id,
                guid: "urn:example:\(index)",
                url: URL(string: "https://example.com/\(index)"),
                title: article.title,
                excerpt: article.excerpt,
                language: "fr",
                publishedAt: date,
                receivedAt: date
            )
            entry.hasMedia = false

            try await database.writer.write { db in
                try entry.insert(db)
                try EntryBody(entryID: entry.id, plainText: article.excerpt).insert(db)
            }
        }

    }

    // MARK: - Grouping

    @Test("Articles about one event become one story")
    func clustering() async throws {
        try await StoryBuilder(database).build(now: now)

        let digest = try await service.digest(now: now)
        let stories = digest.live + digest.stories

        #expect(stories.count == 3)
        #expect(stories.map(\.articleCount).sorted() == [2, 2, 4])
        #expect(digest.looseCount == Corpus.loose.count)
    }

    @Test("A story keeps its identity as it grows")
    func stability() async throws {
        try await StoryBuilder(database).build(now: now)
        let first = try await service.digest(now: now).live.first?.id

        // Another newsroom picks the story up an hour later.
        let feed = try #require(feeds["Le Soir"])
        var entry = Entry(
            feedID: feed.id,
            guid: "urn:example:late",
            title: "Calendrier scolaire : le ministère précise son calendrier",
            excerpt: "Les trois académies pilotes seront désignées avant la fin du mois.",
            language: "fr",
            publishedAt: now.addingTimeInterval(-600),
            receivedAt: now.addingTimeInterval(-600)
        )
        entry.hasMedia = false
        try await database.writer.write { db in try entry.insert(db) }

        try await StoryBuilder(database).build(now: now)

        let digest = try await service.digest(now: now)
        let story = try #require(digest.live.first)

        #expect(story.id == first)
        #expect(story.articleCount == 5)
    }

    @Test("A story shows the picture of its most recent illustrated article")
    func cover() async throws {
        try await StoryBuilder(database).build(now: now)

        // Two of the four articles carry a picture, and the latest of the four
        // is not one of them.
        let illustrated = [
            "Une réforme du calendrier scolaire à l'étude": "https://example.com/first.jpg",
            "Calendrier scolaire : trois académies pilotes dès l'an prochain": "https://example.com/latest.jpg",
        ]
        try await database.writer.write { db in
            for (title, address) in illustrated {
                var entry = try #require(try Entry.filter(Column("title") == title).fetchOne(db))
                entry.imageURL = URL(string: address)
                try entry.update(db)
            }
        }

        let digest = try await service.digest(now: now)
        let story = try #require((digest.live + digest.stories).first { $0.articleCount == 4 })

        // The most recent picture, not the first one the story ever had.
        #expect(story.imageURL?.absoluteString == "https://example.com/latest.jpg")
    }

    @Test("Building twice changes nothing")
    func idempotence() async throws {
        try await StoryBuilder(database).build(now: now)
        let first = try await service.digest(now: now)

        try await StoryBuilder(database).build(now: now)
        let second = try await service.digest(now: now)

        #expect(first == second)
    }

    // MARK: - What is happening

    @Test("Several rooms in a few hours is what makes a story live")
    func liveStories() async throws {
        try await StoryBuilder(database).build(now: now)
        let digest = try await service.digest(now: now)

        // The school calendar has four rooms within five hours. The others came
        // in more than six hours ago, so nothing is happening about them now.
        #expect(digest.live.count == 1)
        #expect(digest.live.first?.feedCount == 4)
        #expect(digest.live.first?.title.localizedCaseInsensitiveContains("calendrier") == true)
    }

    @Test("The front page looks back three days, not one")
    func window() async throws {
        try await StoryBuilder(database).build(now: now)

        let page = try await service.digest(now: now)

        // The Swift story is thirty hours old : a page that looked back a day
        // would have lost it overnight, which is not what a front page is.
        #expect(page.live.count + page.stories.count == 3)
        #expect(page.stories.contains { $0.title.localizedCaseInsensitiveContains("macros") })
    }

    // MARK: - The language of a brief

    @Test("A brief written in a language the reader no longer reads is written again")
    func briefLanguage() async throws {
        try await StoryBuilder(database).build(now: now)

        // Every story has a brief already, one of them written in French and
        // the rest in English, as they would be by a reader who has just
        // changed the language of their device.
        try await database.writer.write { db in
            for (index, story) in try Story.fetchAll(db).enumerated() {
                var story = story
                story.summary = "Ce qui est arrivé."
                story.isGenerated = true
                story.briefLocale = index == 0 ? "fr_FR" : "en_GB"
                try story.update(db)
            }
        }

        let work = BriefStoriesJob.work(locale: Locale(identifier: "fr_FR"), hasModel: true)
        let waiting = try await database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM story WHERE \(work.sql)",
                arguments: work.arguments
            ) ?? 0
        }

        // The French one is left alone, the English ones are asked for again.
        #expect(waiting == 2)
    }

    @Test("A headline the reader settled themselves is never written again")
    func lockedBriefs() async throws {
        try await StoryBuilder(database).build(now: now)

        try await database.writer.write { db in
            for story in try Story.fetchAll(db) {
                var story = story
                story.summary = "Written in English."
                story.isGenerated = true
                story.briefLocale = "en_GB"
                story.briefLocked = true
                try story.update(db)
            }
        }

        let work = BriefStoriesJob.work(locale: Locale(identifier: "fr_FR"), hasModel: true)
        let waiting = try await database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM story WHERE \(work.sql)",
                arguments: work.arguments
            ) ?? 0
        }

        #expect(waiting == 0)
    }

    @Test("Throwing away what the model wrote spares what the reader settled")
    func rewriting() async throws {
        try await StoryBuilder(database).build(now: now)

        try await database.writer.write { db in
            for (index, story) in try Story.fetchAll(db).enumerated() {
                var story = story
                story.summary = "Written by the model."
                story.isGenerated = true
                story.briefLocale = "en_GB"
                story.topic = "Software"
                story.briefLocked = index == 0
                try story.update(db)
            }
        }

        // The clearing on its own : what follows it is a rebuild, which on a
        // machine that has a model writes the page again straight away.
        await service.discardWhatTheModelWrote()

        let stories = try await database.writer.read { db in try Story.fetchAll(db) }
        let settled = try #require(stories.first { $0.briefLocked })
        let rest = stories.filter { !$0.briefLocked }

        // What the reader settled stays settled, subject included.
        #expect(settled.summary == "Written by the model.")
        #expect(settled.topic == "Software")

        #expect(rest.count == 2)
        #expect(rest.allSatisfy { $0.summary == nil })
        #expect(rest.allSatisfy { !$0.isGenerated })
        #expect(rest.allSatisfy { $0.briefLocale == nil })
        #expect(rest.allSatisfy { $0.topic == nil })
    }

    // MARK: - Subjects

    @Test("A page the model cannot read keeps the subjects it already had")
    func modelSilence() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["calendrier": "Éducation", "macros": "Logiciel", "grotesques": "Logiciel"])

        // What the naming job does when the model says nothing : on a machine
        // with no Apple Intelligence, that is every run.
        let silent = await TopicNamer().topics(of: [])
        #expect(silent == nil)

        await service.nameTopics(now: now)

        // Blanking a good page because the model was switched off for an
        // afternoon would be losing work to a transient.
        let page = try await service.digest(now: now)
        #expect(!page.topics.isEmpty)
    }

    @Test("The pills are the subjects on the page, most covered first")
    func topics() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["calendrier": "Éducation", "macros": "Logiciel", "grotesques": "Logiciel"])

        let page = try await service.digest(now: now)

        #expect(page.topics == ["Logiciel", "Éducation"])
    }

    @Test("A subject narrows the page to itself, and keeps the way back")
    func narrowing() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["calendrier": "Éducation", "macros": "Logiciel", "grotesques": "Logiciel"])

        let page = try await service.digest(.named("Éducation"), now: now)

        #expect(page.live.count + page.stories.count == 1)
        #expect(page.live.first?.topic == "Éducation")
        // The other subjects stay on the page, or there would be no way off it.
        #expect(page.topics == ["Logiciel", "Éducation"])
        // The tail belongs to no story, so it belongs to no subject either.
        #expect(page.looseCount == 0)
    }

    @Test("A story the model put under nothing is still on the front page")
    func unsorted() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["calendrier": "Éducation"])

        let front = try await service.digest(now: now)
        let education = try await service.digest(.named("Éducation"), now: now)

        #expect(front.live.count + front.stories.count == 3)
        #expect(education.live.count + education.stories.count == 1)
        #expect(front.looseCount == Corpus.loose.count)
    }

    /// Writes subjects onto the stories whose title holds each word, which is
    /// what the model does when there is one.
    private func put(_ topics: [String: String]) async throws {
        try await database.writer.write { db in
            for story in try Story.fetchAll(db) {
                for (word, topic) in topics where story.title.localizedCaseInsensitiveContains(word) {
                    var story = story
                    story.topic = topic
                    try story.update(db)
                }
            }
        }
    }

    @Test("A story names the rooms talking about it")
    func sources() async throws {
        try await StoryBuilder(database).build(now: now)
        let story = try #require(try await service.digest(now: now).live.first)

        #expect(story.feedCount == 4)
        #expect(story.feedTitles.count == DigestStore.namedFeeds)
        #expect(Set(story.feedTitles).isSubset(of: Set(Corpus.calendar.map(\.feed))))
    }

    @Test("The articles of a story are there, newest first")
    func articlesOfAStory() async throws {
        try await StoryBuilder(database).build(now: now)
        let story = try #require(try await service.digest(now: now).live.first)

        let articles = try await service.articles(of: story.id)
        #expect(articles.count == 4)
        #expect(articles.first?.date ?? .distantPast > articles.last?.date ?? .distantFuture)
    }

    @Test("What made no story is still reachable")
    func looseArticles() async throws {
        try await StoryBuilder(database).build(now: now)

        let loose = try await service.looseArticles(now: now)
        #expect(loose.count == Corpus.loose.count)
        #expect(loose.contains { $0.title.contains("Cévennes") })
    }
}

@Suite("Subjects")
struct TopicNamerTests {
    private let stories = (1...4).map { (id: UUID.v7(), title: "Story \($0)") }

    private func topics(_ generated: [(String, [Int])]) -> GeneratedTopics {
        GeneratedTopics(topics: generated.map { GeneratedTopic(name: $0.0, headlines: $0.1) })
    }

    @Test("Each story ends up under the subject that covers it")
    func assigning() {
        let assigned = TopicNamer.assign(topics([("Éducation", [1, 2]), ("Logiciel", [3, 4])]), to: stories)

        #expect(assigned[stories[0].id] == "Éducation")
        #expect(assigned[stories[1].id] == "Éducation")
        #expect(assigned[stories[3].id] == "Logiciel")
    }

    @Test("A subject covering one story is not a subject")
    func singletons() {
        let assigned = TopicNamer.assign(topics([("Éducation", [1, 2]), ("Typographie", [3])]), to: stories)

        // A pill covering one story says what the story underneath already says.
        #expect(assigned[stories[2].id] == nil)
        #expect(Set(assigned.values) == ["Éducation"])
    }

    @Test("A number that was never on the list is ignored")
    func invention() {
        let assigned = TopicNamer.assign(topics([("Éducation", [1, 2, 9, 0, -3])]), to: stories)

        #expect(assigned.count == 2)
        #expect(assigned[stories[0].id] == "Éducation")
    }

    @Test("A story claimed twice keeps the first subject that claimed it")
    func overlap() {
        let assigned = TopicNamer.assign(topics([("Éducation", [1, 2]), ("Logiciel", [2, 3, 4])]), to: stories)

        #expect(assigned[stories[1].id] == "Éducation")
        #expect(assigned[stories[2].id] == "Logiciel")
    }

    @Test("A subject with no name is no subject")
    func unnamed() {
        let assigned = TopicNamer.assign(topics([("   ", [1, 2]), ("Logiciel", [3, 4])]), to: stories)

        #expect(assigned[stories[0].id] == nil)
        #expect(assigned[stories[2].id] == "Logiciel")
    }
}

@Suite("Digest shapes")
struct DigestShapeTests {
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    @Test("A sparkline shows the shape of an arrival")
    func sparkline() {
        // Everything in the last third : a burst.
        let dates = (0..<12).map { now.addingTimeInterval(Double($0) * 60) } + [now.addingTimeInterval(3600 * 6)]
        let line = DigestStore.sparkline(dates, buckets: 6)

        #expect(line.count == 6)
        #expect(line.reduce(0, +) == dates.count)
        #expect(line[0] > line[3])
    }

    @Test("A sparkline of one moment is one bar")
    func flatSparkline() {
        #expect(DigestStore.sparkline([now]) == [1])
        #expect(DigestStore.sparkline([]) == [0])
    }

    @Test("Without a model, a story is named after its most central article")
    func fallbackBrief() {
        let brief = StorySummarizer.fallback(for: [
            (title: "Une réforme du calendrier scolaire", excerpt: "Le ministère envisage un décalage."),
            (title: "Autre chose", excerpt: nil),
        ])

        #expect(brief.title == "Une réforme du calendrier scolaire")
        #expect(brief.summary == "Le ministère envisage un décalage.")
        // And it says so : section 14 flags anything a model wrote, and this is
        // not that.
        #expect(!brief.isGenerated)
    }

    @Test("A story with no articles has nothing to be named after")
    func emptyBrief() {
        let brief = StorySummarizer.fallback(for: [])

        #expect(brief.title.isEmpty)
        #expect(brief.summary == nil)
    }

    // MARK: - The language of the brief

    @Test("The model is asked to write in the reader's language, not the articles'")
    func briefLanguage() {
        let instruction = OnDeviceModel.languageInstruction(for: Locale(identifier: "fr_FR")) { _ in true }

        #expect(instruction == "Answer in French, whatever language the articles are written in.")
    }

    @Test("The region a reader is in is not the language they read in")
    func regionIsNotLanguage() {
        let swiss = OnDeviceModel.languageInstruction(for: Locale(identifier: "de_CH")) { _ in true }
        let brazilian = OnDeviceModel.languageInstruction(for: Locale(identifier: "pt_BR")) { _ in true }

        #expect(swiss.contains("German"))
        #expect(brazilian.contains("Portuguese"))
    }

    @Test("A language the model does not speak leaves the articles in their own")
    func unsupportedLanguage() {
        let instruction = OnDeviceModel.languageInstruction(for: Locale(identifier: "br_FR")) { _ in false }

        // Half Breton and half English would be worse than either.
        #expect(instruction == "Answer in the language the articles are written in.")
    }

    @Test("The summarizer reads the device's language by default")
    func defaultLocale() {
        #expect(StorySummarizer().locale == Locale.current)
    }
}
