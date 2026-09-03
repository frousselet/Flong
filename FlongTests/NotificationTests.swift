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
    private func opened(
        _ title: String,
        summary: String? = nil,
        rooms: [String] = ["lemonde.fr"],
        picture: URL? = nil
    ) -> DigestStore.Opened {
        DigestStore.Opened(id: .v7(), title: title, summary: summary, rooms: rooms, picture: picture)
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

    @Test("The count in the title is honest about a body that names only a few")
    func theCountIsHonest() throws {
        let stories = (1...12).map { opened("Fil \($0)") }
        let announcement = try #require(Announcement.newStories(stories))

        // The count says twelve because there are twelve. The body names the
        // first three : twelve headlines joined by a middle dot is a paragraph,
        // and a paragraph in a banner is a wall the reader's eye slides off.
        // The newest three, and not the first three : every query behind these
        // answers oldest first, so the front of the list is the stalest of them.
        #expect(announcement.title.contains("12"))
        for story in stories.suffix(3) {
            #expect(announcement.body.contains(story.title))
        }
        #expect(!announcement.body.contains("Fil 1 "))
    }

    /// A picture where there is one story to show a picture of, and none where
    /// there are several : the photograph of the first of three is a claim
    /// about the other two.
    @Test("One story carries its picture, and several carry none")
    func picture() throws {
        let cover = URL(string: "https://feeds.example.com/reforme.jpg")!
        let one = try #require(Announcement.newStories([opened("Une réforme", picture: cover)]))
        #expect(one.picture == cover)

        let several = try #require(
            Announcement.newStories([opened("Une réforme", picture: cover), opened("Un procès")])
        )
        #expect(several.picture == nil)
    }

    @Test("A story nobody has photographed is announced all the same")
    func pictureless() throws {
        // The ordinary case at the moment a story opens : the notice is the
        // headline, and the photograph is what it gains when a newsroom puts
        // one on it.
        #expect(try #require(Announcement.newStories([opened("Une réforme")])).picture == nil)
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

    /// The same rule the front page follows : a story is shown for where it has
    /// got to, so the photograph is the latest one there is. A notice carrying
    /// a different picture from the page it opens would be about a different
    /// story as far as the reader can tell.
    @Test("A story wears the picture of the latest article to carry one")
    func picture() async throws {
        let moment = now.addingTimeInterval(60)
        let old = URL(string: "https://a.example.com/premier.jpg")!
        let new = URL(string: "https://b.example.com/dernier.jpg")!

        let story = Story(id: .v7(at: moment), title: "Une réforme", firstAt: moment, lastAt: moment, updatedAt: moment)
        try await database.writer.write { db in
            try story.insert(db)

            // Three rooms, oldest first : one with a photograph, then the
            // newest with one of its own, then a room that published none.
            let members: [(room: String, minutes: Double, picture: URL?)] = [
                ("a.example.com", 0, old),
                ("b.example.com", 1, new),
                ("c.example.com", 2, nil),
            ]
            for (index, member) in members.enumerated() {
                var feed = Feed(url: URL(string: "https://\(member.room)/atom.xml")!, title: member.room)
                feed.siteURL = URL(string: "https://\(member.room)")
                try feed.insert(db)

                var entry = Entry(
                    feedID: feed.id,
                    guid: "urn:réforme:\(index)",
                    title: "Une réforme",
                    publishedAt: moment.addingTimeInterval(member.minutes * 60),
                    receivedAt: moment
                )
                entry.hasMedia = false
                entry.imageURL = member.picture
                try entry.insert(db)
                try StoryMember(storyID: story.id, entryID: entry.id, similarity: 1).insert(db)
            }
        }

        // Not the picture of the newest article, which has none : the newest
        // that has one. A story whose last room ran no photograph is not a
        // story that loses its photograph.
        #expect(try await digest.opened(since: now, now: now).first?.picture == new)
        #expect(old != new)
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
    private func arrival(
        _ title: String,
        from source: String = "Le Monde",
        picture: URL? = nil
    ) -> ArticleStore.Arrival {
        ArticleStore.Arrival(id: .v7(), title: title, source: source, picture: picture, author: nil)
    }

    @Test("A pass that brought nothing from those sources says nothing")
    func silence() {
        // The ordinary case : almost every pass brings articles from sources
        // the reader asked nothing about.
        #expect(Announcement.newArticles([]) == nil)
    }

    @Test("One article leads with where it came from, and a tap opens it")
    func one() throws {
        let article = arrival("Une réforme du calendrier scolaire")
        let announcement = try #require(Announcement.newArticles([article]))

        // The source in the one bold line a banner truncates at forty
        // characters, and the headline where there is room to read it.
        #expect(announcement.title == "Le Monde")
        #expect(announcement.subtitle == nil)
        #expect(announcement.body == "Une réforme du calendrier scolaire")
        #expect(announcement.article == article.id)
        // An article is read over everything, and a story is a page in the
        // digest : a tap has one place to land and this is not the other one.
        #expect(announcement.story == nil)
    }

    /// A picture where there is one article to show a picture of, and none
    /// where there are several.
    @Test("One article carries its picture, and several carry none")
    func picture() throws {
        let cover = URL(string: "https://feeds.example.com/reforme.jpg")!
        let one = try #require(Announcement.newArticles([arrival("Une réforme", picture: cover)]))
        #expect(one.picture == cover)

        let several = try #require(
            Announcement.newArticles([arrival("Une réforme", picture: cover), arrival("Un procès")])
        )
        #expect(several.picture == nil)
    }

    @Test("An article nobody illustrated is announced all the same")
    func pictureless() throws {
        #expect(try #require(Announcement.newArticles([arrival("Une réforme")])).picture == nil)
    }

    @Test("Several from one source are counted under its name")
    func severalFromOne() throws {
        let articles = [arrival("Une réforme"), arrival("Les macros Swift"), arrival("Le procès")]
        let announcement = try #require(Announcement.newArticles(articles))

        #expect(announcement.title == "Le Monde")
        #expect(try #require(announcement.subtitle).contains("3"))
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

    @Test("An article by a writer the reader asked about names them under the headline")
    func onePerson() throws {
        let article = ArticleStore.Arrival(
            id: .v7(),
            title: "Une réforme du calendrier scolaire",
            source: "Le Monde",
            author: "Claire Ancelin"
        )
        let announcement = try #require(Announcement.newArticles([article]))

        // The person the reader asked about leads, the paper they wrote it for
        // is the line between, and the headline is the message : that is the
        // answer to `why am I being told this`, in the order a notification
        // gives the three of them room.
        #expect(announcement.title == "Claire Ancelin")
        #expect(announcement.subtitle == "Le Monde")
        #expect(announcement.body == "Une réforme du calendrier scolaire")
        #expect(announcement.article == article.id)
    }

    @Test("Several by one writer are counted under their name, not their papers")
    func severalByOnePerson() throws {
        // The whole point of asking of a person : they are followed wherever
        // they write, so two papers in one notice is the notice working.
        let articles = [
            ArticleStore.Arrival(id: .v7(), title: "Une réforme", source: "Le Monde", author: "Claire Ancelin"),
            ArticleStore.Arrival(id: .v7(), title: "Un procès", source: "Libération", author: "Claire Ancelin"),
        ]
        let announcement = try #require(Announcement.newArticles(articles))

        #expect(announcement.title == "Claire Ancelin")
        #expect(try #require(announcement.subtitle).contains("2"))
        #expect(announcement.body == "Une réforme · Un procès")
    }

    @Test("A writer and a source in one pass are listed as the two things asked about")
    func peopleAndPapers() throws {
        let articles = [
            arrival("Une réforme"),
            ArticleStore.Arrival(id: .v7(), title: "Un procès", source: "Libération", author: "Claire Ancelin"),
        ]
        let announcement = try #require(Announcement.newArticles(articles))

        #expect(announcement.title.contains("2"))
        // What the reader asked about is what they are told : the paper for the
        // one, the person for the other.
        #expect(announcement.body.contains("Le Monde"))
        #expect(announcement.body.contains("Claire Ancelin"))
        #expect(!announcement.body.contains("Libération"))
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
        duplicateOf: UUID? = nil,
        picture: URL? = nil
    ) async throws -> UUID {
        var entry = Entry(feedID: feed.id, guid: "urn:\(title)", title: title, receivedAt: receivedAt)
        entry.hasMedia = false
        entry.isRead = isRead
        entry.isHidden = isHidden
        entry.duplicateOf = duplicateOf
        entry.imageURL = picture
        try await database.writer.write { db in try entry.insert(db) }
        return entry.id
    }

    @Test("An arrival carries the picture that stands for it")
    func carriesThePicture() async throws {
        let feed = try await source("Le Monde", at: "lemonde.example.com", announcing: true)
        let cover = URL(string: "https://lemonde.example.com/reforme.jpg")!
        try await article("Une réforme", of: feed, receivedAt: now.addingTimeInterval(60), picture: cover)
        try await article("Un procès", of: feed, receivedAt: now.addingTimeInterval(120))

        let arrived = try await articles.arrived(since: now)
        // The same address the row in the list carries : a notice showing one
        // picture and the article it opens showing another would be two
        // articles as far as the reader can tell.
        #expect(arrived.map(\.picture) == [cover, nil])
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

    /// A writer the reader asked about, and an article they signed.
    private func signed(
        _ title: String,
        by writer: String,
        of feed: Feed,
        receivedAt: Date
    ) async throws -> UUID {
        var entry = Entry(
            feedID: feed.id,
            guid: "urn:\(title)",
            title: title,
            author: writer,
            receivedAt: receivedAt
        )
        entry.hasMedia = false
        try await database.writer.write { db in
            try entry.insert(db)
            try AuthorStore.index(entry.id, byline: writer, in: db)
        }
        return entry.id
    }

    @Test("A writer the reader asked about is announced wherever they write")
    func aWriterAnywhere() async throws {
        let quiet = try await source("Libération", at: "liberation.example.com", announcing: false)
        try await AuthorStore(database).setNotifies("Claire Ancelin", true)

        try await signed("Un procès", by: "Claire Ancelin", of: quiet, receivedAt: now.addingTimeInterval(60))
        try await signed("Autre chose", by: "Paul Rey", of: quiet, receivedAt: now.addingTimeInterval(60))

        // The source says nothing and is not meant to : what was asked about is
        // the person, and they are followed into whichever paper carries them.
        let arrived = try await articles.arrived(since: now)
        #expect(arrived.map(\.title) == ["Un procès"])
        #expect(arrived.first?.author == "Claire Ancelin")
        #expect(arrived.first?.source == "Libération")
    }

    @Test("An article that answers both questions is announced once")
    func neverTwice() async throws {
        // The ordinary case, and the one that would be wrong twice over : a
        // writer somebody follows very often writes for a paper they follow as
        // well. Asked as two questions this article is in both answers, and the
        // reader gets one notice about the paper and a second, moments later,
        // about the person.
        let loud = try await source("Le Monde", at: "lemonde.example.com", announcing: true)
        try await AuthorStore(database).setNotifies("Claire Ancelin", true)
        try await signed("Une réforme", by: "Claire Ancelin", of: loud, receivedAt: now.addingTimeInterval(60))

        let arrived = try await articles.arrived(since: now)
        #expect(arrived.count == 1)
        // And the person leads the wording, since asking about somebody is the
        // more particular of the two requests.
        #expect(arrived.first?.author == "Claire Ancelin")
        #expect(arrived.first?.subject == "Claire Ancelin")
    }

    @Test("A byline naming several people answers for the one asked about")
    func theOneAskedAbout() async throws {
        let quiet = try await source("Libération", at: "liberation.example.com", announcing: false)
        try await AuthorStore(database).setNotifies("Paul Rey", true)
        try await signed(
            "Une enquête",
            by: "Claire Ancelin et Paul Rey",
            of: quiet,
            receivedAt: now.addingTimeInterval(60)
        )

        // A piece signed by two people where the reader asked about one is news
        // about that one, and the notice names them rather than the byline.
        let arrived = try await articles.arrived(since: now)
        #expect(arrived.count == 1)
        #expect(arrived.first?.author == "Paul Rey")
    }

    @Test("Asking about a writer, and stopping")
    func askingAboutAWriter() async throws {
        let store = AuthorStore(database)

        try await store.setNotifies("Claire Ancelin", true)
        #expect(try await store.notified() == ["Claire Ancelin"])
        // It singles nobody out : the favourite gathers a page, and this
        // interrupts. A reader may well want one without the other.
        #expect(try await store.favourites().isEmpty)

        try await store.setNotifies("Claire Ancelin", false)
        #expect(try await store.notified().isEmpty)
    }

    @Test("A writer asked about is on their own page even with nothing to their name")
    func aWriterWithNothingHere() async throws {
        let store = AuthorStore(database)
        try await store.setNotifies("Claire Ancelin", true)

        // The decision arrived from another device, or the purge took the last
        // of what they signed. The page still exists, and it still has to be
        // able to undo the decision.
        let author = try await store.author(named: "Claire Ancelin")
        #expect(author?.notifies == true)
        #expect(author?.isFavourite == false)
        #expect(try await store.all().contains { $0.name == "Claire Ancelin" && $0.notifies })
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

/// The state a model is born in, which is the state a background launch keeps.
///
/// **The whole of the reader's bug lived here.** Every test in this file used to
/// write `isReading` before asserting anything, so the value a model is
/// actually built with was the one value nothing exercised. iOS reclaims a
/// backgrounded application within minutes, so the ordinary background refresh
/// runs in a process with no scene, against a model nothing has ever told
/// anything : it kept the `true` it was born with, suppressed every notice, and
/// stamped the watermark on its way out so no later pass could say them either.
@Suite("A model with no window")
@MainActor
struct WindowlessModelTests {
    @Test("A model is not reading until a window says it is")
    func notReadingUntilToldOtherwise() throws {
        // A suite of its own, like every other model built here : a test that
        // takes the standard defaults writes into the preferences of the
        // application hosting it, and leaves them behind on the device.
        let model = AppModel(
            database: try AppDatabase.inMemory(),
            preferences: Preferences(
                cloud: nil,
                local: UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
            )
        )

        #expect(!model.isReading)
    }

    @Test("A model with no window announces what a pass brought it")
    func announcesWithNoWindow() async throws {
        let database = try AppDatabase.inMemory()
        let preferences = Preferences(
            cloud: nil,
            local: UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        )
        let announcer = MemoryAnnouncer()
        // Built exactly as `BackgroundWorkBox` builds one, and told nothing
        // else at all.
        let model = AppModel(database: database, preferences: preferences, announcer: announcer)

        var feed = Feed(url: URL(string: "https://lemonde.example.com/atom.xml")!, title: "Le Monde")
        feed.siteURL = URL(string: "https://lemonde.example.com")
        feed.notifiesNewArticles = true
        try await database.writer.write { db in try feed.insert(db) }

        await model.setNotifications(true, forSource: feed.id)

        var entry = Entry(
            feedID: feed.id,
            guid: "urn:reforme",
            title: "Une réforme",
            receivedAt: Date().addingTimeInterval(1)
        )
        entry.hasMedia = false
        try await database.writer.write { db in try entry.insert(db) }

        await model.announceNewArticles()

        #expect(announcer.posted.map(\.body) == ["Une réforme"])
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
        #expect(announcer.posted.first?.title == "Le Monde")
        #expect(announcer.posted.first?.body == "Une réforme")
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

    @Test("A writer the reader asked about is announced, and only once")
    func aWriterIsAnnouncedOnce() async throws {
        let feed = try await source()
        // The paper announces too, which is the case that used to say
        // everything twice.
        await asked(about: feed, from: now)
        await model.setNotifications(true, forAuthor: "Claire Ancelin")
        preferences.articlesAnnouncedAt = now
        model.isReading = false

        var entry = Entry(
            feedID: feed.id,
            guid: "urn:reforme",
            title: "Une réforme",
            author: "Claire Ancelin",
            receivedAt: now.addingTimeInterval(60)
        )
        entry.hasMedia = false
        try await database.writer.write { db in
            try entry.insert(db)
            try AuthorStore.index(entry.id, byline: "Claire Ancelin", in: db)
        }

        await model.announceNewArticles()

        #expect(announcer.posted.count == 1)
        #expect(announcer.posted.first?.title == "Claire Ancelin")
        #expect(announcer.posted.first?.subtitle == "Le Monde")
        #expect(announcer.posted.first?.body == "Une réforme")
    }

    @Test("A refusal leaves the writer alone")
    func refusedForAWriter() async throws {
        announcer.granted = false

        await model.setNotifications(true, forAuthor: "Claire Ancelin")

        #expect(try await AuthorStore(database).notified().isEmpty)
        #expect(model.notificationStatus == .denied)
        #expect(preferences.articlesAnnouncedAt == nil)
    }

    @Test("A reader who asked about a writer alone still hears about them")
    func aWriterWithoutASource() async throws {
        let feed = try await source()
        await model.setNotifications(true, forAuthor: "Claire Ancelin")
        preferences.articlesAnnouncedAt = now
        model.isReading = false

        var entry = Entry(
            feedID: feed.id,
            guid: "urn:proces",
            title: "Un procès",
            author: "Claire Ancelin",
            receivedAt: now.addingTimeInterval(60)
        )
        entry.hasMedia = false
        try await database.writer.write { db in
            try entry.insert(db)
            try AuthorStore.index(entry.id, byline: "Claire Ancelin", in: db)
        }

        // No source announces anything : the clock has to run for a reader who
        // asked only about people.
        await model.announceNewArticles()
        #expect(announcer.posted.map(\.body) == ["Un procès"])
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
        #expect(announcer.posted.map(\.body) == ["Nouveau"])
    }

    // MARK: - The switch that covers every source

    /// The one a reader arrives looking for, and the one that was not there.
    @Test("The panel's own switch announces a source nobody singled out")
    func everySource() async throws {
        let feed = try await source()
        // Nothing was ticked on this feed, and nothing ever will be : this is
        // the reader who follows thirty papers and wants to know when any of
        // them publishes.
        await model.setWantsNewArticleNotices(true)
        model.isReading = false
        try await article("Une réforme", of: feed, at: Date().addingTimeInterval(1))

        await model.announceNewArticles()

        #expect(announcer.posted.map(\.body) == ["Une réforme"])
    }

    @Test("With the switch off, a source nobody asked about says nothing")
    func everySourceOff() async throws {
        let feed = try await source()
        await model.setNotifications(true, forAuthor: "Claire Ancelin")
        preferences.articlesAnnouncedAt = now
        model.isReading = false
        try await article("Une réforme", of: feed, at: now.addingTimeInterval(60))

        await model.announceNewArticles()

        #expect(announcer.posted.isEmpty)
    }

    /// Off until the reader says otherwise, like every other switch here. It
    /// is read from the shared store when that store has an answer, so a value
    /// left there by anything at all is a switch the reader never threw.
    @Test("The switch is off on a device that has never been asked")
    func everySourceStartsOff() {
        let fresh = Preferences(
            cloud: nil,
            local: UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        )

        #expect(!fresh.wantsNewArticleNotices)
        #expect(!fresh.wantsNewStoryNotices)
    }

    @Test("A refusal leaves the switch where it was")
    func everySourceRefused() async throws {
        announcer.granted = false

        await model.setWantsNewArticleNotices(true)

        #expect(!model.wantsNewArticleNotices)
        #expect(!preferences.wantsNewArticleNotices)
        #expect(model.notificationStatus == .denied)
    }

    // MARK: - The watermark

    /// Turning on a second source used to throw away what the first one had
    /// waiting, and a reader switching six on threw it away five times.
    @Test("Asking about a second source does not discard what the first one held")
    func theClockStartsOnce() async throws {
        let first = try await source()
        let second = try await source("Libération", at: "liberation.example.com")

        await model.setNotifications(true, forSource: first.id)
        let started = try #require(preferences.articlesAnnouncedAt)

        try await article("Une réforme", of: first, at: Date().addingTimeInterval(1))
        await model.setNotifications(true, forSource: second.id)

        #expect(preferences.articlesAnnouncedAt == started)
    }

    /// A mark left behind by switches that are all off now is a mark standing
    /// still, and starting from it announces everything published since the
    /// reader last listened.
    @Test("Turning a notice back on after a silence starts from now, not from the silence")
    func theClockRestartsAfterASilence() async throws {
        let feed = try await source()

        await model.setNotifications(true, forSource: feed.id)

        // They find it noisy and turn it off. Nothing is asking now, so the
        // mark stands still from here.
        await model.setNotifications(false, forSource: feed.id)
        preferences.articlesAnnouncedAt = now
        // And a backlog piles up behind it.
        try await article("Ancien", of: feed, at: now.addingTimeInterval(60))

        await model.setWantsNewArticleNotices(true)

        let restarted = try #require(preferences.articlesAnnouncedAt)
        #expect(restarted > now.addingTimeInterval(60))

        // And so the backlog is not read out.
        model.isReading = false
        await model.announceNewArticles()
        #expect(announcer.posted.isEmpty)
    }

    /// Turning a second thing on while a first is already asking must NOT move
    /// the mark : that would swallow whatever the first one has published since
    /// the last pass.
    @Test("Asking about a second thing while a first is on leaves the mark alone")
    func theClockHoldsWhileSomethingIsOn() async throws {
        let feed = try await source()
        await model.setNotifications(true, forSource: feed.id)
        let first = try #require(preferences.articlesAnnouncedAt)

        await model.setWantsNewArticleNotices(true)

        #expect(preferences.articlesAnnouncedAt == first)
    }

    /// The mark is what meters the news, so a read that failed must not move
    /// it : a background pass cut short by its own budget used to swallow
    /// everything it had just fetched, for good.
    @Test("A pass that was cancelled leaves the watermark where it was")
    func cancelledLeavesTheMark() async throws {
        let feed = try await source()
        await asked(about: feed, from: now)
        model.isReading = false
        try await article("Une réforme", of: feed, at: now.addingTimeInterval(60))

        let task = Task { @MainActor in
            await model.announceNewArticles()
        }
        task.cancel()
        await task.value

        #expect(announcer.posted.isEmpty)
        #expect(preferences.articlesAnnouncedAt == now)
    }

    /// **A feed's articles all carry one arrival moment**, to the millisecond :
    /// they are written in one go. So a watermark stamped from the last row a
    /// capped answer returned would skip every sibling that did not fit, and
    /// one stamped just below it would announce the whole group again for ever.
    /// The mark is the clock, the read is bounded only against absurdity, and
    /// what the notice *names* is what is bounded.
    @Test("A pass brings every article of a feed at one moment, and none is skipped")
    func onePassOneMoment() async throws {
        let feed = try await source()
        await model.setWantsNewArticleNotices(true)
        preferences.articlesAnnouncedAt = now
        model.isReading = false

        // One moment for all of them, which is what a refresh actually writes.
        let landed = Date().addingTimeInterval(-1)
        for index in 0..<25 {
            try await article("Article \(index)", of: feed, at: landed)
        }

        await model.announceNewArticles()

        let notice = try #require(announcer.posted.first)
        // The count is the whole truth ; the body names what fits.
        #expect(try #require(notice.subtitle).contains("25"))

        // And the pass is over : nothing is left behind the mark to be said
        // again by the next one.
        await model.announceNewArticles()
        #expect(announcer.posted.count == 1)
    }
}
