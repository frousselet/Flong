//
//  EditionTests.swift
//  FlongTests
//
//  Created by François Rousselet on 04/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import Testing

@testable import Flong

@Suite("When an edition comes out")
struct EditionScheduleTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }()

    private func moment(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)) ?? Date()
    }

    @Test("The current edition is the most recent boundary that has passed")
    func current() {
        let schedule = EditionSchedule.standard

        let morning = schedule.current(at: moment(4, 9), in: calendar)
        #expect(morning?.slot == .morning)
        #expect(morning?.opened == moment(4, 7))

        let evening = schedule.current(at: moment(4, 20), in: calendar)
        #expect(evening?.slot == .evening)
        #expect(evening?.opened == moment(4, 18))
    }

    /// **Yesterday's last edition is looked at too.** A reader opening Flong at
    /// six in the morning is before every boundary of their own day, and a
    /// front page that told them there was no edition rather than handing them
    /// last night's would be a page that goes blank every night.
    @Test("Before the first boundary of the day, last night's edition still stands")
    func beforeTheFirstBoundary() {
        let schedule = EditionSchedule.standard
        let early = schedule.current(at: moment(4, 6), in: calendar)

        #expect(early?.slot == .night)
        #expect(early?.opened == moment(3, 23))
    }

    @Test("The next boundary is what the system is asked to wake for")
    func next() {
        let schedule = EditionSchedule.standard

        #expect(schedule.next(after: moment(4, 9), in: calendar) == moment(4, 12))
        // Past the last of the day, the next one is tomorrow's first.
        #expect(schedule.next(after: moment(4, 23, 30), in: calendar) == moment(5, 7))
    }

    @Test("An edition the reader moved comes out when they said")
    func moved() {
        var schedule = EditionSchedule.standard
        schedule.hours[.morning] = 6 * 60 + 30

        #expect(schedule.current(at: moment(4, 6, 45), in: calendar)?.slot == .morning)
        #expect(schedule.current(at: moment(4, 6, 15), in: calendar)?.slot == .night)
    }

    /// Every edition switched off is a legitimate answer, and it means there is
    /// no front page rather than that there is an empty one.
    @Test("With every edition off there is no edition and nothing to wake for")
    func none() {
        let schedule = EditionSchedule(hours: [:])

        #expect(schedule.slots.isEmpty)
        #expect(schedule.current(at: moment(4, 9), in: calendar) == nil)
        #expect(schedule.next(after: moment(4, 9), in: calendar) == nil)
    }
}

@Suite("The edition, and its archive", .serialized)
struct EditionStoreTests {
    private let database: AppDatabase
    private let editions: EditionStore
    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }()

    init() throws {
        database = try AppDatabase.inMemory()
        editions = EditionStore(database)
    }

    /// A story of several articles from several rooms, ending some hours ago.
    ///
    /// Written straight into the store : what these tests pin is which stories
    /// reach a page and in what order, and grouping a corpus to get there would
    /// be testing the grouping.
    @discardableResult
    private func story(
        _ title: String,
        endingHoursAgo hours: Double,
        articles count: Int = 2,
        written: Bool = true
    ) async throws -> UUID {
        let last = now.addingTimeInterval(-hours * 3600)
        var story = Story(id: .v7(at: last), title: title, firstAt: last, lastAt: last, updatedAt: last)
        story.isGenerated = written
        story.summary = written ? "Ce qui s'est passé, en une ligne." : nil

        try await database.writer.write { db in
            try story.insert(db)
            for index in 0..<count {
                let host = "edition-\(abs(title.hashValue))-\(index).example.com"
                var feed = Feed(url: URL(string: "https://\(host)/f.xml")!, title: host)
                feed.siteURL = URL(string: "https://\(host)")
                try feed.insert(db)

                // Spread backwards, so nothing is recent enough to be live and
                // the order under test is the ordinary one.
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
        return story.id
    }

    private func rows(of editionID: UUID) async throws -> [EditionStory] {
        try await database.writer.read { db in
            try EditionStory
                .filter(Column("edition_id") == editionID)
                .order(Column("position"))
                .fetchAll(db)
        }
    }

    @Test("An edition holds ten stories, and the rest is the wire")
    func tenAndNoMore() async throws {
        for index in 0..<14 {
            try await story("Actualité \(index)", endingHoursAgo: Double(index))
        }

        let edition = try #require(await editions.build(.standard, now: now, calendar: calendar))
        let held = try await rows(of: edition.id)

        #expect(held.count == EditionStore.mostStories)
        // The page's own order : the most recent first, since nothing here has
        // a subject the reader has spoken about.
        #expect(held.first?.title == "Actualité 0")
    }

    /// **Only stories the model has written about.** It is what makes `every
    /// edition is written` a rule rather than an aspiration : a story both
    /// voices declined would otherwise stand at the top of a page that could
    /// never be published, and one refusal would silence the front page for a
    /// day.
    @Test("A story the model would not write about does not reach the page")
    func onlyWhatTheModelWrote() async throws {
        try await story("Écrite", endingHoursAgo: 1)
        try await story("Refusée", endingHoursAgo: 0.5, written: false)

        let edition = try #require(await editions.build(.standard, now: now, calendar: calendar))
        let held = try await rows(of: edition.id)

        #expect(held.map(\.title) == ["Écrite"])
    }

    /// A device with no model writes about no story, so it builds no edition at
    /// all. That is section 14's no-model path answered honestly rather than by
    /// putting a publisher's headline over a page and calling it written.
    @Test("With nothing written there is an edition holding nothing, and nothing to publish")
    func noModelNoPage() async throws {
        try await story("Une", endingHoursAgo: 1, written: false)
        try await story("Deux", endingHoursAgo: 2, written: false)

        let edition = try #require(await editions.build(.standard, now: now, calendar: calendar))

        #expect(try await rows(of: edition.id).isEmpty)
        #expect(edition.title == nil)
        #expect(try await editions.current() == nil)
    }

    @Test("Building twice at one boundary is one edition")
    func idempotent() async throws {
        try await story("Une", endingHoursAgo: 1)
        try await story("Deux", endingHoursAgo: 2)

        let first = try #require(await editions.build(.standard, now: now, calendar: calendar))
        let second = try #require(await editions.build(.standard, now: now, calendar: calendar))

        #expect(first.id == second.id)
        let count = try await database.writer.read { db in try Edition.fetchCount(db) }
        #expect(count == 1)
    }

    /// An edition stops being the current one when the next boundary passes,
    /// and it keeps the ten it had rather than being rewritten by the page as
    /// it stands afterwards.
    @Test("The next boundary closes the one before it, which keeps its ten")
    func closing() async throws {
        try await story("Ce matin", endingHoursAgo: 1)
        try await story("Aussi ce matin", endingHoursAgo: 2)

        let morning = try #require(await editions.build(.standard, now: now, calendar: calendar))
        let held = try await rows(of: morning.id).map(\.title)

        // Five hours on, past the next boundary, with a newer story in the
        // store.
        let later = now.addingTimeInterval(6 * 3600)
        try await story("Cet après-midi", endingHoursAgo: -5.5)
        let next = try #require(await editions.build(.standard, now: later, calendar: calendar))

        #expect(next.id != morning.id)
        #expect(try await rows(of: morning.id).map(\.title) == held)

        let closed = try await database.writer.read { db in try Edition.fetchOne(db, key: morning.id) }
        #expect(closed?.closedAt != nil)
    }

    /// **The newest published one, and not the newest one.** The edition of the
    /// moment is being written for the first minutes of its life, and a page
    /// that emptied while the model worked would go blank four times a day.
    @Test("A page still being written does not take the last one off the screen")
    func theLastOneStands() async throws {
        try await story("Hier soir", endingHoursAgo: 10)
        try await story("Hier soir encore", endingHoursAgo: 11)

        let evening = try #require(await editions.build(.standard, now: now, calendar: calendar))
        try await publish(evening.id, titled: "Ce que dit la soirée")

        let later = now.addingTimeInterval(6 * 3600)
        let next = try #require(await editions.build(.standard, now: later, calendar: calendar))
        #expect(next.publishedAt == nil)

        let current = try #require(await editions.current(now: later))
        #expect(current.edition.id == evening.id)
        #expect(current.edition.title == "Ce que dit la soirée")
    }

    @Test("The archive holds what was published and nothing else")
    func archiveIsPublishedOnly() async throws {
        try await story("Une", endingHoursAgo: 1)
        try await story("Deux", endingHoursAgo: 2)

        let edition = try #require(await editions.build(.standard, now: now, calendar: calendar))
        #expect(try await editions.archive(now: now).isEmpty)

        try await publish(edition.id, titled: "Titrée")
        #expect(try await editions.archive(now: now).map(\.edition.id) == [edition.id])
    }

    /// An edition older than the window its stories are held to is a page of
    /// headlines whose articles have gone, and one that closed without ever
    /// being written is not an edition at all.
    @Test("The purge takes what has fallen out of the window")
    func purge() async throws {
        try await story("Une", endingHoursAgo: 1)
        try await story("Deux", endingHoursAgo: 2)

        let edition = try #require(await editions.build(.standard, now: now, calendar: calendar))
        try await publish(edition.id, titled: "Titrée")

        let muchLater = now.addingTimeInterval(EditionStore.archived + 24 * 3600)
        _ = try await editions.purge(now: muchLater)

        #expect(try await editions.archive(now: muchLater).isEmpty)
    }

    private func publish(_ id: UUID, titled title: String) async throws {
        try await database.writer.write { db in
            guard var edition = try Edition.fetchOne(db, key: id) else { return }
            edition.title = title
            edition.summary = "Trois choses, en trois phrases."
            edition.briefLocale = Locale(identifier: "fr_FR").identifier
            edition.publishedAt = Date()
            try edition.update(db)
        }
    }
}

@Suite("What an edition is asked about")
struct EditionBriefWorkTests {
    private let database: AppDatabase
    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    init() throws {
        database = try AppDatabase.inMemory()
    }

    /// The rule is the story's rule, over a whole page : has the model been
    /// asked about *these articles*, in *this language*?
    @Test("A page asked about in this language, over these articles, is not asked again")
    func settled() async throws {
        let locale = Locale(identifier: "fr_FR")
        let work = BriefEditionsJob.work(locale: locale, since: now.addingTimeInterval(-EditionStore.archived))

        #expect(work.sql.contains("brief_locale"))
        #expect(work.sql.contains("brief_members"))
        // Every article of every story on the page, and not a sample of them :
        // an article joining any story is a slightly different page, and the
        // sentence over it is a question worth putting again.
        #expect(BriefEditionsJob.membersKey.contains("story_member"))
        #expect(BriefEditionsJob.membersKey.contains("edition_story"))
        #expect(!BriefEditionsJob.membersKey.contains("LIMIT"))
    }

    /// Without a model there is nothing to ask, so the queue is empty rather
    /// than permanently full : a job that offered the same page at every turn
    /// would stop everything behind it for ever.
    @Test("Without a model there is nothing waiting to be named")
    func nothingToDoWithoutAModel() async throws {
        guard !OnDeviceModel.isAvailable else { return }
        #expect(try await BriefEditionsJob(database, now: now).remaining() == 0)
    }
}

/// The checks an edition's own headline is held to, which are a story's checks
/// asked over a page.
@Suite("What an edition's headline is held to")
struct EditionBriefChecksTests {
    private let french = Locale(identifier: "fr_FR")
    private let page: [(title: String, summary: String?)] = [
        ("Deux ouvriers sauvés au Népal", "Neuf jours après la catastrophe."),
        ("Gaël Monfils éliminé à l'US Open", "Au deuxième tour, en quatre sets."),
    ]

    @Test("A name of twenty words is a sentence, and is asked for again")
    func tooLong() {
        let long = String(repeating: "mot ", count: 20)
        #expect(EditionSummarizer.fault(title: long, summary: "Une phrase.", in: french, over: page) != nil)
    }

    /// **The one the first real page tripped over.** The model named a morning
    /// `Deux ouvriers sauvés au Népal, Gaël Monfils éliminé, et plus` and wrote
    /// the same sentence again underneath, word for word. The story briefs have
    /// checked for exactly that from the beginning ; the edition did not.
    @Test("A summary that repeats the name has said nothing, and is asked for again")
    func repeatsTheName() {
        let name = "Deux ouvriers sauvés au Népal, Gaël Monfils éliminé"
        #expect(EditionSummarizer.fault(title: name, summary: name, in: french, over: page) != nil)
    }

    /// **The page is not its lead.** Shown six headlines the model hands back
    /// the first one, and the page then reads the same sentence twice : once as
    /// the name of the edition and again as the headline directly under it.
    /// Measured on a real morning, which is where it was found.
    @Test("A name that is one of the headlines is asked for again")
    func namedAfterItsLead() {
        #expect(
            EditionSummarizer.fault(
                title: "Deux ouvriers sauvés au Népal",
                summary: "Neuf jours après la catastrophe, deux hommes sont sortis vivants.",
                in: french,
                over: page
            ) != nil
        )
    }

    @Test("A name and a line that each say something are left alone")
    func settled() {
        #expect(
            EditionSummarizer.fault(
                title: "Sauvetage au Népal et sortie de Monfils",
                summary: "Deux ouvriers ont été retrouvés vivants neuf jours après la catastrophe. "
                    + "Gaël Monfils a quitté l'US Open au deuxième tour.",
                in: french,
                over: page
            ) == nil
        )
    }

    /// The page already says when every story on it arrived, and the model is
    /// shown no dates at all, so a year in a name is a year it invented.
    @Test("A year nothing on the page mentions is asked for again")
    func inventedYear() {
        #expect(
            EditionSummarizer.fault(
                title: "Le bilan de 2019",
                summary: "Deux ouvriers ont été retrouvés vivants.",
                in: french,
                over: page
            ) != nil
        )
    }
}

@Suite("Telling the reader an edition has come out")
struct EditionNoticeTests {
    private func edition(title: String?, summary: String?) -> Edition {
        Edition(
            slot: .morning,
            openedAt: Date(timeIntervalSince1970: 1_788_000_000),
            title: title,
            summary: summary,
            publishedAt: Date()
        )
    }

    /// **The one notice whose words are already written.** Everything else is a
    /// sentence assembled from names ; this arrives carrying a headline and a
    /// line the model wrote over the whole page, and writing anything of our
    /// own on top would be a third opinion about a page that already has one.
    @Test("The notice is the edition's own headline and its own line")
    func wording() {
        let announcement = try? #require(
            Announcement.newEdition(edition(title: "Budget rejeté", summary: "L'Assemblée a rejeté le texte.")))

        #expect(announcement?.title == "Budget rejeté")
        #expect(announcement?.body == "L'Assemblée a rejeté le texte.")
        // A tap opens the digest, where the edition is. There is no deeper
        // place to go : the edition is the front page.
        #expect(announcement?.story == nil)
        #expect(announcement?.article == nil)
    }

    @Test("A page with no headline of its own says nothing at all")
    func nothingToSay() {
        #expect(Announcement.newEdition(edition(title: nil, summary: nil)) == nil)
        #expect(Announcement.newEdition(edition(title: "Titrée", summary: nil)) == nil)
        #expect(Announcement.newEdition(edition(title: "", summary: "Une ligne.")) == nil)
    }
}

/// **Indexing always happens behind, and never on a path the reader waits on.**
///
/// It did not. The system index was written from the read behind every render
/// and every store tick, and from six foreground gestures that each awaited it,
/// and the backlog of people to read out of a hundred thousand articles ran at
/// the tail of the gesture that wrote the headlines.
@Suite("The indexing lane", .serialized)
@MainActor
struct IndexingLaneTests {
    private let database: AppDatabase
    private let model: AppModel

    init() throws {
        database = try AppDatabase.inMemory()
        model = AppModel(database: database)
    }

    /// A feed and an article that names somebody, which is what the queue the
    /// lane drains is made of.
    private func article(named title: String, about person: String) async throws {
        var feed = Feed(url: URL(string: "https://lane.example.com/atom.xml")!, title: "Le Monde")
        feed.siteURL = URL(string: "https://lane.example.com")

        var entry = Entry(
            feedID: feed.id,
            guid: "urn:\(title)",
            title: title,
            excerpt: "\(person) a parlé ce matin.",
            receivedAt: Date()
        )
        entry.hasMedia = false

        try await database.writer.write { db in
            try feed.insert(db)
            try entry.insert(db)
        }
    }

    /// **The point of the lane is in the call and not in the timing.**
    /// `index()` is not `async` : there is no `await` at any of its call sites,
    /// so no gesture, no render and no store tick can wait on it, which is the
    /// whole of what `indexing always happens behind` means. A test that
    /// asserted the queue was still full a line later would be asserting that
    /// the lane is slow, which is neither true nor wanted.
    ///
    /// What is worth pinning is the other half : it does get done, and asking
    /// twice is asking once, since what the lane does is bring the index up to
    /// what the store says now.
    @Test("The lane is never waited on, and drains the queue all the same")
    func drains() async throws {
        try await article(named: "Une réforme", about: "Claire Ancelin")
        #expect(try await NewsmakerStore(database).outstandingCount() > 0)

        // No `await` : that is the property.
        model.index()
        model.index()

        // The lane runs behind the caller, so a test waits for the queue rather
        // than for the task.
        for _ in 0..<200 {
            if try await NewsmakerStore(database).outstandingCount() == 0 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(try await NewsmakerStore(database).outstandingCount() == 0)
    }
}
