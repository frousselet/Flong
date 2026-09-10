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
import UserNotifications

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

    /// A Saturday, twenty to one in the afternoon, in Paris.
    ///
    /// The boundary that has gone is noon, so a page made here is the midday
    /// edition and its period ends at midday. Everything below is said in hours
    /// before that hour rather than before this moment, since what a page holds
    /// is a question about its period and never about the moment it is made.
    private let now = Date(timeIntervalSince1970: 1_788_000_000)
    private var noon: Date { now.addingTimeInterval(-40 * 60) }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }()

    init() throws {
        database = try AppDatabase.inMemory()
        editions = EditionStore(database)
    }

    /// A story of several articles from several rooms, ending some hours before
    /// the midday boundary.
    ///
    /// Written straight into the store : what these tests pin is which stories
    /// reach a page and in what order, and grouping a corpus to get there would
    /// be testing the grouping.
    @discardableResult
    private func story(
        _ title: String,
        endingHoursBeforeNoon hours: Double,
        articles count: Int = 2,
        written: Bool = true,
        groupedHoursBeforeNoon grouped: Double? = nil
    ) async throws -> UUID {
        let last = noon.addingTimeInterval(-hours * 3600)
        // The key is minted where the grouping runs, which is not where the
        // articles are dated : a publisher may stamp this morning's item with
        // last week's date.
        let minted = grouped.map { noon.addingTimeInterval(-$0 * 3600) } ?? last
        var story = Story(id: .v7(at: minted), title: title, firstAt: last, lastAt: last, updatedAt: last)
        story.isGenerated = written
        story.summary = written ? "Ce qui s'est passé, en une ligne." : nil
        // Asked about and answered, so nothing here is a story the coming page
        // is still waiting on : the readiness of a period is its own suite.
        story.briefLocale = written ? Locale.current.identifier : nil

        try await database.writer.write { [story] db in
            try story.insert(db)
            for index in 0..<count {
                let host = "edition-\(abs(title.hashValue))-\(index).example.com"
                var feed = Feed(url: URL(string: "https://\(host)/f.xml")!, title: host)
                feed.siteURL = URL(string: "https://\(host)")
                try feed.insert(db)

                // Spread backwards, so nothing is recent enough to be live and
                // the order under test is the ordinary one.
                let date = last.addingTimeInterval(-Double(index) * 60)
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

    /// Opens the page being made and chooses what stands on it, which is what
    /// every pass does.
    @discardableResult
    private func make(at moment: Date? = nil) async throws -> Edition {
        let moment = moment ?? now
        let edition = try #require(await editions.open(.standard, now: moment, calendar: calendar))
        try await editions.compose(edition, now: moment)
        return edition
    }

    @Test("An edition holds ten stories, and the rest is the wire")
    func tenAndNoMore() async throws {
        for index in 0..<14 {
            try await story("Actualité \(index)", endingHoursBeforeNoon: Double(index) + 1)
        }

        let edition = try await make()
        let held = try await rows(of: edition.id)

        #expect(held.count == EditionStore.mostStories)
        // The page's own order : the most recent first, since nothing here has
        // a subject the reader has spoken about and every story weighs the same.
        #expect(held.first?.title == "Actualité 0")
    }

    /// **Only stories the model has written about.** It is what makes `every
    /// edition is written` a rule rather than an aspiration : a story both
    /// voices declined would otherwise stand at the top of a page that could
    /// never be published, and one refusal would silence the front page for a
    /// day.
    @Test("A story the model would not write about does not reach the page")
    func onlyWhatTheModelWrote() async throws {
        try await story("Écrite", endingHoursBeforeNoon: 1)
        try await story("Refusée", endingHoursBeforeNoon: 0.5, written: false)

        let edition = try await make()

        #expect(try await rows(of: edition.id).map(\.title) == ["Écrite"])
    }

    /// A device with no model writes about no story, so it builds no edition at
    /// all. That is section 14's no-model path answered honestly rather than by
    /// putting a publisher's headline over a page and calling it written.
    @Test("With nothing written there is an edition holding nothing, and nothing to publish")
    func noModelNoPage() async throws {
        try await story("Une", endingHoursBeforeNoon: 1, written: false)
        try await story("Deux", endingHoursBeforeNoon: 2, written: false)

        let edition = try await make()

        #expect(try await rows(of: edition.id).isEmpty)
        #expect(edition.points.isEmpty)
        #expect(try await editions.current(now: now) == nil)
    }

    @Test("Opening twice at one boundary is one edition")
    func idempotent() async throws {
        try await story("Une", endingHoursBeforeNoon: 1)
        try await story("Deux", endingHoursBeforeNoon: 2)

        let first = try await make()
        let second = try await make()

        #expect(first.id == second.id)
        let count = try await database.writer.read { db in try Edition.fetchCount(db) }
        #expect(count == 1)
    }

    // MARK: - What a period holds

    /// The page is about a stretch of time that has ended, and a story older
    /// than it belongs to a paper the reader has already had.
    @Test("An edition holds what happened in its period and nothing older")
    func thePeriod() async throws {
        try await story("Ce matin", endingHoursBeforeNoon: 2)
        try await story("Aussi ce matin", endingHoursBeforeNoon: 3)

        // A page that came out at seven, so the midday period runs from seven.
        let morning = try await make(at: noon.addingTimeInterval(-5 * 3600 + 60))
        try await publish(morning.id)
        try await story("Avant-hier", endingHoursBeforeNoon: 30)

        let midday = try await make()
        #expect(midday.coversFrom == noon.addingTimeInterval(-5 * 3600))
        #expect(try await rows(of: midday.id).map(\.title) == ["Ce matin", "Aussi ce matin"])
    }

    /// **An article inside the period, and not a story whose last article is
    /// inside it.** A story that broke at ten and gained one more article at ten
    /// past noon is still the midday page's story.
    @Test("A story that broke in the period and moved after it is still on the page")
    func movedAfterwards() async throws {
        let id = try await story("En cours", endingHoursBeforeNoon: 1)
        let after = noon.addingTimeInterval(20 * 60)
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE story SET last_at = ? WHERE id = ?", arguments: [after, id])
        }

        let edition = try await make()
        #expect(try await rows(of: edition.id).map(\.title) == ["En cours"])
    }

    /// A page can never lead on something dated after its own dateline.
    @Test("A page holds nothing that arrived after its hour")
    func nothingAfterTheHour() async throws {
        try await story("Après", endingHoursBeforeNoon: -0.5)
        try await story("Avant", endingHoursBeforeNoon: 1)

        let edition = try await make()
        #expect(try await rows(of: edition.id).map(\.title) == ["Avant"])
    }

    /// A publisher that stamps this morning's item with last week's date is an
    /// ordinary publisher. The story's own key is minted where the grouping
    /// runs, so it reaches the page of the period it was grouped in.
    @Test("A story grouped in the period is on the page though its articles are dated last week")
    func backDated() async throws {
        try await story("Antidatée", endingHoursBeforeNoon: 60, groupedHoursBeforeNoon: 0.5)
        try await story("Ordinaire", endingHoursBeforeNoon: 1)

        let edition = try await make()
        #expect(try await rows(of: edition.id).map(\.title).contains("Antidatée"))
    }

    /// A quiet night is a short paper and never a blank one.
    @Test("A quiet period gives a short edition")
    func aShortPage() async throws {
        try await story("Une", endingHoursBeforeNoon: 1)
        try await story("Deux", endingHoursBeforeNoon: 2)

        let edition = try await make()
        #expect(try await rows(of: edition.id).count == EditionStore.leastStories)
    }

    /// One story under a dateline is a headline rather than an edition, and the
    /// paper before it stays on the table.
    @Test("Below two there is no edition, and nothing is stamped")
    func belowTheFloor() async throws {
        try await story("Seule", endingHoursBeforeNoon: 1)

        let edition = try await make()
        #expect(try await rows(of: edition.id).count == 1)

        let work = BriefEditionsJob.work(locale: .current, now: now)
        let waiting = try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM edition WHERE \(work.sql)", arguments: work.arguments)
        }
        #expect(waiting == 0)

        let row = try await database.writer.read { db in try Edition.fetchOne(db, key: edition.id) }
        #expect(row?.publishedAt == nil)
        #expect(row?.briefLocale == nil)
        #expect(row?.askedAt == nil)
    }

    // MARK: - Where a period begins

    /// A boundary the device slept through was closed and never published, so
    /// its news folds into the page that follows rather than falling between
    /// two of them.
    @Test("A period nobody published is folded into the next one")
    func foldedForward() async throws {
        try await story("Hier soir", endingHoursBeforeNoon: 14)
        try await story("Hier soir encore", endingHoursBeforeNoon: 15)

        // Seven o'clock, published, then the noon boundary with nothing in
        // between having come out.
        let morning = try await make(at: noon.addingTimeInterval(-5 * 3600 + 60))
        try await publish(morning.id)

        let midday = try await make()
        #expect(midday.coversFrom == morning.openedAt)
        #expect(try await rows(of: midday.id).isEmpty)
    }

    /// A slot the reader switched off never published, so the next period
    /// stretches back over it rather than leaving a hole.
    @Test("A slot switched off lengthens the next period")
    func aSlotSwitchedOff() async throws {
        var schedule = EditionSchedule.standard
        schedule.hours[.noon] = nil

        try await story("Ce matin", endingHoursBeforeNoon: 2)
        try await story("Aussi ce matin", endingHoursBeforeNoon: 3)

        let morning = try #require(
            await editions.open(schedule, now: noon.addingTimeInterval(-5 * 3600 + 60), calendar: calendar))
        try await publish(morning.id)

        let evening = try #require(
            await editions.open(schedule, now: noon.addingTimeInterval(6 * 3600 + 60), calendar: calendar))
        #expect(evening.slot == .evening)
        #expect(evening.coversFrom == morning.openedAt)
    }

    /// A store with nothing published takes the three days the stories are held
    /// to, which is the right first page for somebody who has just imported a
    /// thousand feeds.
    @Test("The first edition of a store covers the three days")
    func theFirstPage() async throws {
        try await story("Une", endingHoursBeforeNoon: 1)

        let edition = try await make()
        #expect(edition.coversFrom == edition.openedAt.addingTimeInterval(-DigestStore.window))
    }

    /// A slot moved backwards, a flight west and a schedule naming an hour
    /// already covered are one case, and minting a row for it would be a page
    /// with an inverted period that nothing can ever show.
    @Test("A boundary earlier than the last page that came out mints nothing")
    func neverBehindTheLastPage() async throws {
        try await story("Une", endingHoursBeforeNoon: 1)
        try await story("Deux", endingHoursBeforeNoon: 2)

        let midday = try await make()
        try await publish(midday.id)

        var moved = EditionSchedule.standard
        moved.hours[.noon] = 11 * 60
        #expect(try await editions.open(moved, now: now, calendar: calendar) == nil)

        let count = try await database.writer.read { db in try Edition.fetchCount(db) }
        #expect(count == 1)
    }

    // MARK: - What freezes, and when

    /// An edition stops being the current one when the next boundary passes,
    /// and it keeps the ten it had rather than being rewritten by the page as
    /// it stands afterwards.
    @Test("The next boundary closes the one before it, which keeps its ten")
    func closing() async throws {
        try await story("Ce matin", endingHoursBeforeNoon: 1)
        try await story("Aussi ce matin", endingHoursBeforeNoon: 2)

        let midday = try await make()
        try await publish(midday.id)
        let held = try await rows(of: midday.id).map(\.title)

        let later = now.addingTimeInterval(6 * 3600)
        try await story("Cet après-midi", endingHoursBeforeNoon: -5.5)
        let next = try await make(at: later)

        #expect(next.id != midday.id)
        #expect(try await rows(of: midday.id).map(\.title) == held)

        let closed = try await database.writer.read { db in try Edition.fetchOne(db, key: midday.id) }
        #expect(closed?.closedAt != nil)
    }

    /// **Composed again until it comes out, and never after.** Choosing again
    /// while a page is unpublished is what stops it being frozen from the first
    /// thirty seconds of a five-minute pass ; the freeze is at publication and
    /// it is total.
    @Test("The ten are chosen again until the page comes out, and never after")
    func composedUntilPublished() async throws {
        try await story("Une", endingHoursBeforeNoon: 3)
        try await story("Deux", endingHoursBeforeNoon: 4)

        let edition = try await make()
        try await story("Plus récente", endingHoursBeforeNoon: 1)
        try await editions.compose(edition, now: now)
        #expect(try await rows(of: edition.id).first?.title == "Plus récente")

        try await publish(edition.id)
        let published = try #require(
            await database.writer.read { db in try Edition.fetchOne(db, key: edition.id) })
        try await story("Plus récente encore", endingHoursBeforeNoon: 0.5)
        try await editions.compose(published, now: now)
        #expect(try await rows(of: edition.id).first?.title == "Plus récente")
    }

    /// The reading of a page and the writing of it are two transactions with a
    /// model call's worth of time between them, and a page published in that
    /// gap is a page frozen.
    @Test("A page published while it was being chosen is not rewritten")
    func composedAfterPublishing() async throws {
        try await story("Une", endingHoursBeforeNoon: 3)
        try await story("Deux", endingHoursBeforeNoon: 4)

        let edition = try await make()
        let held = try await rows(of: edition.id).map(\.title)

        // The value in hand still says unpublished, as the other lane's would.
        try await publish(edition.id)
        try await story("Plus récente", endingHoursBeforeNoon: 1)
        try await editions.compose(edition, now: now)

        #expect(try await rows(of: edition.id).map(\.title) == held)
    }

    /// The idle cost, asserted. A pass over a page nothing has changed writes
    /// nothing at all, on two tables the store watcher follows.
    @Test("A settled edition is read and never written")
    func idle() async throws {
        try await story("Une", endingHoursBeforeNoon: 1)
        try await story("Deux", endingHoursBeforeNoon: 2)

        let edition = try await make()
        let stamped = try #require(
            await database.writer.read { db in try Edition.fetchOne(db, key: edition.id)?.updatedAt })

        try await editions.compose(edition, now: now.addingTimeInterval(60))
        let again = try #require(
            await database.writer.read { db in try Edition.fetchOne(db, key: edition.id)?.updatedAt })

        #expect(again == stamped)
    }

    /// **The newest one that has come out, and not the newest one written.**
    @Test("A page still being written does not take the last one off the screen")
    func theLastOneStands() async throws {
        try await story("Ce matin", endingHoursBeforeNoon: 1)
        try await story("Aussi ce matin", endingHoursBeforeNoon: 2)

        let midday = try await make()
        try await publish(midday.id)

        let later = now.addingTimeInterval(6 * 3600)
        let next = try await make(at: later)
        #expect(next.publishedAt == nil)

        let current = try #require(await editions.current(now: later))
        #expect(current.edition.id == midday.id)
        #expect(current.edition.points.count == 2)
    }

    @Test("The archive holds what has come out and nothing else")
    func archiveIsPublishedOnly() async throws {
        try await story("Une", endingHoursBeforeNoon: 1)
        try await story("Deux", endingHoursBeforeNoon: 2)

        let edition = try await make()
        #expect(try await editions.archive(now: now).isEmpty)

        try await publish(edition.id)
        #expect(try await editions.archive(now: now).map(\.edition.id) == [edition.id])
    }

    /// An edition older than the window its stories are held to is a page of
    /// headlines whose articles have gone.
    @Test("The purge takes what has fallen out of the window")
    func purge() async throws {
        try await story("Une", endingHoursBeforeNoon: 1)
        try await story("Deux", endingHoursBeforeNoon: 2)

        let edition = try await make()
        try await publish(edition.id)

        // A newer page, so the one under test is no longer the paper on the
        // table and the purge may take it.
        let later = now.addingTimeInterval(6 * 3600)
        try await story("Ce soir", endingHoursBeforeNoon: -5)
        try await story("Ce soir encore", endingHoursBeforeNoon: -5.5)
        let evening = try await make(at: later)
        try await publish(evening.id, at: later)

        let muchLater = later.addingTimeInterval(EditionStore.archived + 24 * 3600)
        _ = try await editions.purge(now: muchLater)

        #expect(try await editions.archive(now: muchLater).map(\.edition.id) == [evening.id])
    }

    /// A quiet reader whose periods keep failing to fill two stories keeps one
    /// page for days, and the age would eventually take it and leave the front
    /// page blank.
    @Test("The purge never takes the page on the table")
    func purgeSparesTheCurrent() async throws {
        try await story("Une", endingHoursBeforeNoon: 1)
        try await story("Deux", endingHoursBeforeNoon: 2)

        let edition = try await make()
        try await publish(edition.id)

        let muchLater = now.addingTimeInterval(EditionStore.archived + 24 * 3600)
        _ = try await editions.purge(now: muchLater)

        #expect(try await editions.current(now: muchLater)?.edition.id == edition.id)
    }

    /// The model call sits between the choosing and the stamping, and a page
    /// published with a list describing rows it no longer holds would be final.
    @Test("A list is not written over a page that has moved under it")
    func composedOf() async throws {
        try await story("Une", endingHoursBeforeNoon: 3)
        try await story("Deux", endingHoursBeforeNoon: 4)

        let edition = try await make()
        let asked = try await rows(of: edition.id).map(\.storyID)

        try await story("Plus récente", endingHoursBeforeNoon: 1)
        try await editions.compose(edition, now: now)

        let written = try await editions.publish(
            edition.id,
            points: ["Une chose.", "Une autre."],
            topics: ["", ""],
            in: Locale(identifier: "fr_FR"),
            composedOf: asked
        )
        #expect(written == false)
        #expect(try await editions.current(now: now) == nil)
    }

    /// The row as the store holds it now.
    private func row(_ id: UUID) async throws -> Edition? {
        try await database.writer.read { db in try Edition.fetchOne(db, key: id) }
    }

    /// **A page the reader cancelled is a page nobody may write.** The work set
    /// is `closed_at IS NULL AND published_at IS NULL`, so a row left open by a
    /// slot that no longer exists is indistinguishable from the page being
    /// made : a model call was spent on it, it came out, and it announced
    /// itself under an hour the reader had just abolished.
    @Test("A slot the reader switches off takes the page in flight with it")
    func aCancelledSlotIsAbandoned() async throws {
        try await story("Une", endingHoursBeforeNoon: 3)
        try await story("Deux", endingHoursBeforeNoon: 4)
        let edition = try await make()
        #expect(edition.slot == .noon)

        var schedule = EditionSchedule.standard
        schedule.hours[.noon] = nil
        try await editions.open(schedule, now: now, calendar: calendar)

        let standing = try #require(await row(edition.id))
        #expect(standing.closedAt != nil)
        #expect(standing.publishedAt == nil)
    }

    /// With no boundary at all the old code returned before it closed anything,
    /// so the last page open went on being written and announced itself after
    /// the reader had switched every edition off.
    @Test("With every edition switched off, the page being made is abandoned")
    func everySlotOffAbandonsThePage() async throws {
        try await story("Une", endingHoursBeforeNoon: 3)
        try await story("Deux", endingHoursBeforeNoon: 4)
        let edition = try await make()

        #expect(try await editions.open(EditionSchedule(hours: [:]), now: now, calendar: calendar) == nil)

        let standing = try #require(await row(edition.id))
        #expect(standing.closedAt != nil)
        #expect(standing.publishedAt == nil)
    }

    /// The work set tests `closed_at IS NULL`, but it tests it before the model
    /// call. A boundary that goes to press inside that call would otherwise put
    /// two pages of one period in the archive.
    @Test("A page whose successor has gone to press is not published")
    func aClosedPageIsNotPublished() async throws {
        try await story("Une", endingHoursBeforeNoon: 3)
        try await story("Deux", endingHoursBeforeNoon: 4)
        let edition = try await make()
        let asked = try await rows(of: edition.id).map(\.storyID)

        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE edition SET closed_at = ? WHERE id = ?", arguments: [self.now, edition.id])
        }

        let written = try await editions.publish(
            edition.id,
            points: ["Une chose.", "Une autre."],
            topics: ["", ""],
            in: Locale(identifier: "fr_FR"),
            composedOf: asked
        )
        #expect(written == false)
        #expect(try await editions.current(now: now) == nil)
    }

    /// **What a second background grant is worth asking for.** A phone gets one
    /// wake per boundary, and one that lands inside the wait for a page's own
    /// stories finds nothing ready ; re-arming for the next boundary threw the
    /// hour away entirely.
    @Test("A page composed and still unwritten is what a second grant is for")
    func aPageInThePress() async throws {
        #expect(try await editions.inThePress(now: now) == nil)

        try await story("Une", endingHoursBeforeNoon: 3)
        try await story("Deux", endingHoursBeforeNoon: 4)
        let edition = try await make()
        #expect(try await editions.inThePress(now: now) == edition.openedAt)

        // Read and declined is a durable answer, so there is nothing to wake
        // for : the same question would get the same refusal.
        try await editions.stamp(edition.id, refusedIn: Locale(identifier: "fr_FR"), now: now)
        #expect(try await editions.inThePress(now: now) == nil)
    }

    private func publish(_ id: UUID, at moment: Date? = nil) async throws {
        try await database.writer.write { db in
            guard var edition = try Edition.fetchOne(db, key: id) else { return }
            edition.points = ["Deux ouvriers sauvés au Népal.", "Gaël Monfils quitte l'US Open."]
            edition.pointTopics = ["", ""]
            edition.briefLocale = Locale(identifier: "fr_FR").identifier
            edition.askedAt = moment ?? self.now
            edition.publishedAt = moment ?? self.now
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

    /// **Nothing invalidates a page, because a page is asked about once.** The
    /// rule was the story's rule said over a whole page : has the model been
    /// asked about *these articles*. It was right for a page that lived while
    /// its news was still arriving and wrong for a page about a period that has
    /// ended, where there is nothing underneath left to change.
    @Test("A page that has come out is never asked about again")
    func settled() async throws {
        let work = BriefEditionsJob.work(locale: Locale(identifier: "fr_FR"), now: now)

        #expect(work.sql.contains("published_at IS NULL"))
        #expect(work.sql.contains("closed_at IS NULL"))
        #expect(work.sql.contains("brief_locale"))
        #expect(work.sql.contains("asked_at"))
        // The key that re-opened the question is gone with the question.
        #expect(!work.sql.contains("brief_members"))
        #expect(!work.sql.contains("story_member"))
    }

    /// Without a model there is nothing to ask, so the queue is empty rather
    /// than permanently full : a job that offered the same page at every turn
    /// would stop everything behind it for ever.
    @Test("Without a model there is nothing waiting to be named")
    func nothingToDoWithoutAModel() async throws {
        guard !LocalProvider().isAvailable else { return }
        #expect(try await BriefEditionsJob(database, now: now).remaining() == 0)
    }
}

/// Whether a page's own period has been written, which decides when it goes to
/// press.
///
/// **The readiness test and the writer have to be asking one question.** They
/// were asking two. The writer is metered : a story it has already been asked
/// about inside this period is one it will not touch again, however many
/// articles have since joined it. The readiness test read the *unmetered*
/// predicate, so every one of those counted as a story the page was still
/// waiting on, the count could never reach nought, and no edition was ever
/// ready before its twenty minutes of grace had run out. Four times a day, the
/// paper came out twenty minutes after its own hour.
@Suite("Whether a page's own period has been written")
struct EditionReadinessTests {
    private let database: AppDatabase
    private let french = Locale(identifier: "fr_FR")

    /// The hour the page closes at, and a moment ten minutes past it : inside
    /// the grace, so readiness is really asked rather than short-circuited.
    private let boundary = Date(timeIntervalSince1970: 1_788_000_000)
    private var now: Date { boundary.addingTimeInterval(10 * 60) }
    private var opened: Date { boundary.addingTimeInterval(-8 * 3600) }

    init() throws {
        database = try AppDatabase.inMemory()
    }

    private func page() async throws -> Edition {
        let edition = Edition(slot: .morning, openedAt: boundary, coversFrom: opened, updatedAt: now)
        try await database.writer.write { [edition] db in try edition.insert(db) }
        return edition
    }

    /// A story inside the period, of two articles, and whatever the model has
    /// been told about it.
    ///
    /// `brief_members` is deliberately never written, which is what says the
    /// articles have moved since the model last saw them.
    private func story(askedAt: Date?) async throws {
        let middle = boundary.addingTimeInterval(-4 * 3600)
        var story = Story(
            id: .v7(at: middle), title: "Le tunnel", firstAt: middle, lastAt: middle, updatedAt: middle)
        story.isGenerated = askedAt != nil
        story.briefLocale = askedAt == nil ? nil : french.identifier
        story.briefAskedAt = askedAt

        try await database.writer.write { [story] db in
            try story.insert(db)
            var feed = Feed(url: URL(string: "https://readiness.example.com/f.xml")!, title: "Readiness")
            try feed.insert(db)
            for index in 0..<2 {
                let date = middle.addingTimeInterval(-Double(index) * 60)
                var entry = Entry(
                    feedID: feed.id, guid: "urn:readiness:\(index)", title: "Le tunnel",
                    publishedAt: date, receivedAt: date)
                entry.hasMedia = false
                try entry.insert(db)
                try StoryMember(storyID: story.id, entryID: entry.id, similarity: 1).insert(db)
            }
        }
    }

    private func isReady(_ edition: Edition) async throws -> Bool {
        try await database.writer.read { db in
            try BriefEditionsJob.isReady(edition, in: db, locale: self.french, now: self.now)
        }
    }

    @Test("A story already asked about inside the period does not hold the page")
    func aMeteredStoryDoesNotHold() async throws {
        let edition = try await page()
        try await story(askedAt: boundary.addingTimeInterval(-2 * 3600))

        #expect(try await isReady(edition))
    }

    @Test("A story nobody has asked about holds the page until the grace runs out")
    func anUnwrittenStoryHolds() async throws {
        let edition = try await page()
        try await story(askedAt: nil)

        #expect(try await isReady(edition) == false)
    }
}

/// The hours the reader is in the middle of choosing.
///
/// **A choice being made is not a choice the store knows about yet.** Moving a
/// wheel from seven to nine passes through a hundred and twenty minutes, and
/// each of them wrote the preference, pushed it to iCloud, grouped the whole
/// three-day window and read the page back. So the writing waits half a second
/// for the reader to stop. What that opens is a window in which the held value
/// and the stored one disagree, and ``AppModel/load()`` reads the stored one
/// back over the held one : it is the tail of every refresh, every pull and
/// every mark-all-read, so a pass landing inside the settle would undo the hour
/// the reader had just chosen, and the pending write would then make the undoing
/// permanent.
@Suite("A schedule the reader is still choosing", .serialized)
@MainActor
struct EditionScheduleSettleTests {
    private let model: AppModel

    init() throws {
        model = AppModel(
            database: try AppDatabase.inMemory(),
            preferences: Preferences(cloud: nil, local: UserDefaults(suiteName: "flong.settle.\(UUID())") ?? .standard)
        )
    }

    @Test("A refresh landing inside the settle does not undo the hour just chosen")
    func aChoiceSurvivesARefresh() async throws {
        var wanted = EditionSchedule.standard
        wanted.hours[.morning] = 6 * 60

        model.editionSchedule = wanted
        #expect(model.editionSchedule == wanted)

        // What every refresh ends with, while the preference still holds the
        // reader's previous hours.
        await model.load()

        #expect(model.editionSchedule == wanted)
    }
}

/// How the model's turn is shared between the three things it does in one.
///
/// **The page is what the turn is for, and it was the one thing that could get
/// none of it.** The headlines and the subjects took a slice each in turn until
/// the turn was over, and the naming was given whatever was left on the grounds
/// that one call for a whole page costs nothing to put last. What was left on a
/// morning was nothing : the night's stories all wanted a headline, every story
/// that had gained an article wanted its own written again, and the naming was
/// reached with its deadline already behind it. No call was made, no page came
/// out, and the reader had last night's paper at ten.
@Suite("How the model's turn is shared")
struct EnrichmentTurnTests {
    private let start = Date(timeIntervalSince1970: 1_788_000_000)
    private var end: Date { start.addingTimeInterval(DigestService.enrichmentTurn) }

    @Test("The writing and the filing stop a slice short of the end")
    func writingLeavesTheLastSlice() {
        #expect(
            DigestService.writingEnds(by: end)
                == end.addingTimeInterval(-DigestService.enrichmentSlice))
        #expect(DigestService.writingEnds(by: end) > start)
    }

    @Test("The naming works to the end of the turn when the writing stopped in time")
    func namingTakesWhatWasReserved() {
        let stopped = DigestService.writingEnds(by: end)
        #expect(DigestService.namingEnds(by: end, at: stopped) == end)
        #expect(DigestService.namingEnds(by: end, at: stopped) > stopped)
    }

    /// A deadline is read before a call and not during one, so a headline begun
    /// a moment before the writing was due to stop runs on past it. Without a
    /// floor that one call carries the whole reservation away and the page is
    /// asked about on no pass at all.
    @Test("A page is still asked about when the writing overran the whole turn")
    func namingHasAFloor() {
        let overran = end.addingTimeInterval(5)
        #expect(DigestService.namingEnds(by: end, at: overran) > overran)
        #expect(
            DigestService.namingEnds(by: end, at: overran)
                == overran.addingTimeInterval(DigestService.enrichmentSlice))
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
    /// same rule gave a French reader less to be told than an English one. Long
    /// words that fit pass where a hundred characters did not, and a run of
    /// short ones fails where a hundred characters did.
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

    /// **A standing condition is not news.** `La Russie et l'Ukraine sont en
    /// guerre` was true yesterday and will be true tomorrow, and a front page
    /// that spends one of its three lines on it has told the reader nothing
    /// about today. The rule lives in both voices, so both are held to it.
    @Test("Both voices refuse a point that only says a situation exists")
    func bothVoicesRefuseAStandingFact() {
        for voice in [EditionSummarizer.instructions, EditionSummarizer.condensing] {
            #expect(voice.contains("Russia and Ukraine are at war"))
        }
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
        guard LocalProvider.writes(french) else { return }
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
    private func edition(points: [String], openedAt: Date = Date(timeIntervalSince1970: 1_788_000_000))
        -> Edition
    {
        Edition(slot: .morning, openedAt: openedAt, points: points, publishedAt: Date())
    }

    /// **The one notice whose words are already written.** Everything else is a
    /// sentence assembled from names ; this arrives carrying a headline and a
    /// line the model wrote over the whole page, and writing anything of our
    /// own on top would be a third opinion about a page that already has one.
    @Test("The notice names the edition and says its own points")
    func wording() throws {
        let announcement = try #require(
            Announcement.newEdition(
                edition(points: ["L'Assemblée a rejeté le texte.", "La CGT reconduit la grève."])
            )
        )

        // The edition names itself in the one bold line a banner gives a title,
        // which is where the dateline stands on the page for the same reason.
        #expect(announcement.title == String(localized: EditionSlot.morning.title))
        // A middle dot rather than commas, as the headlines are joined
        // everywhere else here : a point may hold commas of its own.
        #expect(announcement.body == "L'Assemblée a rejeté le texte. · La CGT reconduit la grève.")
        // A tap opens the digest, where the edition is. There is no deeper
        // place to go : the edition is the front page.
        #expect(announcement.story == nil)
        #expect(announcement.article == nil)
    }

    @Test("A page the model has not written says nothing at all")
    func nothingToSay() {
        #expect(Announcement.newEdition(edition(points: [])) == nil)
    }

    /// **Only a named notice can be replaced.** Everything but an article took
    /// a fresh identifier every time, so two passes that both noticed one page
    /// had come out stacked two banners for one paper.
    @Test("An edition's notice is known by its hour, so it can be replaced")
    func known() throws {
        let announcement = try #require(Announcement.newEdition(edition(points: ["Une chose."])))
        #expect(Notifier.identifier(of: announcement) == announcement.name)
        #expect(
            Edition.notice(for: Date(timeIntervalSince1970: 1_788_000_000))
                != Edition.notice(for: Date(timeIntervalSince1970: 1_788_003_600)))
    }

    /// A banner and a sound over the page they are about is telling somebody
    /// something they are looking at. Filed rather than dropped, since Flong
    /// being open is not the same as the front page being read.
    @Test("An edition arriving while the reader is in Flong is filed and not sounded")
    func heldBackWhileReading() {
        #expect(
            NotificationRouter.presentation(thread: Announcement.Thread.newEdition, isReading: true) == [.list])
        #expect(
            NotificationRouter.presentation(thread: Announcement.Thread.newEdition, isReading: false)
                == [.banner, .list, .sound])
        // And only the edition : the others reach a foreground window because
        // they were posted a moment before it opened, and they are worth
        // showing.
        #expect(
            NotificationRouter.presentation(thread: Announcement.Thread.newStories, isReading: true)
                == [.banner, .list, .sound])
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

        try await database.writer.write { [entry, feed] db in
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
