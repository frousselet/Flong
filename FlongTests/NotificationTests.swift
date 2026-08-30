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
    @Test("A pass that found no new subject says nothing")
    func silence() {
        // The ordinary case, by far : most passes file every story under a
        // subject the reader already has.
        #expect(Announcement.newSubjects([]) == nil)
    }

    @Test("One subject is named, and a tap opens it")
    func one() throws {
        let announcement = try #require(Announcement.newSubjects(["Typographie"]))

        #expect(announcement.title == String(localized: "New subject"))
        #expect(announcement.body == "Typographie")
        // One subject is a place to go.
        #expect(announcement.subject == "Typographie")
    }

    @Test("Several are counted in the title and listed in the body")
    func several() throws {
        let names = ["Typographie", "Cybersécurité", "Élections"]
        let announcement = try #require(Announcement.newSubjects(names))

        #expect(announcement.title.contains("3"))
        for name in names {
            #expect(announcement.body.contains(name))
        }
        // A tap that had to choose one of three would choose wrongly twice out
        // of three times, so it chooses none.
        #expect(announcement.subject == nil)
    }

    @Test("The count in the title is the number of names in the body")
    func theCountIsHonest() throws {
        // A body showing the first few of a longer list is a small lie, and a
        // title counting more than the body shows is the same lie twice.
        let names = (1...12).map { "Sujet \($0)" }
        let announcement = try #require(Announcement.newSubjects(names))

        #expect(announcement.title.contains("12"))
        #expect(names.allSatisfy { announcement.body.contains($0) })
    }

    @Test("Notifications of one kind are grouped under one thread")
    func grouped() throws {
        let first = try #require(Announcement.newSubjects(["Typographie"]))
        let second = try #require(Announcement.newSubjects(["Élections"]))

        // A week of these is one stack in Notification Centre, not a week of
        // rows.
        #expect(first.thread == second.thread)
        #expect(first.thread == Announcement.Thread.newSubjects)
    }
}

@Suite("Which subjects are worth telling the reader about")
struct NewSubjectTests {
    private let database: AppDatabase
    private let topics: TopicPreferences
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() throws {
        database = try AppDatabase.inMemory()
        topics = TopicPreferences(database)
    }

    @Test("Only what the model wrote after the moment asked about")
    func since() async throws {
        try await topics.record("Ancien", at: now.addingTimeInterval(-3600))
        try await topics.record("Nouveau", at: now.addingTimeInterval(3600))

        #expect(try await topics.made(since: now) == ["Nouveau"])
    }

    @Test("A subject the reader wrote is not news to the reader")
    func theirOwn() async throws {
        try await topics.add("Le mien", at: now.addingTimeInterval(3600))
        try await topics.record("Le sien", at: now.addingTimeInterval(3600))

        // Telling somebody about a word they typed themselves is the
        // application repeating them back at them.
        #expect(try await topics.made(since: now) == ["Le sien"])
    }

    @Test("A second spelling of a subject that exists is not a new subject")
    func folded() async throws {
        try await topics.record("Cybersécurité", at: now.addingTimeInterval(-3600))
        try await topics.record("cybersecurite", at: now.addingTimeInterval(3600))

        // The vocabulary folds it, so nothing was written, so there is nothing
        // to announce : the reader would have been told about a subject they
        // already had.
        #expect(try await topics.made(since: now).isEmpty)
    }

    @Test("They arrive in the order they were found")
    func ordered() async throws {
        for (index, name) in ["Premier", "Deuxième", "Troisième"].enumerated() {
            try await topics.record(name, at: now.addingTimeInterval(Double(index + 1) * 60))
        }

        #expect(try await topics.made(since: now) == ["Premier", "Deuxième", "Troisième"])
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
        #expect(preferences().wantsNewSubjectNotices == false)
        #expect(preferences().subjectsAnnouncedAt == nil)
    }

    @Test("The answer is remembered")
    func remembered() {
        let store = preferences()

        store.wantsNewSubjectNotices = true
        #expect(store.wantsNewSubjectNotices)

        store.wantsNewSubjectNotices = false
        #expect(!store.wantsNewSubjectNotices)
    }

    @Test("A device that has said nothing does not overrule one that has")
    func iCloudSilenceIsNotAnAnswer() {
        let defaults = UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        defaults.set(true, forKey: "notify.new-subjects")

        // `bool(forKey:)` answers false for a key nobody ever wrote, so reading
        // the iCloud store directly would have an empty one turn the notices
        // off on a device that had turned them on.
        let cloud = NSUbiquitousKeyValueStore()
        cloud.removeObject(forKey: "notify.new-subjects")
        #expect(Preferences(cloud: cloud, local: defaults).wantsNewSubjectNotices)
    }

    @Test("The watermark is this device's own")
    func watermark() {
        let store = preferences()
        let moment = Date(timeIntervalSince1970: 1_787_646_600)

        store.subjectsAnnouncedAt = moment
        #expect(store.subjectsAnnouncedAt == moment)

        store.subjectsAnnouncedAt = nil
        #expect(store.subjectsAnnouncedAt == nil)
    }
}

/// When the reader is actually told, and when they are deliberately not.
@Suite("Telling the reader about a new subject", .serialized)
@MainActor
struct AnnouncingTests {
    private let database: AppDatabase
    private let topics: TopicPreferences
    private let preferences: Preferences
    private let announcer = MemoryAnnouncer()
    private let model: AppModel
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() throws {
        database = try AppDatabase.inMemory()
        topics = TopicPreferences(database)
        preferences = Preferences(
            cloud: nil,
            local: UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        )
        model = AppModel(database: database, preferences: preferences, announcer: announcer)
    }

    /// The reader has turned the notices on, and the clock started then.
    private func wanted(from moment: Date) async {
        await model.setWantsNewSubjectNotices(true)
        preferences.subjectsAnnouncedAt = moment
    }

    @Test("A subject found while the reader was away is announced")
    func announced() async throws {
        await wanted(from: now)
        model.isReading = false
        try await topics.record("Typographie", at: now.addingTimeInterval(60))

        await model.announceNewSubjects()

        #expect(announcer.posted.count == 1)
        #expect(announcer.posted.first?.body == "Typographie")
        #expect(announcer.posted.first?.subject == "Typographie")
    }

    @Test("Nothing is said twice")
    func onlyOnce() async throws {
        await wanted(from: now)
        model.isReading = false
        try await topics.record("Typographie", at: now.addingTimeInterval(60))

        await model.announceNewSubjects()
        await model.announceNewSubjects()

        // The watermark moved past it, so the second pass has nothing to say.
        #expect(announcer.posted.count == 1)
    }

    @Test("Nothing interrupts a reader looking at the page it would be about")
    func silentWhileReading() async throws {
        await wanted(from: now)
        model.isReading = true
        try await topics.record("Typographie", at: now.addingTimeInterval(60))

        await model.announceNewSubjects()
        #expect(announcer.posted.isEmpty)

        // And it is not saved up for later : the subject appeared as a pill on
        // the page they had open, so they know about it, and being told
        // tomorrow about what they saw today is worse than not being told.
        model.isReading = false
        await model.announceNewSubjects()
        #expect(announcer.posted.isEmpty)
    }

    @Test("A reader who asked for nothing hears nothing, and the clock does not run")
    func silentUntilAskedFor() async throws {
        model.isReading = false
        try await topics.record("Typographie", at: now.addingTimeInterval(60))

        await model.announceNewSubjects()

        #expect(announcer.posted.isEmpty)
        // Untouched, so that turning the notices on later starts from that
        // moment rather than from whatever a silent pass had stamped.
        #expect(preferences.subjectsAnnouncedAt == nil)
    }

    @Test("Turning the notices on starts the clock, so what already exists is not news")
    func startsFromNow() async throws {
        try await topics.record("Ancien", at: now.addingTimeInterval(-86400))

        await model.setWantsNewSubjectNotices(true)
        model.isReading = false
        await model.announceNewSubjects()

        #expect(model.wantsNewSubjectNotices)
        #expect(announcer.posted.isEmpty)
    }

    @Test("A refusal leaves the switch where it was")
    func refused() async throws {
        announcer.granted = false

        await model.setWantsNewSubjectNotices(true)

        // The system said no, and no switch in an application may say
        // otherwise.
        #expect(!model.wantsNewSubjectNotices)
        #expect(model.notificationStatus == .denied)
        #expect(preferences.subjectsAnnouncedAt == nil)
    }

    @Test("Turning them off stops them without asking anything")
    func turnedOff() async throws {
        await wanted(from: now)
        await model.setWantsNewSubjectNotices(false)

        model.isReading = false
        try await topics.record("Typographie", at: now.addingTimeInterval(60))
        await model.announceNewSubjects()

        #expect(!model.wantsNewSubjectNotices)
        #expect(announcer.posted.isEmpty)
    }
}
