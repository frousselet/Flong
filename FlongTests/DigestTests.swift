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
        }

        let work = BriefStoriesJob.work(locale: Locale(identifier: "fr_FR"), hasModel: true)
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
        }

        let withModel = BriefStoriesJob.work(locale: Locale(identifier: "fr_FR"), hasModel: true)
        let without = BriefStoriesJob.work(locale: Locale(identifier: "fr_FR"), hasModel: false)

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

        try await TopicPreferences(database).record("Software")
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
        try await TopicPreferences(database).record("Logiciel")
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
        // One the model found, holding nothing today.
        try await preferences.record("Cyclotourisme")

        let page = try await service.digest(now: now)

        // A reader who has just written a subject and cannot see it has no way
        // of knowing it took.
        #expect(page.topics.contains("Cyclisme"))
        // One the model found was never asked for, and is on the page only
        // while it holds something.
        #expect(!page.topics.contains("Cyclotourisme"))
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

    @Test("A headline dressed as a subject is not a subject")
    func fieldsRatherThanStories() {
        let headline = "Les macros Swift, deux ans après"

        #expect(TopicNamer.isField("Logiciel", of: headline))
        #expect(TopicNamer.isField("Développement logiciel", of: headline))

        // The headline back, in whole or in part.
        #expect(!TopicNamer.isField("Les macros Swift", of: headline))
        #expect(!TopicNamer.isField("macros swift", of: headline))
        // A sentence is not a field.
        #expect(!TopicNamer.isField("Ce que les macros ont changé au code", of: headline))
        #expect(!TopicNamer.isField("   ", of: headline))
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

        // Everything but what is already filed, on a machine with a model ;
        // nothing at all on one without, since there is nothing it could do.
        #expect(left == (OnDeviceModel.isAvailable ? stories - filed : 0))
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

    @Test("What the model comes back with is folded into the vocabulary")
    func modelSubjectsAreFolded() async throws {
        let preferences = TopicPreferences(database)
        try await preferences.add("Sécurité informatique")

        // The model answering the same subject in another spelling has not
        // found a new one.
        #expect(try await preferences.record("sécurité informatique") == "Sécurité informatique")
        #expect(try await preferences.record("Typographie") == "Typographie")

        let known = try await preferences.known()
        #expect(known.map(\.name).sorted() == ["Sécurité informatique", "Typographie"])
        #expect(known.first { $0.name == "Typographie" }?.isOwn == false)
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

    @Test("A subject the model found is not the reader's to delete")
    func removingAModelSubject() async throws {
        let preferences = TopicPreferences(database)
        try await preferences.record("Typographie")

        try await preferences.remove("Typographie")

        // It would only be found again on the next page. What a reader wants
        // from one of those is the preference.
        #expect(try await preferences.known().map(\.name) == ["Typographie"])
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

        // What was spoken about comes first.
        #expect(known.first?.name == "Logiciel")
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
    /// what the model does when there is one. A story may take several.
    private func put(_ topics: [String: String]) async throws {
        // Through the vocabulary, as the naming job does : a subject is a
        // thing before it is a filing.
        for topic in Set(topics.values) {
            try await TopicPreferences(database).record(topic)
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
        #expect(Set(story.feedMarks.map(\.title)) == Set(Corpus.calendar.map(\.feed)))
        // In the order the rooms picked it up.
        #expect(story.feedMarks.first?.title == "Le Quotidien")
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

    @Test("What made no story is still reachable")
    func looseArticles() async throws {
        try await StoryBuilder(database).build(now: now)

        let loose = try await service.looseArticles(now: now)
        #expect(loose.count == Corpus.loose.count)
        #expect(loose.contains { $0.title.contains("Cévennes") })
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
