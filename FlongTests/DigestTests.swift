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
import FoundationModels
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
    }

    /// A story moves between the two lists as it gains articles, keeping its
    /// identifier. Derived in the view, the lead was a second answer that could
    /// fall out of step with the page and stay wrong until the next launch.
    @Test("The page names its own lead, and names exactly one")
    func thePageNamesItsLead() async throws {
        try await StoryBuilder(database).build(now: now)
        let page = try await service.digest(now: now)

        let lead = try #require(page.leadID)
        #expect(lead == (page.live.first?.id ?? page.stories.first?.id))
        #expect(page.all.filter { $0.id == lead }.count == 1)
    }

    @Test("An empty page leads on nothing")
    func anEmptyPageLeadsOnNothing() async throws {
        let empty = try await DigestService(try AppDatabase.inMemory()).digest(now: now)

        #expect(empty.isEmpty)
        #expect(empty.leadID == nil)
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

        // And it is credited to the room whose article that picture came with,
        // which is not the first room to have covered the story : the picture
        // and its credit have to be the same article or the credit is a lie.
        #expect(story.imageCredit == feeds["L'Agence"]?.domain)
        #expect(story.imageCredit != story.feedMarks.first?.room)
    }

    @Test("A story with no picture credits nothing")
    func noCoverNoCredit() async throws {
        try await StoryBuilder(database).build(now: now)

        let digest = try await service.digest(now: now)
        let story = try #require((digest.live + digest.stories).first { $0.articleCount == 4 })

        #expect(story.imageURL == nil)
        #expect(story.imageCredit == nil)
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
            // What the brief was written from, as `BriefStoriesJob.save` writes
            // it : without it every story reads as one whose articles have
            // changed, which is exactly what the predicate is now for.
            try db.execute(sql: "UPDATE story SET brief_members = \(BriefStoriesJob.membersKey)")
        }

        let work = BriefStoriesJob.work(locale: Locale(identifier: "fr_FR"), hasModel: true, since: .distantPast)
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

    @Test("A story the model would not write about is not asked about again")
    func refusedOnce() async throws {
        try await StoryBuilder(database).build(now: now)

        // What the job stores when the model refuses this one story : the
        // article's own title, and the language it was asked in.
        try await database.writer.write { db in
            for story in try Story.fetchAll(db) {
                var story = story
                story.summary = "Le chapeau de son propre article."
                story.isGenerated = false
                story.briefLocale = "fr_FR"
                try story.update(db)
            }
            // What the brief was written from, as `BriefStoriesJob.save` writes
            // it : without it every story reads as one whose articles have
            // changed, which is exactly what the predicate is now for.
            try db.execute(sql: "UPDATE story SET brief_members = \(BriefStoriesJob.membersKey)")
        }

        let work = BriefStoriesJob.work(locale: Locale(identifier: "fr_FR"), hasModel: true, since: .distantPast)
        let waiting = try await database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM story WHERE \(work.sql)",
                arguments: work.arguments
            ) ?? 0
        }

        // Asking again in the same language would get the same refusal, and
        // the count would never reach zero.
        #expect(waiting == 0)
    }

    @Test("A story no model has ever been asked about is asked as soon as one appears")
    func neverAsked() async throws {
        try await StoryBuilder(database).build(now: now)

        try await database.writer.write { db in
            for story in try Story.fetchAll(db) {
                var story = story
                story.summary = "Le chapeau de son propre article."
                story.isGenerated = false
                story.briefLocale = nil
                try story.update(db)
            }
            // What the brief was written from, as `BriefStoriesJob.save` writes
            // it : without it every story reads as one whose articles have
            // changed, which is exactly what the predicate is now for.
            try db.execute(sql: "UPDATE story SET brief_members = \(BriefStoriesJob.membersKey)")
        }

        let withModel = BriefStoriesJob.work(locale: Locale(identifier: "fr_FR"), hasModel: true, since: .distantPast)
        let without = BriefStoriesJob.work(locale: Locale(identifier: "fr_FR"), hasModel: false, since: .distantPast)

        let counts = try await database.writer.read { db in
            (
                asked: try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM story WHERE \(withModel.sql)", arguments: withModel.arguments
                ) ?? 0,
                quiet: try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM story WHERE \(without.sql)", arguments: without.arguments
                ) ?? 0
            )
        }

        #expect(counts.asked == 3)
        // And without a model it asks for nothing, so the count reaches zero.
        #expect(counts.quiet == 0)
    }

    @Test("A brief in the wrong language is refused before it is stored")
    func wrongLanguage() {
        let french = Locale(identifier: "fr_FR")

        let right = StorySummarizer.isWritten(
            in: french,
            title: "Réforme du calendrier scolaire",
            summary: "Le ministère envisage de décaler la rentrée dans trois académies pilotes."
        )
        let wrong = StorySummarizer.isWritten(
            in: french,
            title: "Microsoft Security Updates",
            summary: "Microsoft released security updates to address vulnerabilities in its SharePoint Server."
        )
        // A headline too short to judge is taken at its word : half the words
        // in one are proper nouns that belong to no language at all.
        let short = StorySummarizer.isWritten(in: french, title: "Ivanti Sentry", summary: "")

        #expect(right)
        #expect(!wrong)
        #expect(short)
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
            // What the brief was written from, as `BriefStoriesJob.save` writes
            // it : without it every story reads as one whose articles have
            // changed, which is exactly what the predicate is now for.
            try db.execute(sql: "UPDATE story SET brief_members = \(BriefStoriesJob.membersKey)")
        }

        let work = BriefStoriesJob.work(locale: Locale(identifier: "fr_FR"), hasModel: true, since: .distantPast)
        let waiting = try await database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM story WHERE \(work.sql)",
                arguments: work.arguments
            ) ?? 0
        }

        #expect(waiting == 0)
    }

    /// The excerpt is the top of the article body flattened and cut at three
    /// hundred characters on the nearest space. A release note went out as a
    /// standfirst, ticket numbers and `Tags:` footer included.
    @Test("An article's body is not a standfirst, and a publisher's line is")
    func whatCountsAsAStandfirst() {
        // What the reader was shown.
        #expect(
            StorySummarizer.standfirst(
                from: "Release: llm-gemini 0.34 New model gemini-3.8-flash for Gemini 3.8 Flash, with low, "
                    + "medium and high thinking levels. #146 Fixed async responses failing to record the "
                    + "resolved model version. Thanks, Charlie Tonneslan. #137 Tags: llm, gemini",
                under: "llm-gemini 0.34"
            ) == nil
        )

        // A line a publisher wrote, which is what the page is for.
        #expect(
            StorySummarizer.standfirst(
                from: "Les trois académies pilotes seront désignées avant la fin du mois.",
                under: "Une réforme du calendrier scolaire"
            ) == "Les trois académies pilotes seront désignées avant la fin du mois."
        )

        // The footer goes and the sentence above it stays.
        #expect(
            StorySummarizer.standfirst(
                from: "Le ministère précise son calendrier. Tags: éducation, réforme",
                under: "Une réforme"
            ) == "Le ministère précise son calendrier."
        )

        // A line that only says the headline again says nothing.
        #expect(StorySummarizer.standfirst(from: "Une réforme du calendrier", under: "Une réforme") == nil)
    }

    @Test("Throwing away what the model wrote spares what the reader settled")
    func rewriting() async throws {
        try await StoryBuilder(database).build(now: now)

        try await TopicPreferences(database).add("Software")
        try await database.writer.write { db in
            for (index, story) in try Story.fetchAll(db).enumerated() {
                var story = story
                story.summary = "Written by the model."
                story.isGenerated = true
                story.briefLocale = "en_GB"
                story.briefLocked = index == 0
                try story.update(db)
                try StoryTopic(storyID: story.id, name: "Software").insert(db)
            }
        }

        // The clearing on its own : what follows it is a rebuild, which on a
        // machine that has a model writes the page again straight away.
        await service.discardWhatTheModelWrote()

        let stories = try await database.writer.read { db in try Story.fetchAll(db) }
        let settled = try #require(stories.first { $0.briefLocked })
        let rest = stories.filter { !$0.briefLocked }

        let remaining = try await database.writer.read { db in try StoryTopic.fetchAll(db) }

        // What the reader settled stays settled, subjects included.
        #expect(settled.summary == "Written by the model.")
        #expect(remaining.map(\.storyID) == [settled.id])

        #expect(rest.count == 2)
        #expect(rest.allSatisfy { $0.summary == nil })
        #expect(rest.allSatisfy { !$0.isGenerated })
        #expect(rest.allSatisfy { $0.briefLocale == nil })
    }

    // MARK: - The order of the page

    /// A story of several articles, each from its own room, ending some hours
    /// ago.
    ///
    /// Written straight into the store rather than grouped out of the corpus :
    /// what this pins is the order the page is read in, and the corpus has no
    /// heavy old story to set against a light new one.
    private func story(_ title: String, articles count: Int, endingHoursAgo hours: Double) async throws {
        let last = now.addingTimeInterval(-hours * 3600)
        let story = Story(id: .v7(at: last), title: title, firstAt: last, lastAt: last, updatedAt: last)

        try await database.writer.write { db in
            try story.insert(db)

            for index in 0..<count {
                let host = "order-\(abs(title.hashValue))-\(index).example.com"
                var feed = Feed(url: URL(string: "https://\(host)/f.xml")!, title: host)
                feed.siteURL = URL(string: "https://\(host)")
                try feed.insert(db)

                // Spread backwards, so nothing is recent enough to be live.
                let date = last.addingTimeInterval(-Double(index) * 3600)
                var entry = Entry(
                    feedID: feed.id,
                    guid: "urn:\(host):\(index)",
                    title: title,
                    publishedAt: date,
                    receivedAt: date
                )
                entry.hasMedia = false
                try entry.insert(db)
                try StoryMember(storyID: story.id, entryID: entry.id, similarity: 1).insert(db)
            }
        }
    }

    @Test("The page leads with what happened last, not with what has most articles")
    func recencyBeforeWeight() async throws {
        // A story that has run all week keeps gathering articles and outweighs
        // anything that opened this morning, and outweighs it more every day.
        // Ordered by weight, the top of the page was the same top of the page
        // every morning however much had arrived overnight, which is a front
        // page saying nothing has happened.
        try await story("Le long feuilleton", articles: 6, endingHoursAgo: 40)
        try await story("Ce matin", articles: 2, endingHoursAgo: 2)

        let page = try await service.digest(now: now)

        #expect(page.stories.map(\.title) == ["Ce matin", "Le long feuilleton"])
    }

    @Test("What the reader asked for still comes before when it happened")
    func preferenceBeforeRecency() async throws {
        try await story("Le long feuilleton", articles: 6, endingHoursAgo: 40)
        try await story("Ce matin", articles: 2, endingHoursAgo: 2)

        try await database.writer.write { db in
            let story = try Story.filter(Column("title") == "Le long feuilleton").fetchOne(db)
            try StoryTopic(storyID: try #require(story).id, name: "Éducation").insert(db)
        }
        try await TopicPreferences(database).adjust("Éducation", by: 1)

        let page = try await service.digest(now: now)

        // A reader who says more of this expects more of this, whenever it
        // happened : the score is still the first thing asked.
        #expect(page.stories.map(\.title) == ["Le long feuilleton", "Ce matin"])
    }

    // MARK: - What the reader wants more or less of

    @Test("A subject the reader asked more of comes first, whatever its weight")
    func preference() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["calendrier": "Éducation", "macros": "Logiciel", "grotesques": "Typographie"])

        let before = try await service.digest(now: now)
        // The heaviest story leads, as it did before anyone said anything.
        #expect(before.stories.first?.topics == ["Logiciel"])

        try await TopicPreferences(database).adjust("Typographie", by: 1)
        let after = try await service.digest(now: now)

        #expect(after.stories.first?.topics == ["Typographie"])
        // And the pills lead with it too.
        #expect(after.topics.first == "Typographie")
        #expect(after.scores == ["Typographie": 1])
    }

    @Test("A subject the reader asked less of goes last")
    func dislike() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["macros": "Logiciel", "grotesques": "Typographie"])

        try await TopicPreferences(database).adjust("Logiciel", by: -1)
        let page = try await service.digest(now: now)

        #expect(page.stories.last?.topics == ["Logiciel"])
        #expect(page.topics.last == "Logiciel")
    }

    @Test("Wanting more of one of a story's subjects is wanting more of the story")
    func severalSubjects() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["macros": "Logiciel", "grotesques": "Typographie"])

        // The typography story is also about software, and the reader wants
        // less of software and more of typography.
        try await TopicPreferences(database).add("Logiciel")
        try await database.writer.write { db in
            for story in try Story.fetchAll(db) where story.title.localizedCaseInsensitiveContains("grotesques") {
                try StoryTopic(storyID: story.id, name: "Logiciel").insert(db, onConflict: .ignore)
            }
        }
        let preferences = TopicPreferences(database)
        try await preferences.adjust("Logiciel", by: -2)
        try await preferences.adjust("Typographie", by: 1)

        let page = try await service.digest(now: now)
        let typography = try #require(page.stories.first { $0.topics.contains("Typographie") })

        // Asking for more of anything wins.
        #expect(typography.score(page.scores) == 1)
        #expect(page.stories.first?.id == typography.id)
    }

    @Test("A reader can only push a subject so far")
    func clamped() async throws {
        let preferences = TopicPreferences(database)

        for _ in 0..<6 { try await preferences.adjust("Logiciel", by: 1) }
        #expect(try await preferences.score(of: "Logiciel") == TopicPreferences.limit)

        for _ in 0..<12 { try await preferences.adjust("Logiciel", by: -1) }
        #expect(try await preferences.score(of: "Logiciel") == -TopicPreferences.limit)
    }

    @Test("Saying nothing about a subject leaves no trace of it")
    func neutral() async throws {
        let preferences = TopicPreferences(database)

        try await preferences.adjust("Logiciel", by: 1)
        try await preferences.adjust("Logiciel", by: -1)
        #expect(try await preferences.scores().isEmpty)

        try await preferences.adjust("Logiciel", by: 2)
        try await preferences.clear("Logiciel")
        #expect(try await preferences.scores().isEmpty)
    }

    @Test("A subject the reader wrote is on the page before anything is filed under it")
    func ownSubjectsAreOnThePage() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["calendrier": "Éducation"])

        let preferences = TopicPreferences(database)
        try await preferences.add("Cyclisme")
        // A section of the catalogue, holding nothing today.
        try await preferences.seedStandards(["Sport"], at: now)

        let page = try await service.digest(now: now)

        // A reader who has just written a subject and cannot see it has no way
        // of knowing it took.
        #expect(page.topics.contains("Cyclisme"))
        // A section nobody asked for is on the page only while it holds
        // something : fifty empty pills would say nothing at all.
        #expect(!page.topics.contains("Sport"))
        #expect(page.topics.first == "Éducation")
    }

    @Test("Narrowing to a subject that holds nothing gives an empty page, not a broken one")
    func emptySubject() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["calendrier": "Éducation"])
        try await TopicPreferences(database).add("Cyclisme")

        let page = try await service.digest(.named("Cyclisme"), now: now)

        #expect(page.isEmpty)
        // And the way back is still on the page.
        #expect(page.topics.contains("Éducation"))
    }

    @Test("The stories left to file are counted, and none of them is one already filed")
    func backlog() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["calendrier": "Éducation"])

        let job = FileStoriesJob(database, now: now)
        let left = try await job.remaining()

        let stories = try await database.writer.read { db in try Story.fetchCount(db) }
        let filed = try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT story_id) FROM story_topic") ?? 0
        }

        // Everything but what is already filed, whether this machine has a
        // model or not. It answered nought without one, so a backlog waiting
        // for Apple Intelligence to finish downloading looked exactly like no
        // backlog at all and the interface had nothing it could say about the
        // wait. Whether anything can be done about the queue is `step()`'s
        // business, not the count's.
        #expect(left == stories - filed)
    }

    @Test("A story is not stamped as asked when there was nothing to ask about")
    func nothingIsStampedWithoutAVocabulary() async throws {
        try await StoryBuilder(database).build(now: now)
        // A store whose sections have not been seeded yet, so `settled()` is
        // empty and the model would be shown nothing to choose from.
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM topic")
        }

        let before = try await FileStoriesJob(database, now: now).remaining()
        #expect(before > 0)

        _ = try await FileStoriesJob(database, now: now).step()

        // Still waiting, and not stamped : the queue survives a vocabulary that
        // has not been seeded yet, and empties once it has.
        #expect(try await FileStoriesJob(database, now: now).remaining() == before)
    }

    @Test("Enriching names each half as it takes its turn")
    func enrichmentNamesItsPhases() async throws {
        try await StoryBuilder(database).build(now: now)
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE story SET summary = NULL, brief_locale = NULL, topics_asked_at = NULL")
        }

        let phases = Locked<[WorkPhase]>([])
        await service.enrich(now: now) { phase in phases.append(phase) }

        // The reader watching a repair wants to see the writing and the filing
        // happen, and both have to say so. They said nothing at all until the
        // turns were named : the page went from grouping straight to tidying.
        let seen = phases.value
        #expect(seen.contains(.writing))
        #expect(seen.contains(.filing))

        // And in that order, a written headline being a better thing to file
        // than the title of whichever article was nearest the middle.
        #expect(seen.first == .writing)
    }

    @Test("Throwing away what the model wrote puts every story back in both queues")
    func discardingRefillsTheQueues() async throws {
        try await StoryBuilder(database).build(now: now)

        // A page as it stands after a night's work : every story written and
        // filed, so both jobs have nothing left to do.
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE story SET summary = 'Un résumé.', is_generated = 1, brief_locale = ?,
                                     topics_asked_at = ?, brief_members = \(BriefStoriesJob.membersKey)
                    """,
                arguments: [Locale.current.identifier, now]
            )
            try Topic(name: "Éducation", kind: .standard, createdAt: now).insert(db)
            for id in try UUID.fetchAll(db, sql: "SELECT id FROM story") {
                try StoryTopic(storyID: id, name: "Éducation").insert(db)
            }
        }

        #expect(try await BriefStoriesJob(database, now: now).remaining() == 0)
        #expect(try await FileStoriesJob(database, now: now).remaining() == 0)

        // This is what the repair rests on. Forgetting the change tokens
        // repairs what came from iCloud and nothing else, so a repair that did
        // not also do this found both jobs empty, returned in milliseconds, and
        // showed the reader none of the steps they had asked to watch.
        await service.discardWhatTheModelWrote()

        let stories = try await database.writer.read { db in try Story.fetchCount(db) }
        #expect(try await BriefStoriesJob(database, now: now).remaining() == stories)
        #expect(try await FileStoriesJob(database, now: now).remaining() == stories)
    }

    /// A story keeps one identity while its articles come and go, and the
    /// brief used to be keyed to nothing but the story and the language : one
    /// briefed on a protest kept that headline over the photography that joined
    /// the group a week later.
    @Test("A story whose articles changed is written about again")
    func aBriefFollowsItsArticles() async throws {
        try await StoryBuilder(database).build(now: now)

        // A page as it stands after a night's work.
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE story SET summary = 'Ce qui est arrivé.', is_generated = 1, brief_locale = ?,
                                     brief_members = \(BriefStoriesJob.membersKey)
                    """,
                arguments: [Locale(identifier: "fr_FR").identifier]
            )
        }

        let settled = BriefStoriesJob.work(
            locale: Locale(identifier: "fr_FR"), hasModel: true, since: .distantPast)
        #expect(try await waiting(under: settled) == 0)

        // Another newsroom picks one of them up.
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

        // The one whose articles moved, and only that one.
        #expect(try await waiting(under: settled) == 1)
    }

    /// The filing had no such rule at all : a story the model declined stood
    /// under no rubric for life, and one filed before its headline was written
    /// kept the rubric chosen from a raw article title.
    @Test("A story whose headline changed is filed again")
    func aFilingFollowsItsHeadline() async throws {
        try await StoryBuilder(database).build(now: now)

        try await database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE story
                    SET topics_asked_at = ?,
                        topics_asked_for = title || char(10) || COALESCE(substr(summary, 1, 240), '')
                    """,
                arguments: [now]
            )
        }
        #expect(try await FileStoriesJob(database, now: now).remaining() == 0)

        // The model writes a headline, which is the whole of what the filing
        // was asked about.
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE story SET title = 'Une réforme du calendrier scolaire'")
        }

        let left = try await FileStoriesJob(database, now: now).remaining()
        #expect(left > 0)
    }

    private func waiting(under work: (sql: String, arguments: StatementArguments)) async throws -> Int {
        try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM story WHERE \(work.sql)", arguments: work.arguments) ?? 0
        }
    }

    @Test("A story the model cannot file does not block the ones behind it")
    func theQueueMoves() async throws {
        try await StoryBuilder(database).build(now: now)

        let job = FileStoriesJob(database, now: now)
        let before = try await job.remaining()

        // The stories at the head of the queue, asked about and left unfiled,
        // which is what happens when the model has nothing for them.
        try await database.writer.write { db in
            for story in try Story.fetchAll(db) {
                var story = story
                story.topicsAskedAt = self.now
                try story.update(db)
            }
            // What the brief was written from, and what the filing was asked
            // about, as the two jobs write them : without either, every story
            // reads as one whose question has changed, which is exactly what
            // the two predicates are now for.
            try db.execute(sql: "UPDATE story SET brief_members = \(BriefStoriesJob.membersKey)")
            try db.execute(
                sql: """
                    UPDATE story
                    SET topics_asked_for = title || char(10) || COALESCE(substr(summary, 1, 240), '')
                    """
            )
        }

        // The queue is empty because everything has been asked, not because
        // everything was answered. It used to stall on the first one it could
        // not file and never reach the rest.
        #expect(try await job.remaining() == 0)
        #expect(before >= 0)
    }

    @Test("Writing the page again asks about every story once more")
    func rewritingAsksAgain() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["calendrier": "Éducation"])
        try await database.writer.write { db in
            for story in try Story.fetchAll(db) {
                var story = story
                story.topicsAskedAt = self.now
                try story.update(db)
            }
            // What the brief was written from, as `BriefStoriesJob.save` writes
            // it : without it every story reads as one whose articles have
            // changed, which is exactly what the predicate is now for.
            try db.execute(sql: "UPDATE story SET brief_members = \(BriefStoriesJob.membersKey)")
        }

        await service.discardWhatTheModelWrote()

        let stamped = try await database.writer.read { db in
            try Story.fetchAll(db).filter { $0.topicsAskedAt != nil }.count
        }
        #expect(stamped == 0)
    }

    // MARK: - A vocabulary that stays put

    @Test("A story keeps the subjects it was given")
    func subjectsStayPut() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["calendrier": "Éducation"])

        // What the naming job does on a machine with no model : nothing to
        // the ones already filed, whatever else happens.
        await service.nameTopics(now: now)

        let page = try await service.digest(now: now)
        let calendar = try #require((page.live + page.stories).first { $0.title.contains("calendrier") })
        #expect(calendar.topics == ["Éducation"])
    }

    @Test("A subject the reader writes is theirs, and is folded against what exists")
    func ownSubjects() async throws {
        let preferences = TopicPreferences(database)

        #expect(try await preferences.add("Cybersécurité") == "Cybersécurité")
        // The same word said another way is the same subject.
        #expect(try await preferences.add("cybersecurite") == "Cybersécurité")
        #expect(try await preferences.add("   ") == nil)

        let known = try await preferences.known()
        #expect(known.map(\.name) == ["Cybersécurité"])
        #expect(known.first?.isOwn == true)
        #expect(known.first?.stories == 0)
    }

    @Test("The vocabulary shown to the model leads with what is used most")
    func vocabularyOrder() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["calendrier": "Éducation", "macros": "Logiciel", "grotesques": "Logiciel"])

        let preferences = TopicPreferences(database)
        try await preferences.add("Cyclisme")

        let vocabulary = try await preferences.vocabulary()
        #expect(vocabulary.first == "Logiciel")
        #expect(Set(vocabulary) == ["Logiciel", "Éducation", "Cyclisme"])
    }

    @Test("Removing a subject the reader wrote takes its filings with it")
    func removingOwnSubject() async throws {
        try await StoryBuilder(database).build(now: now)
        let preferences = TopicPreferences(database)
        try await preferences.add("Cyclisme")
        try await put(["calendrier": "Cyclisme"])
        try await preferences.adjust("Cyclisme", by: 2)

        try await preferences.remove("Cyclisme")

        #expect(try await preferences.known().isEmpty)
        #expect(try await preferences.scores().isEmpty)
        let filed = try await database.writer.read { db in try StoryTopic.fetchCount(db) }
        #expect(filed == 0)
    }

    // MARK: - Managing the subjects

    @Test("Every subject is listed, with what covers it and what was said")
    func knownTopics() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["calendrier": "Éducation", "macros": "Logiciel", "grotesques": "Logiciel"])

        let preferences = TopicPreferences(database)
        try await preferences.adjust("Logiciel", by: -2)
        // A subject the model has stopped using, which the reader must still
        // be able to find to take back what they said about it.
        try await preferences.adjust("Cyclisme", by: 1)

        let known = try await preferences.known()

        #expect(known.map(\.name).sorted() == ["Cyclisme", "Logiciel", "Éducation"])
        let software = try #require(known.first { $0.name == "Logiciel" })
        let cycling = try #require(known.first { $0.name == "Cyclisme" })

        #expect(software.stories == 2)
        // A score below nought is a score, not an absence.
        #expect(software.score == -2)
        #expect(cycling.stories == 0)
        #expect(cycling.score == 1)

        // The alphabet, and in the reader's own : `Éducation` files under E
        // rather than after Z, and a subject nudged up does not move out from
        // under the finger that nudged it.
        #expect(known.map(\.name) == ["Cyclisme", "Éducation", "Logiciel"])
    }

    @Test("Everything said can be taken back at once")
    func forgetting() async throws {
        let preferences = TopicPreferences(database)
        try await preferences.adjust("Logiciel", by: -2)
        try await preferences.adjust("Éducation", by: 3)

        try await preferences.clearAll()

        #expect(try await preferences.scores().isEmpty)

        // The subjects stay : forgetting what was said about a subject is not
        // forgetting the subject, and the model still files under them.
        let known = try await preferences.known()
        #expect(known.map(\.name).sorted() == ["Logiciel", "Éducation"])
        #expect(known.allSatisfy { $0.score == 0 })
    }

    // MARK: - Subjects

    @Test("Filing the page again never disturbs what is already filed")
    func alreadyFiled() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["calendrier": "Éducation", "macros": "Logiciel", "grotesques": "Logiciel"])

        let before = try await database.writer.read { db in
            try StoryTopic.fetchAll(db).map { "\($0.storyID)|\($0.name)" }.sorted()
        }

        // Whatever the model says, or fails to say : the job is only ever
        // shown the stories nobody has filed.
        await service.nameTopics(now: now)

        let after = try await database.writer.read { db in
            try StoryTopic.fetchAll(db).map { "\($0.storyID)|\($0.name)" }.sorted()
        }

        #expect(after == before)
        #expect(!(try await service.digest(now: now)).topics.isEmpty)
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
        #expect(page.live.first?.topics == ["Éducation"])
        // The other subjects stay on the page, or there would be no way off it.
        #expect(page.topics == ["Logiciel", "Éducation"])
    }

    @Test("A story the model put under nothing is still on the front page")
    func unsorted() async throws {
        try await StoryBuilder(database).build(now: now)
        try await put(["calendrier": "Éducation"])

        let front = try await service.digest(now: now)
        let education = try await service.digest(.named("Éducation"), now: now)

        #expect(front.live.count + front.stories.count == 3)
        #expect(education.live.count + education.stories.count == 1)
    }

    /// Writes subjects onto the stories whose title holds each word, which is
    /// what the model does when there is one. A story may take several.
    private func put(_ topics: [String: String]) async throws {
        // Through the vocabulary, as the naming job does : a subject is a
        // thing before it is a filing.
        for topic in Set(topics.values) {
            try await TopicPreferences(database).add(topic)
        }

        try await database.writer.write { db in
            for story in try Story.fetchAll(db) {
                for (word, topic) in topics where story.title.localizedCaseInsensitiveContains(word) {
                    try StoryTopic(storyID: story.id, name: topic).insert(db, onConflict: .ignore)
                }
            }
        }
    }

    @Test("A story names the rooms talking about it")
    func sources() async throws {
        try await StoryBuilder(database).build(now: now)
        let story = try #require(try await service.digest(now: now).live.first)

        #expect(story.feedCount == 4)
        #expect(story.feedMarks.count == DigestStore.namedFeeds)

        // A mark is a room and not a feed, so what the page shows is the host
        // each article came from : the name and the picture beside it belong
        // to the publisher and are looked up, never carried on the story.
        let rooms = Set(Corpus.calendar.compactMap { feeds[$0.feed]?.domain })
        #expect(Set(story.feedMarks.map(\.room)) == rooms)
        // In the order the rooms picked it up.
        #expect(story.feedMarks.first?.room == feeds["Le Quotidien"]?.domain)
    }

    @Test("A paper running a story in two of its sections is one room")
    func roomsAreNewsrooms() async throws {
        // The same paper, two desks, the same story : one room covering it,
        // one mark on the page.
        let subscriptions = SubscriptionStore(database)
        var feeds: [Feed] = []
        for desk in ["societe", "politique"] {
            feeds.append(
                try await subscriptions.subscribe(
                    to: Subscription(
                        address: "https://lequotidien.example.com/\(desk)/rss.xml", title: "Le Quotidien - \(desk)")
                ).feed
            )
        }

        for (index, feed) in feeds.enumerated() {
            var entry = Entry(
                feedID: feed.id,
                guid: "urn:example:phones:\(index)",
                title: "L'interdiction des téléphones portables dans les lycées",
                excerpt: "Le gouvernement annonce que l'interdiction sera effective dès la rentrée scolaire.",
                language: "fr",
                publishedAt: now.addingTimeInterval(-600),
                receivedAt: now.addingTimeInterval(-600)
            )
            entry.hasMedia = false
            try await database.writer.write { db in
                try entry.insert(db)
                try EntryBody(entryID: entry.id, plainText: entry.excerpt ?? "").insert(db)
            }
        }

        try await StoryBuilder(database).build(now: now)
        let page = try await service.digest(now: now)
        let story = try #require((page.live + page.stories).first { $0.title.contains("téléphones") })

        #expect(story.articleCount == 2)
        #expect(story.feedCount == 1)
        #expect(story.feedMarks.map(\.room) == ["lequotidien.example.com"])
        // And two desks of one paper are not several rooms, so nothing is
        // happening yet.
        #expect(!story.isLive)
    }

    @Test("The articles of a story are there, newest first")
    func articlesOfAStory() async throws {
        try await StoryBuilder(database).build(now: now)
        let story = try #require(try await service.digest(now: now).live.first)

        let articles = try await service.articles(of: story.id)
        #expect(articles.count == 4)
        #expect(articles.first?.date ?? .distantPast > articles.last?.date ?? .distantFuture)
    }

    @Test("What made no story is still in the wire")
    func looseArticles() async throws {
        try await StoryBuilder(database).build(now: now)

        // The front page shows stories and nothing else. The tail that used to
        // sit under it was the wire drawn a second time, and what grouped with
        // nothing is still there, in the section whose whole job is everything
        // as it arrived : that is what makes taking the tail away a tidying
        // rather than a hiding, and it is worth an expectation of its own.
        let wire = try await ArticleStore(database).summaries(.all, now: now)
        #expect(wire.contains { $0.title.contains("Cévennes") })

        // And the page itself is empty of them : a front page counting them as
        // content would render blank while insisting it is not.
        var bare = Digest()
        #expect(bare.isEmpty)
        bare.stories = try await service.digest(now: now).stories
        #expect(!bare.isEmpty)
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
        let brief = StorySummarizer.fallback(
            for: [
                (title: "Une réforme du calendrier scolaire", excerpt: "Le ministère envisage un décalage."),
                (title: "Autre chose", excerpt: nil),
            ],
            readIn: Locale(identifier: "fr_FR")
        )

        #expect(brief.title == "Une réforme du calendrier scolaire")
        #expect(brief.summary == "Le ministère envisage un décalage.")
        // And it says so : section 14 flags anything a model wrote, and this is
        // not that.
        #expect(!brief.isGenerated)
    }

    // MARK: - The head of a story nobody wrote a brief for

    @Test("The headline and the line come from one article, or the line does not come")
    func fallbackKeepsOneArticleWhole() {
        // What a real page showed : a Guardian letter about the Great Lakes
        // over a French line about a mapping application climbing the charts.
        let brief = StorySummarizer.fallback(
            for: [
                (title: "Donald Trump's shallow renaming of the Great Lakes | Letters", excerpt: nil),
                (
                    title: "Apple Maps renames Lake Ontario as Lake America",
                    excerpt: "Apple has renamed the lake for users in the United States."
                ),
            ],
            readIn: Locale(identifier: "en_GB")
        )

        #expect(brief.title == "Apple Maps renames Lake Ontario as Lake America")
        #expect(brief.summary == "Apple has renamed the lake for users in the United States.")
    }

    @Test("Where no article carries a line, the story is shown as a headline")
    func fallbackWithNoLineAnywhere() {
        let brief = StorySummarizer.fallback(
            for: [(title: "Une réforme du calendrier scolaire", excerpt: nil)],
            readIn: Locale(identifier: "fr_FR")
        )

        #expect(brief.title == "Une réforme du calendrier scolaire")
        #expect(brief.summary == nil)
    }

    @Test("The reader's own language decides which article stands for the story")
    func fallbackPrefersTheReadersLanguage() {
        let brief = StorySummarizer.fallback(
            for: [
                (
                    title: "Apple Maps renames Lake Ontario as Lake America after Trump order",
                    excerpt: "The change follows an executive order signed last week in Washington."
                ),
                (
                    title: "« Lac Ontario » vs « Lake America » : l'appli MapQuest tient tête à Donald Trump",
                    excerpt: "Une application de cartographie vient de doubler Google Maps au classement."
                ),
            ],
            readIn: Locale(identifier: "fr_FR")
        )

        #expect(brief.title.hasPrefix("« Lac Ontario »"))
        #expect(brief.summary?.hasPrefix("Une application") == true)
    }

    @Test("The furniture a template staples to a headline comes off")
    func headlineFurniture() {
        #expect(
            StorySummarizer.plainTitle("Climate injustices have been laid bare in the flood disaster | Letters")
                == "Climate injustices have been laid bare in the flood disaster"
        )
        #expect(
            StorySummarizer.plainTitle("Farewell Keir Starmer, a politician we wanted more from | Zoe Williams")
                == "Farewell Keir Starmer, a politician we wanted more from"
        )
        // What stands after the pipe has to be short, and what stands before it
        // has to still be a headline.
        #expect(StorySummarizer.plainTitle("Swift | Objective-C") == "Swift | Objective-C")
        let plain = "Une réforme du calendrier scolaire"
        #expect(StorySummarizer.plainTitle(plain) == plain)
    }

    // MARK: - What the model writes, and what is done about it

    @Test("A line whose first sentence is the headline again has spent itself")
    func aFirstSentenceThatRepeats() {
        let title = "La Russie revendique des frappes dans les régions de Kiev et d'Odessa"

        // Straight off the page : the headline, then two more sentences, which
        // used to pass because the line as a whole added enough words.
        #expect(
            StorySummarizer.repeats(
                title,
                in: """
                    La Russie revendique des frappes dans les régions de Kiev et d'Odessa. \
                    Vladimir Poutine justifie les frappes de représailles. Treize oblasts touchés.
                    """
            )
        )
        // And a line that names the same subject while going on to say
        // something is left alone.
        #expect(
            !StorySummarizer.repeats(
                title,
                in: """
                    Treize oblasts ukrainiens ont été touchés dans la nuit, et Kiev fait état de \
                    dégâts sur son réseau électrique.
                    """
            )
        )
    }

    @Test("A standfirst that ran long is cut back to the sentences that fit")
    func aLongLineIsCut() {
        let long = """
            Le président a annoncé la mesure lundi. Elle entrera en vigueur en janvier et concerne \
            les communes de plus de dix mille habitants. Les préfets disposeront de six mois pour \
            publier les arrêtés correspondants, et les recours devront être déposés avant la fin de \
            l'année suivante, faute de quoi ils seront jugés irrecevables par le tribunal.
            """
        let kept = try? #require(StorySummarizer.shortened(long))

        #expect(kept != nil)
        #expect(StorySummarizer.isBrief(kept ?? long))
        // Whole sentences, and the model's own words in its own order.
        #expect(kept?.hasPrefix("Le président a annoncé la mesure lundi.") == true)
        #expect(long.hasPrefix(kept ?? ""))

        // A single sentence that is itself a paragraph leaves nothing to keep.
        let oneBreath = String(repeating: "mot ", count: 60) + "."
        #expect(StorySummarizer.shortened(oneBreath) == nil)
    }

    @Test("A story with no articles has nothing to be named after")
    func emptyBrief() {
        let brief = StorySummarizer.fallback(for: [], readIn: Locale(identifier: "fr_FR"))

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

/// The two ways the model was quietly losing work.
///
/// Both were reported by the reader, and both are the same shape : a failure
/// the code could not tell from an answer. One left a fil with no thématique
/// for good ; the other let a made-up year through into the line above a story.
@Suite("What the model gets wrong, and what is done about it")
struct ModelFailureTests {
    private let articles: [(title: String, excerpt: String?)] = [
        ("Une réforme du calendrier scolaire", "Le ministère envisage un décalage de la rentrée."),
        ("La rentrée décalée à la mi-août", "Les fédérations de parents sont consultées."),
    ]

    // MARK: - A year nothing said

    @Test("A year the articles never mention is one the model made up")
    func inventedYear() {
        // The model is shown headlines and standfirsts and no dates at all, so
        // it has nothing to date anything by and fills the gap rather than
        // leaving it.
        #expect(
            StorySummarizer.inventedYear(
                title: "Réforme du calendrier",
                summary: "Le ministère a décidé en 2019 de décaler la rentrée.",
                from: articles
            ) == "2019"
        )
    }

    @Test("A year the articles do carry is one the model copied")
    func copiedYear() {
        let dated: [(title: String, excerpt: String?)] = [
            ("La réforme de 2019 revient", "Le texte de 2019 est rouvert."),
            ("Calendrier scolaire", "Une consultation s'ouvre."),
        ]

        // Copied, not invented, and a story genuinely about a year should be
        // allowed to say it.
        #expect(StorySummarizer.inventedYear(title: "La réforme de 2019", summary: "", from: dated) == nil)
    }

    @Test("A line with no year at all is left alone")
    func noYear() {
        #expect(
            StorySummarizer.inventedYear(
                title: "Réforme du calendrier",
                summary: "Le ministère envisage de décaler la rentrée.",
                from: articles
            ) == nil
        )
    }

    @Test("A number that is not a year is not mistaken for one")
    func notAYear() {
        // A count, a price, a page number. Only what a news article plausibly
        // names as a date counts.
        #expect(
            StorySummarizer.inventedYear(
                title: "12000 personnes attendues",
                summary: "Le billet coûte 45 euros, et 300 places restent.",
                from: articles
            ) == nil
        )
        // And one that looks like a year is caught even glued to punctuation.
        #expect(
            StorySummarizer.inventedYear(title: "Depuis (2018),", summary: "", from: articles) == "2018"
        )
    }

    // MARK: - What a headline has to be

    @Test("A headline stops being one somewhere past a dozen words")
    func headlineLength() {
        // Up to about ten sits in a reader's immediate memory. Twelve is where
        // the line is drawn rather than ten, so a good headline of eleven is
        // not thrown away for being one over the ideal.
        #expect(StorySummarizer.isShort("Le ministère avance la rentrée scolaire dans trois académies pilotes"))
        #expect(StorySummarizer.isShort(String(repeating: "mot ", count: StorySummarizer.maximumTitleWords)))
        #expect(!StorySummarizer.isShort(String(repeating: "mot ", count: StorySummarizer.maximumTitleWords + 1)))
    }

    @Test("An elision is one word, not two")
    func elisionsCountOnce() {
        // Counted on whitespace : a rule that split on apostrophes would make
        // every French headline half as long as it is.
        #expect(StorySummarizer.isShort("L'étude de l'impact de l'ozone sur l'agriculture d'altitude l'an prochain"))
    }

    @Test("A standfirst stops being one somewhere past a paragraph")
    func standfirstLength() {
        // A chapeau of one or two sentences runs to about twenty-five or forty
        // words. The ceiling is generous on purpose : what it is for is the
        // model that writes a paragraph, and rejecting a good standfirst of
        // forty-two words costs the reader a real line for nothing.
        #expect(
            StorySummarizer.isBrief(
                "Le ministère décale la rentrée à la mi-août dans trois académies pilotes, contre l'avis des syndicats."
            )
        )
        #expect(StorySummarizer.isBrief(String(repeating: "mot ", count: StorySummarizer.maximumSummaryWords)))
        #expect(!StorySummarizer.isBrief(String(repeating: "mot ", count: StorySummarizer.maximumSummaryWords + 1)))
    }

    @Test("Naming somebody does not make a standfirst too long")
    func abbreviationsDoNotSplitIt() {
        // Counted in words rather than sentences on purpose : a sentence
        // tokenizer splits `M. Dupont` in two, and a standfirst rejected for
        // naming somebody is a worse outcome than one that ran to three.
        #expect(StorySummarizer.isBrief("M. Dupont a signé l'arrêté. Mme Martin s'y oppose. Le Conseil tranchera."))
    }

    @Test("A story with no standfirst at all is not too long")
    func nothingIsBriefEnough() {
        #expect(StorySummarizer.isBrief(""))
    }

    @Test("A standfirst that says the headline again has said nothing")
    func standfirstMustAdd() {
        let title = "La rentrée avancée à la mi-août"

        // The shape that actually comes back : the headline repeated with a
        // clause bolted on.
        #expect(StorySummarizer.repeats(title, in: "La rentrée avancée à la mi-août, selon le ministère."))
        #expect(StorySummarizer.repeats(title, in: "LA RENTRÉE AVANCÉE À LA MI-AOÛT."))
    }

    @Test("A standfirst that names the same subject and then says something is kept")
    func standfirstMayNameTheSubject() {
        let title = "La rentrée avancée à la mi-août"

        // Rejecting this would reject most of what the model writes correctly :
        // a line about the reform will name the reform.
        #expect(
            !StorySummarizer.repeats(
                title,
                in: "La rentrée avancée à la mi-août concernerait trois académies pilotes, contre l'avis des syndicats."
            )
        )
        #expect(
            !StorySummarizer.repeats(
                title, in: "Trois académies désigneront leurs établissements avant la fin du mois."))
    }

    @Test("A headline with nothing under it is not a repeat of itself")
    func nothingIsNotARepeat() {
        #expect(!StorySummarizer.repeats("", in: ""))
        #expect(!StorySummarizer.repeats("Une réforme", in: ""))
    }

    // MARK: - A filing that never happened

    @Test("A vocabulary with nothing in it is no answer at all")
    func emptyVocabulary() async {
        let namer = TopicNamer(locale: Locale(identifier: "fr_FR"))

        // It used to come back as the model having considered the story and
        // placed it under nothing, so the caller stamped it as asked and never
        // came back to it. Nothing had been asked. A migration that left every
        // existing subject marked as the model's own emptied this list for one
        // run, and a whole page was stamped as answered by a question nobody
        // ever put : the standard sections were seeded an hour later and not
        // one story could ever be filed under them.
        guard case .unusable = await namer.file("Une réforme", summary: nil, into: []) else {
            Issue.record("An empty vocabulary is a question that was never asked")
            return
        }
    }
}

/// The three natures of a subject, and what the model is asked of each.
@Suite("Standard, personal and smart subjects")
struct TopicKindTests {
    private let database: AppDatabase
    private let topics: TopicPreferences
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() throws {
        database = try AppDatabase.inMemory()
        topics = TopicPreferences(database)
    }

    @Test("The sections every reader has are written down once")
    func seeding() async throws {
        try await topics.seedStandards(["Politique", "Économie"], at: now)
        try await topics.seedStandards(["Politique", "Économie"], at: now)

        let known = try await topics.known()
        #expect(known.count == 2)
        #expect(known.allSatisfy { $0.kind == .standard })
    }

    @Test("A section the reader had already written stays theirs")
    func seedingFolds() async throws {
        try await topics.add("écologie", at: now)
        try await topics.seedStandards(["Écologie", "Politique"], at: now)

        let known = try await topics.known()
        // Folded like everything else : one subject, and it is the reader's.
        #expect(known.count == 2)
        #expect(known.first { $0.name == "écologie" }?.kind == .own)
        #expect(known.first { $0.name == "Écologie" } == nil)
    }

    @Test("A section that has been renamed takes its stories and its preference with it")
    func renaming() async throws {
        let story = UUID.v7(at: now)
        try await topics.seedStandards(["Écologie"], at: now)
        try await topics.adjust("Écologie", by: 1)
        try await database.writer.write { db in
            try Story(id: story, title: "Une réforme", firstAt: now, lastAt: now, updatedAt: now).insert(db)
            try StoryTopic(storyID: story, name: "Écologie").insert(db)
        }

        // A section is known by its name and by nothing else, so renaming one
        // without moving the filings and the preference leaves the stories
        // under a name that no longer exists and the reader's word attached to
        // it.
        let changed = try await topics.seedStandards(
            ["Environnement"],
            renaming: [("Écologie", "Environnement")],
            at: now
        )

        #expect(changed)
        #expect(try await topics.known().map(\.name) == ["Environnement"])
        #expect(try await topics.score(of: "Environnement") == 1)
        #expect(
            try await database.writer.read { db in
                try String.fetchAll(db, sql: "SELECT name FROM story_topic")
            } == ["Environnement"]
        )
    }

    @Test("A rename that would land on a section that already exists is left alone")
    func renamingNeverMerges() async throws {
        try await topics.seedStandards(["Écologie", "Environnement"], at: now)

        // Merging two sections is a different decision, and not one a rename
        // may take by itself.
        _ = try await topics.seedStandards(
            ["Environnement"],
            renaming: [("Écologie", "Environnement")],
            at: now
        )

        #expect(try await topics.known().map(\.name).sorted() == ["Environnement", "Écologie"])
    }

    @Test("Seeding the sections asks again about the stories that were shown none")
    func seedingReopens() async throws {
        let asked = now.addingTimeInterval(-3600)
        let unfiled = UUID.v7(at: now)
        let filed = UUID.v7(at: now)

        try await database.writer.write { db in
            for (id, title) in [(unfiled, "Sans thématique"), (filed, "Déjà classé")] {
                try Story(id: id, title: title, firstAt: now, lastAt: now, updatedAt: now).insert(db)
                try db.execute(
                    sql: "UPDATE story SET topics_asked_at = ? WHERE id = ?",
                    arguments: [asked, id]
                )
            }
            // Filed under a name that is in no vocabulary, which is what the
            // model's own subjects became once it stopped naming them.
            try StoryTopic(storyID: unfiled, name: "Cybersécurité").insert(db)
        }
        // One story already under something the reader will recognize.
        try await topics.seedStandards(["Politique"], at: now)
        try await database.writer.write { db in
            try StoryTopic(storyID: filed, name: "Politique").insert(db)
            try db.execute(sql: "UPDATE story SET topics_asked_at = ? WHERE id = ?", arguments: [asked, filed])
        }

        try await topics.seedStandards(["Politique", "Économie"], at: now)

        let stamps = try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT id, topics_asked_at FROM story")
                .reduce(into: [UUID: Date?]()) { $0[$1["id"] as UUID] = $1["topics_asked_at"] as Date? }
        }
        // The one under nothing a reader recognizes is asked again. The one
        // already filed under a section keeps its answer : it was asked a
        // question the vocabulary could answer.
        #expect(stamps[unfiled] == .some(nil))
        #expect(stamps[filed] ?? nil != nil)
    }

    @Test("The model chooses from the whole vocabulary, the reader's own first")
    func settled() async throws {
        try await topics.seedStandards(["Politique"], at: now)
        try await topics.add("Typographie", at: now.addingTimeInterval(60))

        // It used to exclude a third kind, the ones the model had coined
        // itself : offering those back to it turned a page into a drift of near
        // synonyms, since it reached for whatever it said last. It coins
        // nothing now, so there is nothing to exclude. What the reader wrote
        // comes first, being what they will look for a story under.
        #expect(try await topics.settled() == ["Typographie", "Politique"])
    }

    @Test("A reader may unmake what they made, and nothing else")
    func removing() async throws {
        try await topics.seedStandards(["Politique"], at: now)
        try await topics.add("Typographie", at: now)

        for name in ["Politique", "Typographie"] {
            try await topics.remove(name)
        }

        // A standard section is not a thing that was made, so there is nothing
        // there to unmake.
        #expect(try await topics.known().map(\.name) == ["Politique"])
    }

    @Test("What a reader wrote comes before the sections, for the model to reach first")
    func ownFirst() async throws {
        try await topics.seedStandards(["Politique", "Économie"], at: now)
        try await topics.add("Typographie", at: now.addingTimeInterval(60))

        #expect(try await topics.settled().first == "Typographie")
    }
}

/// When the model is left alone, and when it is asked again.
///
/// The model failing is ordinary : the assets are still downloading, Apple
/// Intelligence is off, a backgrounded application has been rate-limited. What
/// matters is that none of those is permanent, and that giving up on the model
/// is therefore never permanent either.
@Suite("Giving up on the model, and coming back to it", .serialized)
struct ModelPatienceTests {
    init() { OnDeviceModel.reconsider() }

    private func refuse(_ error: LanguageModelSession.GenerationError, times: Int, at moment: Date) {
        for _ in 0..<times { OnDeviceModel.refused(error, now: moment) }
    }

    @Test("Three failures of the model itself are enough to leave it alone")
    func givesUp() {
        let now = Date()
        refuse(.assetsUnavailable(.init(debugDescription: "")), times: 3, at: now)

        #expect(OnDeviceModel.hasGivenUp(now: now))
    }

    @Test("It is asked again once the pause is over")
    func comesBack() {
        let now = Date()
        refuse(.assetsUnavailable(.init(debugDescription: "")), times: 3, at: now)

        // It was a one-way latch : nothing cleared the count but a success, and
        // no success is possible while every caller asks whether the model is
        // available first. Three failures and the model was off for the life of
        // the process, which on a Mac is days.
        #expect(!OnDeviceModel.hasGivenUp(now: now.addingTimeInterval(OnDeviceModel.refusalPause + 1)))
    }

    @Test("A model that is merely busy is not a model to give up on")
    func busyIsNotBroken() {
        let now = Date()
        // A backgrounded application's sessions are rate-limited hard, and
        // three of those used to silence the model for the rest of the process:
        // that is a night spent writing headlines and filing no subjects.
        refuse(.rateLimited(.init(debugDescription: "")), times: 10, at: now)

        #expect(!OnDeviceModel.hasGivenUp(now: now))
        // Still no answer about this story, so nothing is stamped as answered.
        #expect(
            OnDeviceModel.isTheModelItself(
                LanguageModelSession.GenerationError.rateLimited(.init(debugDescription: ""))))
    }

    @Test("A story the model will not write about does not count against it")
    func oneStoryIsNotTheModel() {
        let now = Date()
        refuse(.guardrailViolation(.init(debugDescription: "")), times: 10, at: now)

        // A page of security advisories trips the guardrail on some of its
        // stories and not others, and counting those would silence the model
        // for every story after them.
        #expect(!OnDeviceModel.hasGivenUp(now: now))
    }

    @Test("A success in between clears what came before it")
    func successForgives() {
        let now = Date()
        refuse(.assetsUnavailable(.init(debugDescription: "")), times: 2, at: now)
        OnDeviceModel.succeeded()
        OnDeviceModel.refused(
            LanguageModelSession.GenerationError.assetsUnavailable(.init(debugDescription: "")), now: now)

        #expect(!OnDeviceModel.hasGivenUp(now: now))
    }
}
