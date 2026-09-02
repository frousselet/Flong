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

    /// A story as the page would have one : two rooms, inside the window.
    ///
    /// One article is not a story and the front page does not show one, so
    /// neither does a notification about the front page.
    /// - Parameters:
    ///   - moment: when its articles were published, which is what the page
    ///     holds a story to.
    ///   - opened: when the story itself was made, which the identifier carries
    ///     and which the announcement asks about. They differ whenever a pass
    ///     groups a backlog : the story is minutes old and its articles are
    ///     days old.
    @discardableResult
    private func story(
        _ title: String,
        at moment: Date,
        opened: Date? = nil,
        rooms: [String] = ["a.example.com", "b.example.com"]
    ) async throws -> UUID {
        let story = Story(
            id: .v7(at: opened ?? moment),
            title: title,
            firstAt: moment,
            lastAt: moment,
            updatedAt: moment
        )
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
        #expect(try await digest.opened(since: now, now: now).map(\.title) == ["Nouveau"])
    }

    @Test("They arrive in the order they opened")
    func ordered() async throws {
        for (index, title) in ["Premier", "Deuxième", "Troisième"].enumerated() {
            try await story(title, at: now.addingTimeInterval(Double(index + 1) * 60))
        }

        #expect(try await digest.opened(since: now, now: now).map(\.title) == ["Premier", "Deuxième", "Troisième"])
    }

    @Test("A story the front page will not show is not announced either")
    func onlyWhatThePageShows() async throws {
        // A quiet feed's backlog, fetched by a full pass and grouped into a
        // story dated last week. The story is new, and the page looks back
        // three days, so the reader would be told about news they then could
        // not find anywhere : a notification about a page that had, as far as
        // they could see, not changed at all.
        try await story(
            "Vieilles nouvelles",
            at: now.addingTimeInterval(-8 * 24 * 3600),
            opened: now.addingTimeInterval(30)
        )
        try await story("Ce matin", at: now.addingTimeInterval(60))

        #expect(try await digest.opened(since: now, now: now).map(\.title) == ["Ce matin"])
    }

    @Test("A single article is not a story, and is not announced")
    func oneArticleIsNotAStory() async throws {
        try await story("Seul", at: now.addingTimeInterval(60), rooms: ["a.example.com"])

        // The page shows nothing a single article stands behind, so neither
        // does a notification about the page.
        #expect(try await digest.opened(since: now, now: now).isEmpty)
    }

    @Test("A story says which newsrooms are covering it, once each")
    func rooms() async throws {
        try await story("Une réforme", at: now.addingTimeInterval(60), rooms: ["lemonde.fr", "liberation.fr"])

        let opened = try #require(await digest.opened(since: now, now: now).first)
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
    /// Two minutes ago, and not a fixed date in the past.
    ///
    /// What is announced is what the front page is showing, and the page looks
    /// back three days : a fixture dated last week describes a story the reader
    /// could not find if they went looking for it.
    ///
    /// Two minutes rather than none, because the stories are dated a minute
    /// after this and the watermark the announcement leaves behind is the
    /// moment it ran : a story dated in the future would sit above every
    /// watermark and be announced again on every pass.
    private let now = Date().addingTimeInterval(-120)

    init() throws {
        database = try AppDatabase.inMemory()
        preferences = Preferences(
            cloud: nil,
            local: UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        )
        model = AppModel(database: database, preferences: preferences, announcer: announcer)
    }

    /// Two rooms, which is the smallest thing the front page calls a story.
    private func story(_ title: String, at moment: Date) async throws {
        let story = Story(id: .v7(at: moment), title: title, firstAt: moment, lastAt: moment, updatedAt: moment)
        try await database.writer.write { db in
            try story.insert(db)

            for room in ["a.example.com", "b.example.com"] {
                var feed = Feed(url: URL(string: "https://\(room)/\(title).xml")!, title: room)
                feed.siteURL = URL(string: "https://\(room)")
                try feed.insert(db)

                var entry = Entry(feedID: feed.id, guid: "urn:\(title):\(room)", title: title, publishedAt: moment)
                entry.hasMedia = false
                try entry.insert(db)
                try StoryMember(storyID: story.id, entryID: entry.id, similarity: 1).insert(db)
            }
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

/// What a notice about one source's own articles says.
///
/// The stories are a calculation and this is the opposite question, asked
/// source by source : the wording has to work for one article, for four from
/// one place, and for four from four.
@Suite("What Flong says about a source's own articles")
struct SourceAnnouncementTests {
    private func arrival(_ title: String, from source: String = "Le Monde") -> ArticleStore.Arrival {
        ArticleStore.Arrival(id: .v7(), title: title, source: source)
    }

    @Test("A pass that brought nothing from those sources says nothing")
    func silence() {
        // The ordinary case : almost every pass brings articles from sources
        // the reader asked nothing about.
        #expect(Announcement.newArticles([]) == nil)
    }

    @Test("One article leads with its own headline, and a tap opens it")
    func one() throws {
        let article = arrival("Une réforme du calendrier scolaire")
        let announcement = try #require(Announcement.newArticles([article]))

        #expect(announcement.title == "Une réforme du calendrier scolaire")
        #expect(announcement.body == "Le Monde")
        #expect(announcement.article == article.id)
        // An article is read over everything, and a story is a page in the
        // digest : a tap has one place to land and this is not the other one.
        #expect(announcement.story == nil)
    }

    @Test("Several from one source are counted under its name")
    func severalFromOne() throws {
        let articles = [arrival("Une réforme"), arrival("Les macros Swift"), arrival("Le procès")]
        let announcement = try #require(Announcement.newArticles(articles))

        #expect(announcement.title.contains("Le Monde"))
        #expect(announcement.title.contains("3"))
        for article in articles {
            #expect(announcement.body.contains(article.title))
        }
        // Three articles are not a place to go.
        #expect(announcement.article == nil)
    }

    @Test("Headlines are not run together as one sentence")
    func headlinesAreSeparated() throws {
        let announcement = try #require(
            Announcement.newArticles([arrival("Réforme, acte II"), arrival("Procès, la suite")])
        )

        #expect(announcement.body == "Réforme, acte II · Procès, la suite")
    }

    @Test("Several sources are counted and then named")
    func severalSources() throws {
        let articles = [
            arrival("Une réforme", from: "Le Monde"),
            arrival("Les macros Swift", from: "Swift by Sundell"),
            arrival("Le procès", from: "Le Monde"),
        ]
        let announcement = try #require(Announcement.newArticles(articles))

        #expect(announcement.title.contains("3"))
        // A reader told `3 new articles` and left to work out where from would
        // have to open the application to learn what they were just told. Each
        // source is named once, whatever it served.
        #expect(announcement.body.contains("Le Monde"))
        #expect(announcement.body.contains("Swift by Sundell"))
        #expect(!announcement.body.contains("Une réforme"))
    }

    @Test("These notices are grouped under a thread of their own")
    func grouped() throws {
        let first = try #require(Announcement.newArticles([arrival("Une réforme")]))
        let second = try #require(Announcement.newArticles([arrival("Un procès")]))

        #expect(first.thread == second.thread)
        #expect(first.thread == Announcement.Thread.newArticles)
        // Not the stack the stories are in : one is a calculation about the
        // press and the other is one source publishing.
        #expect(first.thread != Announcement.Thread.newStories)
    }
}

/// Which articles are worth telling the reader about, and which are not.
@Suite("What a source the reader asked about has just published")
struct ArrivedArticleTests {
    private let database: AppDatabase
    private let articles: ArticleStore
    private let subscriptions: SubscriptionStore
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() throws {
        database = try AppDatabase.inMemory()
        articles = ArticleStore(database)
        subscriptions = SubscriptionStore(database)
    }

    /// A source, asked about or not.
    ///
    /// The name and the address are given separately : what a source is called
    /// is the reader's language, spaces and accents included, and what it is
    /// served at is an address.
    @discardableResult
    private func source(_ name: String, at host: String, announcing: Bool) async throws -> Feed {
        var feed = Feed(url: URL(string: "https://\(host)/atom.xml")!, title: name)
        feed.siteURL = URL(string: "https://\(host)")
        feed.notifiesNewArticles = announcing
        try await database.writer.write { db in try feed.insert(db) }
        return feed
    }

    /// An article that reached this device at a moment, whatever it is dated.
    @discardableResult
    private func article(
        _ title: String,
        of feed: Feed,
        receivedAt: Date,
        isRead: Bool = false,
        isHidden: Bool = false,
        duplicateOf: UUID? = nil
    ) async throws -> UUID {
        var entry = Entry(feedID: feed.id, guid: "urn:\(title)", title: title, receivedAt: receivedAt)
        entry.hasMedia = false
        entry.isRead = isRead
        entry.isHidden = isHidden
        entry.duplicateOf = duplicateOf
        try await database.writer.write { db in try entry.insert(db) }
        return entry.id
    }

    @Test("Only the sources the reader asked about")
    func onlyThoseAskedAbout() async throws {
        let asked = try await source("Le Monde", at: "lemonde.example.com", announcing: true)
        let other = try await source("Libération", at: "liberation.example.com", announcing: false)
        try await article("Une réforme", of: asked, receivedAt: now.addingTimeInterval(60))
        try await article("Un procès", of: other, receivedAt: now.addingTimeInterval(60))

        let arrived = try await articles.arrived(since: now)
        #expect(arrived.map(\.title) == ["Une réforme"])
        #expect(arrived.map(\.source) == ["Le Monde"])
    }

    @Test("When it arrived here, and not when it was published")
    func whenItArrived() async throws {
        let feed = try await source("Le Monde", at: "lemonde.example.com", announcing: true)
        // A source backfilling a month of articles published them a month ago
        // and served them tonight. A notice about what is dated today would be
        // silent about everything the reader actually just received.
        try await article("Ancien", of: feed, receivedAt: now.addingTimeInterval(-3600))
        try await article("Nouveau", of: feed, receivedAt: now.addingTimeInterval(60))

        #expect(try await articles.arrived(since: now).map(\.title) == ["Nouveau"])
    }

    @Test("They arrive in the order they landed")
    func ordered() async throws {
        let feed = try await source("Le Monde", at: "lemonde.example.com", announcing: true)
        for (index, title) in ["Premier", "Deuxième", "Troisième"].enumerated() {
            try await article(title, of: feed, receivedAt: now.addingTimeInterval(Double(index + 1) * 60))
        }

        #expect(try await articles.arrived(since: now).map(\.title) == ["Premier", "Deuxième", "Troisième"])
    }

    @Test("What is read, hidden or a second copy is left out")
    func leftOut() async throws {
        let feed = try await source("Le Monde", at: "lemonde.example.com", announcing: true)
        let first = try await article("Une réforme", of: feed, receivedAt: now.addingTimeInterval(60))
        // Read on another device an hour ago, hidden by a rule the reader
        // wrote, and the same piece arriving through a second feed of one
        // newsroom. None of the three is news.
        try await article("Déjà lu", of: feed, receivedAt: now.addingTimeInterval(60), isRead: true)
        try await article("Masqué", of: feed, receivedAt: now.addingTimeInterval(60), isHidden: true)
        try await article("Copie", of: feed, receivedAt: now.addingTimeInterval(60), duplicateOf: first)

        #expect(try await articles.arrived(since: now).map(\.title) == ["Une réforme"])
    }

    @Test("The sources that announce are the ones asked for, in the order a list shows them")
    func announcingSources() async throws {
        try await source("Zébu", at: "zebu.example.com", announcing: true)
        try await source("Abeille", at: "abeille.example.com", announcing: true)
        try await source("Chameau", at: "chameau.example.com", announcing: false)

        #expect(try await subscriptions.announcing().map(\.title) == ["Abeille", "Zébu"])
    }

    @Test("Asking about a source, and stopping")
    func askingAndStopping() async throws {
        let feed = try await source("Le Monde", at: "lemonde.example.com", announcing: false)

        try await subscriptions.setNotifies(feed.id, true)
        #expect(try await subscriptions.feed(id: feed.id)?.notifiesNewArticles == true)
        // It says nothing about the favourite beside it : the two are different
        // judgements about the same publisher.
        #expect(try await subscriptions.feed(id: feed.id)?.isFavourite == false)

        try await subscriptions.setNotifies(feed.id, false)
        #expect(try await subscriptions.feed(id: feed.id)?.notifiesNewArticles == false)
    }
}

/// When the reader is actually told about a source's own articles.
@Suite("Telling the reader about a source they asked about", .serialized)
@MainActor
struct AnnouncingSourceTests {
    private let database: AppDatabase
    private let preferences: Preferences
    private let announcer = MemoryAnnouncer()
    private let model: AppModel
    private let now = Date().addingTimeInterval(-120)

    init() throws {
        database = try AppDatabase.inMemory()
        preferences = Preferences(
            cloud: nil,
            local: UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        )
        model = AppModel(database: database, preferences: preferences, announcer: announcer)
    }

    @discardableResult
    private func source(_ name: String = "Le Monde", at host: String = "lemonde.example.com") async throws -> Feed {
        var feed = Feed(url: URL(string: "https://\(host)/atom.xml")!, title: name)
        feed.siteURL = URL(string: "https://\(host)")
        try await database.writer.write { db in try feed.insert(db) }
        return feed
    }

    private func article(_ title: String, of feed: Feed, at moment: Date) async throws {
        var entry = Entry(feedID: feed.id, guid: "urn:\(title)", title: title, receivedAt: moment)
        entry.hasMedia = false
        try await database.writer.write { db in try entry.insert(db) }
    }

    /// The reader has asked about the source, and the clock started then.
    private func asked(about feed: Feed, from moment: Date) async {
        await model.setNotifications(true, forSource: feed.id)
        preferences.articlesAnnouncedAt = moment
    }

    @Test("An article published while the reader was away is announced")
    func announced() async throws {
        let feed = try await source()
        await asked(about: feed, from: now)
        model.isReading = false
        try await article("Une réforme", of: feed, at: now.addingTimeInterval(60))

        await model.announceNewArticles()

        #expect(announcer.posted.count == 1)
        #expect(announcer.posted.first?.title == "Une réforme")
        #expect(announcer.posted.first?.article != nil)
    }

    @Test("Nothing is said twice")
    func onlyOnce() async throws {
        let feed = try await source()
        await asked(about: feed, from: now)
        model.isReading = false
        try await article("Une réforme", of: feed, at: now.addingTimeInterval(60))

        await model.announceNewArticles()
        await model.announceNewArticles()

        #expect(announcer.posted.count == 1)
    }

    @Test("Nothing interrupts a reader looking at the page it would be on")
    func silentWhileReading() async throws {
        let feed = try await source()
        await asked(about: feed, from: now)
        model.isReading = true
        try await article("Une réforme", of: feed, at: now.addingTimeInterval(60))

        await model.announceNewArticles()
        #expect(announcer.posted.isEmpty)

        // And it is not saved up for later : the article appeared in the list
        // they had open.
        model.isReading = false
        await model.announceNewArticles()
        #expect(announcer.posted.isEmpty)
    }

    @Test("A reader who asked about no source hears nothing, and the clock does not run")
    func silentUntilAskedFor() async throws {
        let feed = try await source()
        model.isReading = false
        try await article("Une réforme", of: feed, at: now.addingTimeInterval(60))

        await model.announceNewArticles()

        #expect(announcer.posted.isEmpty)
        // Untouched, so that asking about a source later starts from that
        // moment rather than from whatever a silent pass had stamped.
        #expect(preferences.articlesAnnouncedAt == nil)
    }

    @Test("Asking about a source starts the clock, so its backlog is not news")
    func startsFromNow() async throws {
        let feed = try await source()
        try await article("Ancien", of: feed, at: now.addingTimeInterval(-86400))

        await model.setNotifications(true, forSource: feed.id)
        model.isReading = false
        await model.announceNewArticles()

        #expect(announcer.posted.isEmpty)
        #expect(preferences.articlesAnnouncedAt != nil)
    }

    @Test("A refusal leaves the source alone")
    func refused() async throws {
        let feed = try await source()
        announcer.granted = false

        await model.setNotifications(true, forSource: feed.id)

        // The system said no, and nothing in an application may say otherwise :
        // a source saved as announcing would be a switch that promises what it
        // cannot deliver.
        #expect(try await SubscriptionStore(database).feed(id: feed.id)?.notifiesNewArticles == false)
        #expect(model.notificationStatus == .denied)
        #expect(preferences.articlesAnnouncedAt == nil)
    }

    @Test("Nothing is said about a source that was not asked about")
    func onlyTheOnesAskedAbout() async throws {
        let asked = try await source("Le Monde")
        let other = try await source("Libération", at: "liberation.example.com")
        await self.asked(about: asked, from: now)
        model.isReading = false
        try await article("Un procès", of: other, at: now.addingTimeInterval(60))

        await model.announceNewArticles()
        #expect(announcer.posted.isEmpty)
    }

    @Test("Stopping stops it")
    func stopped() async throws {
        let feed = try await source()
        await asked(about: feed, from: now)
        await model.setNotifications(false, forSource: feed.id)

        model.isReading = false
        try await article("Une réforme", of: feed, at: now.addingTimeInterval(60))
        await model.announceNewArticles()

        #expect(announcer.posted.isEmpty)
    }

    @Test("A decision arriving from another device says nothing about the backlog")
    func fromAnotherDevice() async throws {
        let feed = try await source()
        model.isReading = false
        try await article("Ancien", of: feed, at: now.addingTimeInterval(-86400))
        // The switch was thrown on the iPad : the row arrives here already on,
        // and this device has never said anything about anything.
        try await SubscriptionStore(database).setNotifies(feed.id, true)

        await model.announceNewArticles()

        #expect(announcer.posted.isEmpty)
        // The clock starts now, so the next pass is the first that can say
        // anything.
        #expect(preferences.articlesAnnouncedAt != nil)

        try await article("Nouveau", of: feed, at: Date().addingTimeInterval(1))
        await model.announceNewArticles()
        #expect(announcer.posted.map(\.title) == ["Nouveau"])
    }
}
