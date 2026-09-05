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
        #expect(edition.points.isEmpty)
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
        try await publish(evening.id)

        let later = now.addingTimeInterval(6 * 3600)
        let next = try #require(await editions.build(.standard, now: later, calendar: calendar))
        #expect(next.publishedAt == nil)

        let current = try #require(await editions.current(now: later))
        #expect(current.edition.id == evening.id)
        #expect(current.edition.points.count == 2)
    }

    @Test("The archive holds what was published and nothing else")
    func archiveIsPublishedOnly() async throws {
        try await story("Une", endingHoursAgo: 1)
        try await story("Deux", endingHoursAgo: 2)

        let edition = try #require(await editions.build(.standard, now: now, calendar: calendar))
        #expect(try await editions.archive(now: now).isEmpty)

        try await publish(edition.id)
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
        try await publish(edition.id)

        let muchLater = now.addingTimeInterval(EditionStore.archived + 24 * 3600)
        _ = try await editions.purge(now: muchLater)

        #expect(try await editions.archive(now: muchLater).isEmpty)
    }

    private func publish(_ id: UUID) async throws {
        try await database.writer.write { db in
            guard var edition = try Edition.fetchOne(db, key: id) else { return }
            edition.points = ["Deux ouvriers sauvés au Népal.", "Gaël Monfils quitte l'US Open."]
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

/// The checks an edition's list is held to.
///
/// **There are three left, and there were seven.** An edition carried a name of
/// its own, and every one of the checks that name needed went with it : that it
/// is short, that it is not one of the headlines, that it is about something on
/// the page, that it does not weld two stories together, and the mend by hand
/// when the model would not stop doing that. A front page has never had a name,
/// and `docs/technical/digest.md` records the three attempts at one.
@Suite("What an edition's list is held to")
struct EditionBriefChecksTests {
    private let french = Locale(identifier: "fr_FR")
    private let page: [(title: String, summary: String?)] = [
        ("Deux ouvriers sauvés au Népal", "Neuf jours après la catastrophe."),
        ("Gaël Monfils éliminé à l'US Open", "Au deuxième tour, en quatre sets."),
    ]
    private let good = ["Deux ouvriers ont été sortis vivants d'un tunnel.", "Gaël Monfils quitte l'US Open."]

    /// **A list, and it was a paragraph.** Asked for two or three sentences
    /// over ten stories the model wrote one clause per story and joined them
    /// with commas : seven items and eight lines of type under the headline.
    @Test("One point on its own is not a list")
    func notAList() {
        #expect(EditionSummarizer.fault(["Deux ouvriers sauvés au Népal."], over: page) != nil)
    }

    /// Forty words is a paragraph however short the words are.
    @Test("A point that runs to a paragraph is asked for again")
    func aPointThatIsAParagraph() {
        let long = String(repeating: "mot ", count: 40)
        #expect(EditionSummarizer.fault([long, "Court."], over: page) != nil)
    }

    /// **The bound is on the thought and not on the letters.** A hundred
    /// characters was sixteen French words and eighteen English ones, so the
    /// same rule gave a French reader less to be told than an English one ; and
    /// the page it was measured against was an iPad's column, not the phone it
    /// shipped to. Long words that fit pass where a hundred characters did not,
    /// and a run of short ones fails where a hundred characters did.
    @Test("A point is bounded in words and not in letters")
    func boundIsInWords() {
        let longWords = Array(repeating: "circonstanciel", count: EditionSummarizer.maximumPointWords)
            .joined(separator: " ")
        let manyShort = Array(repeating: "un", count: EditionSummarizer.maximumPointWords + 1)
            .joined(separator: " ")

        #expect(longWords.count > 100)
        #expect(EditionSummarizer.isBrief(longWords))
        #expect(manyShort.count < 100)
        #expect(!EditionSummarizer.isBrief(manyShort))
    }

    /// Counted on whitespace, so an elision is the one word it is : `l'étude` is
    /// not two. The story briefs count the same way, and two bounds that counted
    /// differently would be counting two different things.
    @Test("An elision is the one word it is")
    func elisionIsOneWord() {
        let point = Array(repeating: "l'étude", count: EditionSummarizer.maximumPointWords)
            .joined(separator: " ")
        #expect(EditionSummarizer.isBrief(point))
    }

    /// A bound written in the guide and again in the constant is a bound that
    /// stops agreeing with itself the first time one of the two is changed, and
    /// it had : the guide said a hundred characters while the page's own
    /// documentation said a hundred and twenty.
    @Test("What the model is asked for names the bound it is held to")
    func guideNamesTheBound() {
        #expect(EditionSummarizer.pointGuide.contains("\(EditionSummarizer.maximumPointWords) words"))
    }

    /// The model is shown headlines and standfirsts and nothing else, so it has
    /// nothing to date anything by, and a model of this size fills that gap
    /// rather than leaving it. The page already says when every story on it
    /// arrived, to the minute.
    @Test("A year nothing on the page mentions is asked for again")
    func inventedYear() {
        #expect(EditionSummarizer.fault(["Le bilan de 2019 est tombé.", "Court."], over: page) != nil)
    }

    @Test("A list that says something is left alone")
    func settled() {
        #expect(EditionSummarizer.fault(good, over: page) == nil)
    }

    /// The model writes `1. ` or `- ` in front of its own list items about half
    /// the time, and the page draws its own marks.
    @Test("The numbering a model puts in front of its list comes off")
    func numberingComesOff() {
        #expect(
            EditionSummarizer.tidied(["1. Deux ouvriers sauvés", "- Monfils éliminé", "  ", "3) Un jeu vidéo"])
                == ["Deux ouvriers sauvés", "Monfils éliminé", "Un jeu vidéo"]
        )
    }

    /// `maximumCount` guides the model and does not bind it, so the bound is
    /// kept here as well : a page drawn from an answer that ignored the guide
    /// would be the paragraph this replaced with rules in front of it.
    @Test("A list longer than five is cut to five")
    func boundedAtFive() {
        let many = (1...9).map { "Point \($0)" }
        #expect(EditionSummarizer.tidied(many).count == EditionSummarizer.mostPoints)
    }

    /// The one check that is not style. A page in a language the reader does
    /// not read is not a page they can use, and there is no floor under it to
    /// fall back to : an edition exists only where the model wrote it.
    @Test("A list in the wrong language is not a page the reader can use")
    func language() {
        guard OnDeviceModel.writes(french) else { return }
        #expect(
            EditionSummarizer.languageFault(
                ["Two workers were pulled alive from a tunnel in Nepal.", "Monfils is out of the US Open."],
                in: french
            ) != nil
        )
        #expect(EditionSummarizer.languageFault(good, in: french) == nil)
    }
}

/// Which mark each of an edition's points wears.
///
/// The model writes three to five sentences over ten stories and nothing links
/// one to the other : it is free to say one thing about two of them, and asking
/// it for a story identifier alongside each point would be index bookkeeping,
/// which a small model does badly and which the filing already learnt not to
/// ask for. So the two are compared rather than declared.
@Suite("The mark a point wears")
struct EditionMarkTests {
    private func story(_ title: String, _ id: UUID = .v7()) -> EditionStory {
        EditionStory(
            editionID: .v7(), position: 0, storyID: id, title: title,
            summary: nil, isGenerated: true, isTranslated: false, imageURL: nil)
    }

    @Test("A point takes the subject of the story it shares the most words with")
    func matched() {
        let nepal = UUID.v7()
        let tennis = UUID.v7()
        let stories = [story("Deux ouvriers sauvés au Népal", nepal), story("Monfils éliminé à l'US Open", tennis)]
        let filings = [nepal: ["International"], tennis: ["Sport"]]
        let symbols = ["International": "globe", "Sport": "figure.run"]

        let marks = EditionStore.marks(
            for: [
                "Gaël Monfils est éliminé à l'US Open.",
                "Deux ouvriers ont été sauvés au Népal.",
            ],
            over: stories, filedAs: filings, wearing: symbols
        )

        #expect(marks == ["figure.run", "globe"])
    }

    /// A point about something the filing never reached is an ordinary state
    /// rather than a fault : half a mark on a row of marks would read worse
    /// than a neutral one.
    @Test("A point that matches nothing wears the tag")
    func unmatched() {
        let marks = EditionStore.marks(
            for: ["Il pleut sur la Bretagne."],
            over: [story("Deux ouvriers sauvés au Népal")],
            filedAs: [:],
            wearing: [:]
        )

        #expect(marks == [Topic.defaultSymbol])
    }

    /// A story filed under nothing has no mark to lend, and a subject with no
    /// mark of its own falls back the same way.
    @Test("A story under no subject lends nothing, and neither does a subject with no mark")
    func nothingToLend() {
        let id = UUID.v7()
        let stories = [story("Deux ouvriers sauvés au Népal", id)]

        #expect(
            EditionStore.marks(
                for: ["Deux ouvriers sauvés au Népal."], over: stories, filedAs: [:], wearing: [:])
                == [Topic.defaultSymbol]
        )
        #expect(
            EditionStore.marks(
                for: ["Deux ouvriers sauvés au Népal."], over: stories,
                filedAs: [id: ["International"]], wearing: [:])
                == [Topic.defaultSymbol]
        )
    }

    /// One mark per point and in the same order, whatever the page holds : the
    /// two lists are drawn side by side and a page with fewer marks than points
    /// would put the wrong glyph on every line after the gap.
    @Test("There is one mark per point, in the same order")
    func oneEach() {
        let points = ["Une chose.", "Une autre.", "Une troisième."]
        let marks = EditionStore.marks(for: points, over: [], filedAs: [:], wearing: [:])

        #expect(marks.count == points.count)
    }
}

@Suite("Telling the reader an edition has come out")
struct EditionNoticeTests {
    private func edition(points: [String]) -> Edition {
        Edition(
            slot: .morning,
            openedAt: Date(timeIntervalSince1970: 1_788_000_000),
            points: points,
            publishedAt: Date()
        )
    }

    /// **The one notice whose words are already written.** Everything else is a
    /// sentence assembled from names ; this arrives carrying a headline and a
    /// line the model wrote over the whole page, and writing anything of our
    /// own on top would be a third opinion about a page that already has one.
    @Test("The notice names the edition and says its own points")
    func wording() {
        let announcement = try? #require(
            Announcement.newEdition(
                edition(points: ["L'Assemblée a rejeté le texte.", "La CGT reconduit la grève."])
            )
        )

        // The edition names itself in the one bold line a banner gives a title,
        // which is where the dateline stands on the page for the same reason.
        #expect(announcement?.title == String(localized: EditionSlot.morning.title))
        // A middle dot rather than commas, as the headlines are joined
        // everywhere else here : a point may hold commas of its own.
        #expect(announcement?.body == "L'Assemblée a rejeté le texte. · La CGT reconduit la grève.")
        // A tap opens the digest, where the edition is. There is no deeper
        // place to go : the edition is the front page.
        #expect(announcement?.story == nil)
        #expect(announcement?.article == nil)
    }

    @Test("A page the model has not written says nothing at all")
    func nothingToSay() {
        #expect(Announcement.newEdition(edition(points: [])) == nil)
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
    /// whole of what `indexing always happens behind` means.
    ///
    /// What is asserted is that it does the work, and it is asked for directly
    /// rather than through the scheduling. A test that started the lane and
    /// then waited for the queue to empty failed whenever the machine was busy,
    /// which is exactly when a task at background priority is least likely to
    /// be served : it was asserting that the system is prompt, which is neither
    /// true nor anything this code decides.
    @Test("The lane does the work it is asked for")
    func drains() async throws {
        try await article(named: "Une réforme", about: "Claire Ancelin")
        #expect(try await NewsmakerStore(database).outstandingCount() > 0)

        await model.indexWhatIsWaiting()

        #expect(try await NewsmakerStore(database).outstandingCount() == 0)
    }

    /// And asking for it is a call that returns : no `await` here is the
    /// property, and asking twice is asking once, since what the lane does is
    /// bring the index up to what the store says now.
    @Test("Asking for indexing is never waited on")
    func neverWaitedOn() async throws {
        try await article(named: "Un procès", about: "Paul Rey")

        model.index()
        model.index()
    }
}
