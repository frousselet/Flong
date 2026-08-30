//
//  NotificationTests.swift
//  FlongTests
//
//  Created by François Rousselet on 30/08/2026.
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

/// What a notification says, and when there is one at all.
///
/// The delivery is the system's and is not exercised : an authorization, a
/// bundle and a device are none of them things a test can rely on. What is
/// testable, and what actually reads badly when it is wrong, is the wording,
/// the plural, the list that has to work with one name as well as with five,
/// and where a tap lands.
@Suite("What Flong tells the reader")
struct AnnouncementTests {
    private func opened(_ title: String, summary: String? = nil, rooms: [String] = ["lemonde.fr"])
        -> DigestStore
        .Opened
    {
        DigestStore.Opened(id: .v7(), title: title, summary: summary, rooms: rooms)
    }

    @Test("A pass that opened no story says nothing")
    func silence() {
        // The ordinary case, by far : most passes have articles join a story
        // that already exists, and a cluster of one is not a story at all.
        #expect(Announcement.newStories([]) == nil)
    }

    @Test("One story leads with its own headline, and a tap opens it")
    func one() throws {
        let story = opened("Une réforme du calendrier scolaire", rooms: ["lemonde.fr", "liberation.fr"])
        let announcement = try #require(Announcement.newStories([story]))

        // The headline is the news. A notification titled `New story` with the
        // headline underneath buries the thing the reader is being told.
        #expect(announcement.title == "Une réforme du calendrier scolaire")
        #expect(announcement.body.contains("lemonde.fr"))
        #expect(announcement.body.contains("liberation.fr"))
        #expect(announcement.story == story.id)
    }

    @Test("A written line says more than a list of newsrooms, and takes its place")
    func summaryWins() throws {
        let story = opened("Une réforme", summary: "Le ministère décale la rentrée à la mi-août.")
        let announcement = try #require(Announcement.newStories([story]))

        #expect(announcement.body == "Le ministère décale la rentrée à la mi-août.")
    }

    @Test("A story with no written line falls back on who is covering it")
    func roomsOtherwise() throws {
        let announcement = try #require(Announcement.newStories([opened("Une réforme", summary: "")]))
        #expect(announcement.body == "lemonde.fr")
    }

    @Test("Several are counted in the title and listed in the body")
    func several() throws {
        let stories = [opened("Une réforme"), opened("Les macros Swift"), opened("Le procès")]
        let announcement = try #require(Announcement.newStories(stories))

        #expect(announcement.title.contains("3"))
        for story in stories {
            #expect(announcement.body.contains(story.title))
        }
        // A tap that had to choose one of three would choose wrongly twice out
        // of three times, so it chooses none.
        #expect(announcement.story == nil)
    }

    @Test("Headlines are not run together as one sentence")
    func headlinesAreSeparated() throws {
        let announcement = try #require(
            Announcement.newStories([opened("Réforme, acte II"), opened("Procès, la suite")])
        )

        // A headline may hold commas of its own, so a comma list of them reads
        // as one long broken sentence.
        #expect(announcement.body == "Réforme, acte II · Procès, la suite")
    }

    @Test("The count in the title is the number of headlines in the body")
    func theCountIsHonest() throws {
        let stories = (1...12).map { opened("Fil \($0)") }
        let announcement = try #require(Announcement.newStories(stories))

        #expect(announcement.title.contains("12"))
        #expect(stories.allSatisfy { announcement.body.contains($0.title) })
    }

    @Test("Notifications of one kind are grouped under one thread")
    func grouped() throws {
        let first = try #require(Announcement.newStories([opened("Une réforme")]))
        let second = try #require(Announcement.newStories([opened("Un procès")]))

        // A week of these is one stack in Notification Centre, not a week of
        // rows.
        #expect(first.thread == second.thread)
        #expect(first.thread == Announcement.Thread.newStories)
    }
}

@Suite("Which stories are worth telling the reader about")
struct OpenedStoryTests {
    private let database: AppDatabase
    private let digest: DigestStore
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() throws {
        database = try AppDatabase.inMemory()
        digest = DigestStore(database)
    }

    @discardableResult
    private func story(_ title: String, at moment: Date, rooms: [String] = ["a.example.com"]) async throws -> UUID {
        let story = Story(id: .v7(at: moment), title: title, firstAt: moment, lastAt: moment, updatedAt: moment)
        try await database.writer.write { db in
            try story.insert(db)

            for (index, room) in rooms.enumerated() {
                var feed = Feed(url: URL(string: "https://\(room)/\(title).xml")!, title: room)
                feed.siteURL = URL(string: "https://\(room)")
                try feed.insert(db)

                var entry = Entry(
                    feedID: feed.id,
                    guid: "urn:\(title):\(index)",
                    title: title,
                    publishedAt: moment,
                    receivedAt: moment
                )
                entry.hasMedia = false
                try entry.insert(db)
                try StoryMember(storyID: story.id, entryID: entry.id, similarity: 1).insert(db)
            }
        }
        return story.id
    }

    @Test("Only the stories opened after the moment asked about")
    func since() async throws {
        try await story("Ancien", at: now.addingTimeInterval(-3600))
        try await story("Nouveau", at: now.addingTimeInterval(3600))

        // The identifier carries the moment the story was opened. `first_at`
        // is the date of its earliest article and may be days older.
        #expect(try await digest.opened(since: now).map(\.title) == ["Nouveau"])
    }

    @Test("They arrive in the order they opened")
    func ordered() async throws {
        for (index, title) in ["Premier", "Deuxième", "Troisième"].enumerated() {
            try await story(title, at: now.addingTimeInterval(Double(index + 1) * 60))
        }

        #expect(try await digest.opened(since: now).map(\.title) == ["Premier", "Deuxième", "Troisième"])
    }

    @Test("A story says which newsrooms are covering it, once each")
    func rooms() async throws {
        try await story("Une réforme", at: now.addingTimeInterval(60), rooms: ["lemonde.fr", "liberation.fr"])

        let opened = try #require(await digest.opened(since: now).first)
        // A set, not a list : the rooms come back in the order they picked the
        // story up, and this fixture gives both articles the same moment, so
        // asserting an order would be asserting whatever the database happened
        // to return.
        #expect(Set(opened.rooms) == ["lemonde.fr", "liberation.fr"])
        #expect(opened.rooms.count == 2)
    }
}

@Suite("What the reader asked to be told")
struct NoticePreferenceTests {
    private func preferences() -> Preferences {
        Preferences(cloud: nil, local: UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!)
    }

    @Test("Nothing is announced until the reader asks for it")
    func offByDefault() {
        // A switch that starts on is a prompt at first launch about something
        // the reader has not seen yet, which is how an application gets refused
        // permanently.
        #expect(preferences().wantsNewStoryNotices == false)
        #expect(preferences().storiesAnnouncedAt == nil)
    }

    @Test("The answer is remembered")
    func remembered() {
        let store = preferences()

        store.wantsNewStoryNotices = true
        #expect(store.wantsNewStoryNotices)

        store.wantsNewStoryNotices = false
        #expect(!store.wantsNewStoryNotices)
    }

    @Test("A device that has said nothing does not overrule one that has")
    func iCloudSilenceIsNotAnAnswer() {
        let defaults = UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        defaults.set(true, forKey: "notify.new-stories")

        // `bool(forKey:)` answers false for a key nobody ever wrote, so reading
        // the iCloud store directly would have an empty one turn the notices
        // off on a device that had turned them on.
        let cloud = NSUbiquitousKeyValueStore()
        cloud.removeObject(forKey: "notify.new-stories")
        #expect(Preferences(cloud: cloud, local: defaults).wantsNewStoryNotices)
    }

    @Test("The watermark is this device's own")
    func watermark() {
        let store = preferences()
        let moment = Date(timeIntervalSince1970: 1_787_646_600)

        store.storiesAnnouncedAt = moment
        #expect(store.storiesAnnouncedAt == moment)

        store.storiesAnnouncedAt = nil
        #expect(store.storiesAnnouncedAt == nil)
    }
}

/// When the reader is actually told, and when they are deliberately not.
@Suite("Telling the reader about a new story", .serialized)
@MainActor
struct AnnouncingTests {
    private let database: AppDatabase
    private let preferences: Preferences
    private let announcer = MemoryAnnouncer()
    private let model: AppModel
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() throws {
        database = try AppDatabase.inMemory()
        preferences = Preferences(
            cloud: nil,
            local: UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        )
        model = AppModel(database: database, preferences: preferences, announcer: announcer)
    }

    private func story(_ title: String, at moment: Date) async throws {
        let story = Story(id: .v7(at: moment), title: title, firstAt: moment, lastAt: moment, updatedAt: moment)
        try await database.writer.write { db in
            try story.insert(db)

            var feed = Feed(url: URL(string: "https://a.example.com/\(title).xml")!, title: "A")
            feed.siteURL = URL(string: "https://a.example.com")
            try feed.insert(db)

            var entry = Entry(feedID: feed.id, guid: "urn:\(title)", title: title, publishedAt: moment)
            entry.hasMedia = false
            try entry.insert(db)
            try StoryMember(storyID: story.id, entryID: entry.id, similarity: 1).insert(db)
        }
    }

    /// The reader has turned the notices on, and the clock started then.
    private func wanted(from moment: Date) async {
        await model.setWantsNewStoryNotices(true)
        preferences.storiesAnnouncedAt = moment
    }

    @Test("A story opened while the reader was away is announced")
    func announced() async throws {
        await wanted(from: now)
        model.isReading = false
        try await story("Une réforme", at: now.addingTimeInterval(60))

        await model.announceNewStories()

        #expect(announcer.posted.count == 1)
        #expect(announcer.posted.first?.title == "Une réforme")
        #expect(announcer.posted.first?.story != nil)
    }

    @Test("Nothing is said twice")
    func onlyOnce() async throws {
        await wanted(from: now)
        model.isReading = false
        try await story("Une réforme", at: now.addingTimeInterval(60))

        await model.announceNewStories()
        await model.announceNewStories()

        // The watermark moved past it, so the second pass has nothing to say.
        #expect(announcer.posted.count == 1)
    }

    @Test("Nothing interrupts a reader looking at the page it would be about")
    func silentWhileReading() async throws {
        await wanted(from: now)
        model.isReading = true
        try await story("Une réforme", at: now.addingTimeInterval(60))

        await model.announceNewStories()
        #expect(announcer.posted.isEmpty)

        // And it is not saved up for later : the story appeared on the page
        // they had open, so they know about it, and being told tomorrow about
        // what they saw today is worse than not being told.
        model.isReading = false
        await model.announceNewStories()
        #expect(announcer.posted.isEmpty)
    }

    @Test("A reader who asked for nothing hears nothing, and the clock does not run")
    func silentUntilAskedFor() async throws {
        model.isReading = false
        try await story("Une réforme", at: now.addingTimeInterval(60))

        await model.announceNewStories()

        #expect(announcer.posted.isEmpty)
        // Untouched, so that turning the notices on later starts from that
        // moment rather than from whatever a silent pass had stamped.
        #expect(preferences.storiesAnnouncedAt == nil)
    }

    @Test("Turning the notices on starts the clock, so what is already open is not news")
    func startsFromNow() async throws {
        try await story("Ancien", at: now.addingTimeInterval(-86400))

        await model.setWantsNewStoryNotices(true)
        model.isReading = false
        await model.announceNewStories()

        #expect(model.wantsNewStoryNotices)
        #expect(announcer.posted.isEmpty)
    }

    @Test("A refusal leaves the switch where it was")
    func refused() async throws {
        announcer.granted = false

        await model.setWantsNewStoryNotices(true)

        // The system said no, and no switch in an application may say
        // otherwise.
        #expect(!model.wantsNewStoryNotices)
        #expect(model.notificationStatus == .denied)
        #expect(preferences.storiesAnnouncedAt == nil)
    }

    @Test("Turning them off stops them without asking anything")
    func turnedOff() async throws {
        await wanted(from: now)
        await model.setWantsNewStoryNotices(false)

        model.isReading = false
        try await story("Une réforme", at: now.addingTimeInterval(60))
        await model.announceNewStories()

        #expect(!model.wantsNewStoryNotices)
        #expect(announcer.posted.isEmpty)
    }
}
