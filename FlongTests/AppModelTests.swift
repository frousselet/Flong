//
//  AppModelTests.swift
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
import Testing

@testable import Flong

@Suite("Reading window", .serialized)
@MainActor
struct AppModelTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let model: AppModel
    private let server = StubServer(host: "window.example.com")

    init() throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
        model = AppModel(
            database: database,
            fetcher: FeedFetcher(
                session: server.makeSession(),
                throttle: HostThrottle(interval: 0, burst: 100),
                userAgent: "Flong/test"
            )
        )
    }

    private func file(_ opml: String) throws -> URL {
        let url = URL.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).opml")
        try Data(opml.utf8).write(to: url)
        return url
    }

    @discardableResult
    private func seed(_ title: String, feed: Feed, isRead: Bool = false) async throws -> UUID {
        var entry = Entry(
            feedID: feed.id,
            guid: "urn:example:\(title)",
            url: URL(string: "https://example.com/\(title)"),
            title: title,
            excerpt: "About \(title)",
            publishedAt: Date(),
            isRead: isRead
        )
        entry.hasMedia = false

        try await database.writer.write { db in
            try entry.insert(db)
            try EntryBody(entryID: entry.id, sanitizedHTML: "<p>\(title)</p>").insert(db)
        }
        return entry.id
    }

    // MARK: - The sidebar

    @Test("The sidebar holds the fixed views, then the folders, then the loose feeds")
    func sidebar() async throws {
        let filed = try await subscriptions.subscribe(
            to: Subscription(address: "https://a.example.com/f.xml", title: "Filed", folder: "Presse")
        ).feed
        let loose = try await subscriptions.subscribe(
            to: Subscription(address: "https://b.example.com/f.xml", title: "Loose")
        ).feed

        try await seed("one", feed: filed)
        try await seed("two", feed: filed, isRead: true)
        try await seed("three", feed: loose)

        await model.load()

        #expect(model.smartLists.map(\.kind) == [.digest, .unread, .today, .starred, .all])
        #expect(model.smartLists.first { $0.kind == .unread }?.unreadCount == 2)

        #expect(model.feedItems.map(\.title) == ["Presse", "Loose"])
        #expect(model.feedItems.first?.unreadCount == 1)
        #expect(model.feedItems.first?.children.map(\.title) == ["Filed"])
        #expect(!model.isEmpty)
    }

    @Test("Selecting a view changes what the list holds")
    func selecting() async throws {
        let first = try await subscriptions.subscribe(
            to: Subscription(address: "https://a.example.com/f.xml", title: "A")
        ).feed
        let second = try await subscriptions.subscribe(
            to: Subscription(address: "https://b.example.com/f.xml", title: "B")
        ).feed
        try await seed("one", feed: first)
        try await seed("two", feed: second, isRead: true)

        model.selection = .unread
        await model.load()
        #expect(model.summaries.map(\.title) == ["one"])

        model.selection = .all
        await model.loadArticles()
        #expect(model.summaries.count == 2)

        model.selection = .feed(second.id)
        await model.loadArticles()
        #expect(model.summaries.map(\.title) == ["two"])
    }

    // MARK: - Reading

    @Test("Opening an article reads it, and the counts follow")
    func openingAnArticle() async throws {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://a.example.com/f.xml", title: "A")
        ).feed
        let id = try await seed("one", feed: feed)
        model.selection = .unread
        await model.load()

        await model.open(article: id)

        #expect(model.article?.id == id)
        #expect(model.article?.bodyHTML == "<p>one</p>")
        #expect(model.summaries.first?.isRead == true)
        #expect(model.smartLists.first?.unreadCount == 0)
    }

    @Test("An article can be put back in the unread pile")
    func markingUnread() async throws {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://a.example.com/f.xml", title: "A")
        ).feed
        let id = try await seed("one", feed: feed)
        model.selection = .unread
        await model.load()

        await model.open(article: id)
        await model.markCurrentUnread()

        #expect(model.selectedArticle == nil)
        #expect(model.summaries.first?.isRead == false)
    }

    @Test("Reading and starring can be undone from the list")
    func toggling() async throws {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://a.example.com/f.xml", title: "A")
        ).feed
        try await seed("one", feed: feed)
        model.selection = .unread
        await model.load()

        let summary = try #require(model.summaries.first)
        await model.toggleRead(summary)
        #expect(model.summaries.first?.isRead == true)

        await model.toggleStarred(try #require(model.summaries.first))
        #expect(model.summaries.first?.isStarred == true)
    }

    @Test("A whole view can be given up on")
    func markingAllRead() async throws {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://a.example.com/f.xml", title: "A")
        ).feed
        try await seed("one", feed: feed)
        try await seed("two", feed: feed)
        model.selection = .unread
        await model.load()

        await model.markAllRead()

        #expect(model.summaries.isEmpty)
        #expect(model.smartLists.first?.unreadCount == 0)
    }

    // MARK: - Searching

    @Test("Typing a query narrows the list to what answers it")
    func searching() async throws {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://a.example.com/f.xml", title: "A")
        ).feed
        try await seed("Une réforme du calendrier", feed: feed)
        try await seed("Les macros Swift", feed: feed)
        model.selection = .unread
        await model.load()

        model.searchText = "réforme"
        await model.loadArticles()

        #expect(model.isShowingResults)
        #expect(model.summaries.map(\.title) == ["Une réforme du calendrier"])

        model.searchText = ""
        await model.loadArticles()
        #expect(!model.isShowingResults)
        #expect(model.summaries.count == 2)
    }

    @Test("A query that says nothing is not a query")
    func emptyQuery() async throws {
        model.searchText = "   "
        #expect(model.query == nil)
        #expect(!model.isShowingResults)
    }

    @Test("Feed and folder names complete themselves")
    func suggestions() async throws {
        try await subscriptions.subscribe(
            to: Subscription(address: "https://a.example.com/f.xml", title: "Le Quotidien", folder: "Presse")
        )
        try await subscriptions.subscribe(
            to: Subscription(address: "https://b.example.com/f.xml", title: "Swift", folder: "Veille/iOS")
        )
        await model.load()

        model.searchText = "feed:quot"
        #expect(model.searchSuggestions == ["feed:\"Le Quotidien\""])

        model.searchText = "réforme tag:vei"
        #expect(model.searchSuggestions == ["réforme tag:Veille/iOS"])

        model.searchText = "réforme"
        #expect(model.searchSuggestions.isEmpty)
    }

    // MARK: - Subscribing

    @Test("An address becomes a feed, its articles and a selection")
    func addingAFeed() async throws {
        let body = try Fixtures.data("Feeds/rss2.xml")
        server.install { _ in StubResponse(statusCode: 200, body: body) }
        defer { server.reset() }

        await model.addFeed(at: "window.example.com/feed.xml")

        #expect(model.failure == nil)
        #expect(model.feedItems.map(\.title) == ["Example Weekly"])
        #expect(model.summaries.count == 2)
        if case .feed = model.selection {} else { Issue.record("The new feed should be selected") }
    }

    @Test("An address that leads to no feed is reported, not thrown")
    func addingSomethingElse() async throws {
        server.install { _ in
            StubResponse(statusCode: 200, headers: ["Content-Type": "text/html"], body: Data("<html></html>".utf8))
        }
        defer { server.reset() }

        await model.addFeed(at: "window.example.com")

        #expect(model.failure == .noFeedFound)
        #expect(model.isEmpty)
    }

    @Test("An address that is not one at all is reported before anything is asked")
    func addingNonsense() async throws {
        await model.addFeed(at: "not an address")

        #expect(model.failure == .invalidAddress)
        #expect(server.requests.isEmpty)
    }

    @Test("An OPML file fills the sidebar and reports what it did")
    func importing() async throws {
        server.install { _ in StubResponse(statusCode: 404) }
        defer { server.reset() }

        let url = try file(
            """
            <opml><body>
              <outline text="Tech">
                <outline text="Example" xmlUrl="https://window.example.com/1.xml"/>
              </outline>
              <outline text="Broken" xmlUrl="not an address"/>
            </body></opml>
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        await model.importOPML(from: url)

        #expect(model.report?.added == 1)
        #expect(model.report?.skipped.count == 1)
        #expect(model.feedItems.map(\.title) == ["Tech"])
    }

    @Test("A file that is not a subscription list is reported, not thrown")
    func importingSomethingElse() async throws {
        let url = try file("<rss><channel/></rss>")
        defer { try? FileManager.default.removeItem(at: url) }

        await model.importOPML(from: url)

        #expect(model.failure == .notOPML)
        #expect(model.isEmpty)
    }
}

/// What the front page says the machinery is doing.
///
/// The page said nothing about any of it : a pass that fetched three hundred
/// feeds, wrote sixty headlines and exchanged with iCloud was, to the reader, a
/// page that changed under them for no stated reason.
@Suite("What the page says is happening")
struct WorkPhaseTests {
    @Test("A count is shown only once there is one to show")
    func counts() {
        // Nought of nought is a job that has not said yet, not a job with
        // nothing to do : the bar runs rather than showing itself full.
        #expect(WorkPhase.fetching(done: 0, total: 0).count == nil)
        #expect(WorkPhase.grouping.count == nil)
        #expect(WorkPhase.synchronizing.count == nil)

        let count = WorkPhase.fetching(done: 3, total: 12).count
        #expect(count?.done == 3)
        #expect(count?.total == 12)
    }

    @Test("The bar never runs backwards")
    func monotonic() {
        // A resumable job works its total out afresh after every batch, as what
        // it has done plus what is left, so articles arriving mid-pass raise
        // it. Taken at face value the bar retreats, which reads as the
        // application undoing itself.
        let phase = WorkPhase.filing(done: 8, total: 20).advanced(done: 9, total: 12)

        #expect(phase.count?.total == 20)
        #expect(phase.count?.done == 9)
    }

    @Test("A count past its total is held to it")
    func clamped() {
        #expect(WorkPhase.writing(done: 30, total: 12).count?.done == 12)
    }

    @Test("A phase that carries no count ignores one")
    func countlessPhases() {
        #expect(WorkPhase.grouping.advanced(done: 4, total: 9) == .grouping)
        #expect(WorkPhase.tidying.advanced(done: 4, total: 9) == .tidying)
    }

    @Test("A batch moving on is told from a different phase taking the line")
    func kinds() {
        #expect(WorkPhase.fetching(done: 1, total: 2).isSameKind(as: .fetching(done: 9, total: 9)))
        #expect(!WorkPhase.fetching(done: 1, total: 2).isSameKind(as: .filing(done: 1, total: 2)))
        #expect(WorkPhase.tidying.isSameKind(as: .tidying))
    }
}

/// One refresh at a time, whichever of the six triggers asked for it.
@Suite("Two refreshes never run at once", .serialized)
@MainActor
struct ExclusiveRefreshTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let model: AppModel
    private let server = StubServer(host: "exclusive.example.com")

    init() throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
        model = AppModel(
            database: database,
            fetcher: FeedFetcher(
                session: server.makeSession(),
                throttle: HostThrottle(interval: 0, burst: 100),
                userAgent: "Flong/test"
            )
        )
    }

    @Test("A second catch-up while one is running is refused, not queued")
    func concurrentCatchUps() async throws {
        try await subscriptions.subscribe(
            to: Subscription(url: server.url.appending(path: "f.xml"), title: "F")
        )

        let body = try Fixtures.data("Feeds/rss2.xml")
        server.install { _ in StubResponse(statusCode: 200, body: body) }
        defer { server.reset() }

        // The nightly pass and the five-minute clock could ask three hundred
        // publishers the same question at the same second, each unaware of the
        // other. What a publisher sees is what this is about.
        async let first: Void = model.catchUp(.reader)
        async let second: Void = model.catchUp(.clock)
        _ = await (first, second)

        #expect(server.requests.count == 1)
        // And the gate is given back, so the next one is not refused for ever.
        #expect(!model.isRefreshing)
    }

    @Test("The reader's command stands aside for a pass already running")
    func commandStandsAside() async throws {
        try await subscriptions.subscribe(
            to: Subscription(url: server.url.appending(path: "g.xml"), title: "G")
        )
        server.install { _ in StubResponse(statusCode: 304) }
        defer { server.reset() }

        async let pass: Void = model.backgroundProcessing()
        async let asked: Void = model.refreshAll()
        _ = await (pass, asked)

        #expect(server.requests.count == 1)
        #expect(!model.isRefreshing)
    }
}

/// What each trigger asks for, which is the whole of what tells them apart.
@Suite("What sets a catch-up going")
struct CatchUpTests {
    @Test("Only the reader asks for every feed")
    func everyFeed() {
        // Everything automatic goes through the politeness of section 8, which
        // is what keeps a reader's devices from becoming a burden on three
        // hundred publishers.
        #expect(CatchUp.reader.asksEveryFeed)
        #expect(CatchUp.pull.asksEveryFeed)
        #expect(!CatchUp.launch.asksEveryFeed)
        #expect(!CatchUp.foreground.asksEveryFeed)
        #expect(!CatchUp.clock.asksEveryFeed)
        #expect(!CatchUp.background.asksEveryFeed)
    }

    @Test("Only a background pass spares the reader's data plan")
    func sparingly() {
        #expect(CatchUp.background.sparingly)
        #expect(!CatchUp.pull.sparingly)
        #expect(!CatchUp.clock.sparingly)
    }

    @Test("The model is not run in the twenty-five seconds of a background refresh")
    func model() {
        // The system rate-limits a backgrounded application's sessions hard,
        // and a handful of refusals there used to silence the model for the
        // whole of the process that followed.
        #expect(!CatchUp.background.mayRunTheModel)
        #expect(CatchUp.pull.mayRunTheModel)
        #expect(CatchUp.launch.mayRunTheModel)
    }

    @Test("A pull does not replace the page under its own control")
    func readsBack() {
        // SwiftUI holds the refresh control out until the gesture's work
        // returns, so replacing the content as the last thing before returning
        // has the scroll view begin its retraction against content it has never
        // laid out. The watcher reads back once the control is out of the way.
        #expect(!CatchUp.pull.readsBackAtOnce)
        #expect(CatchUp.reader.readsBackAtOnce)
        #expect(CatchUp.clock.readsBackAtOnce)
        #expect(CatchUp.background.readsBackAtOnce)
    }
}

/// The two floors that keep the line from flickering.
@Suite("When the activity line appears, and when it goes", .serialized)
@MainActor
struct ActivityTimingTests {
    private let model: AppModel

    init() throws {
        model = AppModel(database: try AppDatabase.inMemory())
    }

    @Test("Work that is over before it could be read is never shown at all")
    func tooShortToShow() async throws {
        model.show(.fetching(done: 0, total: 0))
        model.show(nil)

        // A catch-up that finds nothing due returns in a few milliseconds, and
        // a line that appeared and left inside one frame is a flicker rather
        // than information.
        try await Task.sleep(for: AppModel.workAppearsAfter * 3)
        #expect(model.work == nil)
    }

    @Test("Work that lasts is shown, and shown long enough to read")
    func longEnoughToRead() async throws {
        model.show(.grouping)
        // Not yet : nothing shorter than the first floor is seen at all.
        #expect(model.work == nil)

        try await Task.sleep(for: AppModel.workAppearsAfter * 3)
        #expect(model.work == .grouping)

        // The same fault the other way : a line that appeared for good reason
        // and left before it could be read told the reader nothing.
        model.show(nil)
        #expect(model.work == .grouping)

        try await Task.sleep(for: AppModel.workStaysFor * 2)
        #expect(model.work == nil)
    }

    @Test("The words are the phase the work has reached, not the one it started")
    func showsThePhaseReached() async throws {
        model.show(.fetching(done: 0, total: 0))
        model.show(.grouping)

        try await Task.sleep(for: AppModel.workAppearsAfter * 3)
        #expect(model.work == .grouping)
    }
}
