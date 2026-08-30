//
//  AppModel.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import OSLog

/// An entry of the sidebar.
nonisolated struct SidebarItem: Identifiable, Hashable, Sendable {
    /// What an entry stands for. It is also the selection, so it holds nothing
    /// that changes when a feed is renamed.
    enum Kind: Hashable {
        case digest
        case unread, today, library, starred, all
        case folder(String)
        case feed(UUID)
    }

    let kind: Kind
    /// The name of a folder or a feed. Smart lists are named by the interface,
    /// in the reader's language.
    let title: String?
    let unreadCount: Int
    /// Where a feed keeps its mark, when it is a feed and it states one.
    var iconURL: URL?
    var siteURL: URL?
    var children: [SidebarItem] = []

    var id: Kind { kind }

    var filter: ArticleFilter {
        switch kind {
        case .unread: .unread
        case .today: .today
        case .starred: .starred
        // The digest reads the stories, not a view of the stream.
        case .digest: .all
        // The library is not a view over the stream : it is its own table, and
        // the list reads it directly.
        case .library, .all: .all
        case .folder(let path): .folder(path)
        case .feed(let id): .feed(id)
        }
    }
}

/// Why something the reader asked for did not happen.
nonisolated enum AppFailure: Hashable, Identifiable, Sendable {
    case unreadableFile
    case notOPML
    case notSaved
    case invalidAddress
    case unreachableFeed
    case noFeedFound
    case notSignedIn

    var id: Self { self }

    var message: LocalizedStringResource {
        switch self {
        case .unreadableFile: "This file could not be opened."
        case .notOPML: "This file could not be read as OPML."
        case .notSaved: "The subscriptions could not be saved."
        case .invalidAddress: "This address is not one Flong can follow."
        case .unreachableFeed: "This address could not be reached."
        case .noFeedFound: "No feed was found at this address."
        case .notSignedIn: "This site left no session. Sign in on its page, then say so."
        }
    }
}

/// What the window shows, and what the reader can do to it.
///
/// One object for one window : the three levels of section 16 of the
/// specification move together, and splitting them would mean keeping three
/// copies of the same selection in step.
@Observable
final class AppModel {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let articles: ArticleStore
    private let library: LibraryStore
    private let spotlight: SpotlightIndex
    private let digestService: DigestService
    private var cloud: CloudSync?
    private let refresher: FeedRefresh
    private let retention: Retention
    private let finder: FeedFinder
    private let opml: OPMLImport
    private let credentials: CredentialStoring
    private let sessions: SessionStoring
    private let preferences: Preferences

    private(set) var sidebar: [SidebarItem] = []
    private(set) var summaries: [ArticleSummary] = []

    /// How many articles arrived on each day of the view being shown, keyed by
    /// the local day. What the chart above the stream is drawn from.
    private(set) var dailyCounts: [Date: Int] = [:]
    private(set) var article: Article?
    /// Whether the page an article lives at is being fetched, so the reader is
    /// told rather than left wondering why the text is short.
    private(set) var isFetchingFullText = false
    /// Which feeds have a credential. The identifiers, never the secrets.
    private(set) var authenticatedFeeds: Set<UUID> = []
    /// The sites the reader has signed in to, for the screen that manages them.
    private(set) var subscribedSites: [SiteSession] = []

    /// Which body an article opens on, as the reader last chose.
    ///
    /// Kept in the iCloud key-value store, so a choice made on the phone is
    /// what the iPad opens on. Not CloudKit : a preference has no business in
    /// a record budget spent on articles.
    var articleBody = Preferences.ArticleBody.feed {
        didSet {
            guard articleBody != oldValue else { return }
            preferences.articleBody = articleBody
        }
    }
    // MARK: - Who is reading

    /// The reader's own name, which belongs to nobody else.
    ///
    /// There is no account and nothing to send it to : it is here so that a
    /// device the reader picks up looks like theirs, and it travels between
    /// their devices through their own iCloud like every other preference.
    var firstName = "" {
        didSet {
            guard firstName != oldValue else { return }
            preferences.firstName = firstName
        }
    }

    var lastName = "" {
        didSet {
            guard lastName != oldValue else { return }
            preferences.lastName = lastName
        }
    }

    /// The reader's own face, ready to draw.
    ///
    /// Decoded once and held, rather than decoded at each draw : it is on
    /// screen in the toolbar of every section, which is as often as anything
    /// gets drawn.
    private(set) var picture: CGImage?

    /// What stands in for a face when there is none.
    var initials: String? {
        ProfilePicture.initials(first: firstName, last: lastName)
    }

    /// The reader's name as one line, when they have given one.
    var name: String? {
        let whole = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return whole.isEmpty ? nil : whole
    }

    /// Takes what the reader picked, scales it, and keeps the small version.
    ///
    /// Anything that is not an image is refused rather than stored : a file
    /// picked by mistake would otherwise become a face that never draws.
    @discardableResult
    func setPicture(_ data: Data?) -> Bool {
        guard let data else {
            preferences.picture = nil
            picture = nil
            return true
        }
        guard let scaled = ProfilePicture.scaled(data) else {
            Log.store.error("What was picked as a profile picture is not an image.")
            return false
        }
        preferences.picture = scaled
        picture = ProfilePicture.image(scaled)
        return true
    }

    /// Reads the name and the face back from what has been kept.
    private func loadProfile() {
        firstName = preferences.firstName
        lastName = preferences.lastName
        picture = preferences.picture.flatMap(ProfilePicture.image)
    }

    private(set) var isRefreshing = false
    private(set) var feedCount = 0

    /// What synchronization is doing, in terms the sidebar can show.
    private(set) var syncStatus = SyncStatus.idle(lastSynchronized: nil)

    /// What is left of the long work : feeds never fetched, articles with no
    /// vector. Both are questions the store answers, which is what makes the
    /// work resumable without a checkpoint to keep in step.
    private(set) var outstandingFeeds = 0
    private(set) var outstandingVectors = 0
    private(set) var isWorking = false

    var hasOutstandingWork: Bool { outstandingFeeds + outstandingVectors > 0 }

    /// Whether the list is showing the answer to a query rather than a view.
    var isShowingResults: Bool { query != nil }

    var selection: SidebarItem.Kind? = .all
    var selectedArticle: UUID?

    /// The summary of the last import, until the reader dismisses it.
    var report: OPMLImportReport?
    var failure: AppFailure?

    /// What is in the search field.
    ///
    /// Results follow it as it is typed, after a pause short enough not to be
    /// felt and long enough that a word is not searched for four times while it
    /// is being written.
    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            search?.cancel()
            search = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                await loadArticles()
            }
        }
    }

    private var search: Task<Void, Never>?

    /// The query as it is understood, or `nil` when the field is empty.
    var query: QueryNode? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let node = QueryParser.parse(trimmed)
        return node == .all ? nil : node
    }

    /// What to offer while a query is being typed.
    ///
    /// Section 12 asks for completion of feed and tag names, which are the two
    /// things nobody remembers the exact spelling of.
    var searchSuggestions: [String] {
        guard let last = searchText.split(separator: " ").last.map(String.init) else { return [] }

        let names: [String]
        let prefix = searchText.dropLast(last.count)

        if last.lowercased().hasPrefix("feed:") {
            names = completions(for: String(last.dropFirst(5)), in: feedTitles)
        } else if last.lowercased().hasPrefix("tag:") {
            names = completions(for: String(last.dropFirst(4)), in: folderPaths)
        } else {
            return []
        }

        let field = last.prefix(while: { $0 != ":" })
        return names.map { name in
            let value = name.contains(" ") ? "\"\(name)\"" : name
            return prefix + field + ":" + value
        }
    }

    private func completions(for text: String, in names: [String]) -> [String] {
        let text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard !names.isEmpty else { return [] }
        guard !text.isEmpty else { return Array(names.prefix(6)) }

        return names.filter { $0.localizedCaseInsensitiveContains(text) }.prefix(6).map { $0 }
    }

    private var feedTitles: [String] {
        sidebar.flatMap { [$0] + $0.children }.compactMap { item in
            if case .feed = item.kind { item.title } else { nil }
        }
    }

    private var folderPaths: [String] {
        sidebar.compactMap { item in
            if case .folder(let path) = item.kind { path } else { nil }
        }
    }

    init(
        database: AppDatabase,
        fetcher: FeedFetcher = FeedFetcher(),
        credentials: CredentialStoring = KeychainCredentials(),
        sessions: SessionStoring = KeychainSessions(),
        preferences: Preferences = Preferences()
    ) {
        self.database = database
        self.credentials = credentials
        self.sessions = sessions
        self.preferences = preferences
        self.articleBody = preferences.articleBody
        self.firstName = preferences.firstName
        self.lastName = preferences.lastName
        self.picture = preferences.picture.flatMap(ProfilePicture.image)
        let subscriptions = SubscriptionStore(database)
        self.subscriptions = subscriptions
        self.articles = ArticleStore(database)
        let library = LibraryStore(database)
        self.library = library
        self.spotlight = SpotlightIndex(library)
        self.digestService = DigestService(database)
        self.refresher = FeedRefresh(database: database, fetcher: fetcher, credentials: credentials)
        self.retention = Retention(database)
        self.finder = FeedFinder(fetcher: fetcher)
        self.opml = OPMLImport(subscriptions)
    }

    /// The fixed views, which every reader has whatever they follow.
    var smartLists: [SidebarItem] {
        sidebar.filter { item in
            switch item.kind {
            case .digest, .unread, .today, .library, .starred, .all: true
            default: false
            }
        }
    }

    /// The folders and the feeds outside them.
    var feedItems: [SidebarItem] {
        sidebar.filter { item in
            switch item.kind {
            case .folder, .feed: true
            default: false
            }
        }
    }

    var filter: ArticleFilter {
        sidebar.flatMap { [$0] + $0.children }.first { $0.kind == selection }?.filter ?? .unread
    }

    /// Whether Flong follows anything at all, which is what the first launch
    /// of section 16 turns on.
    var isEmpty: Bool { feedCount == 0 }

    // MARK: - Loading

    func load() async {
        await loadSidebar()
        await loadArticles()
        await loadCredentials()
        // Another device may have changed them while this one was away.
        preferences.synchronize()
        articleBody = preferences.articleBody
        loadProfile()
        await countOutstandingWork()
    }

    // MARK: - The digest

    /// Which subject the front page is narrowed to, if any.
    var digestTopic = DigestTopic.frontPage {
        didSet {
            guard digestTopic != oldValue else { return }
            Task { await loadDigest() }
        }
    }

    private(set) var digest = Digest()
    /// Whether the model is writing the page again, asked for by the reader.
    private(set) var isRewriting = false
    /// The articles of the story the reader opened, and of that one only : a
    /// digest that loaded every article of every story would be the list it
    /// exists to replace.
    private(set) var storyArticles: [UUID: [ArticleSummary]] = [:]
    private(set) var looseArticles: [ArticleSummary] = []
    var openStory: UUID?

    func loadDigest() async {
        do {
            var fetched = try await digestService.digest(digestTopic)

            // A subject the page no longer has is a page narrowed to nothing,
            // which happens when the last story under it ages out. Falling back
            // to the front page beats an empty page with no way off it.
            if let name = digestTopic.name, !fetched.topics.contains(name) {
                fetched = try await digestService.digest(.frontPage)
                digestTopic = .frontPage
            }
            digest = fetched
        } catch {
            Log.enrich.error("The digest could not be read : \(error, privacy: .public)")
        }
    }

    /// Groups what has arrived, names the new stories, and shows the result.
    /// Groups what has arrived and shows it, then writes the headlines behind.
    ///
    /// The page appears as soon as the grouping is done. Naming is a call to a
    /// model per story, and a page that waited for it would be a page that
    /// arrives a second late to say what it already knew.
    func rebuildDigest() async {
        await digestService.buildStories()
        await loadDigest()
        await loadLooseArticles()

        // The briefs first, then the subjects : the model sorts the page it
        // is shown, and a written headline says what a story is about far
        // better than the title of whichever article was nearest its middle.
        await digestService.brief()
        await digestService.nameTopics()
        await loadDigest()
    }

    /// Every subject there is, for the screen that manages them.
    private(set) var knownTopics: [TopicPreferences.Known] = []

    func loadKnownTopics() async {
        knownTopics = (try? await TopicPreferences(database).known()) ?? []
    }

    /// Sets a subject to a direction rather than to a number : down, nothing,
    /// or up. The pill is where a reader nudges ; this is where they decide.
    func setPreference(of topic: String, to direction: Int) async {
        let preferences = TopicPreferences(database)
        try? await preferences.clear(topic)
        if direction != 0 {
            try? await preferences.adjust(topic, by: direction)
        }

        await loadKnownTopics()
        await loadDigest()
    }

    /// Adds a subject of the reader's own, which the model then files under.
    func addTopic(_ name: String) async {
        try? await TopicPreferences(database).add(name)
        await loadKnownTopics()
    }

    /// Removes a subject the reader wrote, and everything hanging off it.
    func removeTopic(_ name: String) async {
        try? await TopicPreferences(database).remove(name)
        await loadKnownTopics()
        await loadDigest()
    }

    /// Takes back everything the reader has said about every subject.
    func forgetEveryPreference() async {
        try? await TopicPreferences(database).clearAll()
        await loadKnownTopics()
        await loadDigest()
    }

    /// Says the reader wants more of a subject, or less of it.
    ///
    /// The page is read again straight away : a preference nobody can see the
    /// effect of is a preference nobody trusts.
    func prefer(_ topic: String, by delta: Int) async {
        try? await TopicPreferences(database).adjust(topic, by: delta)
        await loadDigest()
        await loadKnownTopics()
    }

    /// Takes back what was said about a subject.
    func forgetPreference(of topic: String) async {
        try? await TopicPreferences(database).clear(topic)
        await loadDigest()
        await loadKnownTopics()
    }

    /// Asks the model to write the page again, whatever it wrote before.
    func rewriteDigest() async {
        guard !isRewriting else { return }
        isRewriting = true
        defer { isRewriting = false }

        await digestService.rewrite()
        await loadDigest()
        await loadLooseArticles()
    }

    /// Loads a story's articles for its own page.
    func openStoryPage(_ storyID: UUID) async {
        guard storyArticles[storyID] == nil else { return }
        storyArticles[storyID] = (try? await digestService.articles(of: storyID)) ?? []
    }

    /// Gives a story back the headline of its own article.
    ///
    /// The assistant is optional : a reader who does not want a written headline
    /// says so once and gets the article's, and the application does not argue.
    func dropGeneratedBrief(of storyID: UUID) async {
        await digestService.dropBrief(of: storyID)
        await loadDigest()
    }

    /// Opens a story, or closes the one that was open.
    func toggle(_ story: DigestStory) async {
        guard openStory != story.id else {
            openStory = nil
            return
        }
        openStory = story.id

        guard storyArticles[story.id] == nil else { return }
        storyArticles[story.id] = (try? await digestService.articles(of: story.id)) ?? []
    }

    /// The articles of the window that made no story.
    func loadLooseArticles() async {
        looseArticles = (try? await digestService.looseArticles()) ?? []
    }

    // MARK: - The long work

    /// Counts what is left to do, so the reader is told rather than left
    /// wondering why an import looks half done.
    func countOutstandingWork() async {
        outstandingFeeds = (try? await FirstFetchJob(database).remaining()) ?? 0
        outstandingVectors = (try? await VectorStore(database).outstandingCount()) ?? 0
    }

    /// Fetches the feeds that have never been fetched, then vectorizes what has
    /// been kept, for as long as it is given.
    ///
    /// Every batch stands alone. Stopping between two of them loses nothing, and
    /// the next run picks up exactly where this one left off, which is what
    /// section 15 means by resumable.
    func doOutstandingWork(until deadline: Date? = nil) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        await JobRunner(FirstFetchJob(database)).run(until: deadline)

        let vectorize = VectorizeJob(database) { [weak self] items in
            // A vector computed here spares every other device the same work.
            await self?.enqueueVectors(for: items)
        }
        await JobRunner(vectorize).run(until: deadline)

        await countOutstandingWork()
        await load()
    }

    /// Starts the long work with the system watching over it.
    ///
    /// On iOS the system is asked to see it through and shows its own progress.
    /// A refusal is not a failure : the work carries on here instead, and again
    /// at the next launch, since it was written to be resumable anyway.
    func finishSetup() async {
        let accepted = BackgroundScheduler.requestContinuedProcessing(
            title: String(localized: "Finishing the setup"),
            subtitle: String(localized: "Fetching your feeds")
        )
        guard !accepted else { return }

        await doOutstandingWork()
    }

    private func enqueueVectors(for items: [LibraryItem]) async {
        await cloud?.enqueue(
            recordNames: items.map { SyncRecords.name(forLibraryItemWithGUID: $0.guid, feedURL: $0.feedURL) }
        )
    }

    /// What a background refresh does with the half minute it is given.
    func backgroundRefresh() async {
        let deadline = Date().addingTimeInterval(BackgroundScheduler.refreshBudget)
        _ = await refresher.refreshDue()
        await JobRunner(FirstFetchJob(database)).run(until: deadline)
        await cloud?.enqueueReadStates()
    }

    /// What a processing task does with the time it is given, on power.
    func backgroundProcessing() async {
        await doOutstandingWork()
        await digestService.rebuild()
        _ = try? await Retention(database).purge()
        try? await SearchIndex(database).optimize()
        await cloud?.enqueueCatchUp()
    }

    /// Starts synchronizing with the reader's own iCloud.
    ///
    /// No account is not an error : Flong is fully usable on one device without
    /// one, and the sidebar says nothing rather than complaining.
    func startSync() async {
        guard cloud == nil else { return }

        let cloud = CloudSync(database: database) { [weak self] status in
            Task { @MainActor [weak self] in self?.syncStatus = status }
        }
        self.cloud = cloud
        await cloud.start()
    }

    /// Sends and fetches now, and folds in whatever arrived.
    func synchronize() async {
        guard let cloud else { return }

        await cloud.enqueueReadStates()
        await cloud.synchronize()
        await load()
    }

    /// Frees what the stream is holding, which is what a full iCloud calls for.
    func purge() async {
        do {
            let summary = try await retention.purge()
            Log.store.notice("Purged \(summary.removed) articles on request")
            await load()
        } catch {
            Log.store.error("The purge failed : \(error, privacy: .public)")
        }
    }

    /// Writes the library to Spotlight when the two have drifted apart.
    ///
    /// Spotlight keeps the record of what it holds, so an index it has lost is
    /// an index Flong writes again, without being told.
    func synchronizeSpotlight() async {
        do {
            try await spotlight.rebuildIfNeeded()
        } catch {
            Log.index.error("The library could not be handed to Spotlight : \(error, privacy: .public)")
        }
    }

    /// Follows what a Spotlight result stands for.
    func open(spotlightIdentifier: String) async {
        guard let id = UUID(uuidString: spotlightIdentifier) else { return }

        selection = .library
        await loadArticles()
        selectedArticle = id
    }

    private func apply(_ change: LibraryChange) async {
        guard !change.isEmpty else { return }

        do {
            try await spotlight.index(change.kept)
            try await spotlight.remove(change.released.map(\.id))
        } catch {
            Log.index.error("Spotlight could not be told about the library : \(error, privacy: .public)")
        }

        // The other devices hear about it on the next exchange, which the
        // engine schedules for itself.
        await cloud?.enqueue(
            recordNames: change.kept.map { SyncRecords.name(forLibraryItemWithGUID: $0.guid, feedURL: $0.feedURL) }
        )
        await cloud?.enqueue(
            deletions: change.released.map { SyncRecords.name(forLibraryItemWithGUID: $0.guid, feedURL: $0.feedURL) }
        )
    }

    func loadSidebar() async {
        do {
            let feeds = try await subscriptions.feeds()
            let counts = try await articles.unreadCounts()

            var items: [SidebarItem] = [
                SidebarItem(kind: .digest, title: nil, unreadCount: 0),
                SidebarItem(kind: .unread, title: nil, unreadCount: try await articles.count(.unread)),
                SidebarItem(kind: .today, title: nil, unreadCount: try await articles.count(.today)),
                SidebarItem(kind: .library, title: nil, unreadCount: 0),
                SidebarItem(kind: .starred, title: nil, unreadCount: 0),
                SidebarItem(kind: .all, title: nil, unreadCount: 0),
            ]

            let grouped = Dictionary(grouping: feeds, by: \.folder)
            let folders = grouped.keys.compactMap { $0 }.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }

            for folder in folders {
                let children = (grouped[folder] ?? []).map { item(for: $0, counts: counts) }
                items.append(
                    SidebarItem(
                        kind: .folder(folder),
                        title: folder,
                        unreadCount: children.reduce(0) { $0 + $1.unreadCount },
                        children: children
                    )
                )
            }
            items += (grouped[nil] ?? []).map { item(for: $0, counts: counts) }

            sidebar = items
            feedCount = feeds.count
        } catch {
            Log.store.error("The sidebar could not be built : \(error, privacy: .public)")
        }
    }

    private func item(for feed: Feed, counts: [UUID: Int]) -> SidebarItem {
        SidebarItem(
            kind: .feed(feed.id),
            title: feed.title,
            unreadCount: counts[feed.id] ?? 0,
            iconURL: feed.iconURL,
            siteURL: feed.siteURL ?? feed.url
        )
    }

    /// Whether the list is showing the library rather than a view of the stream.
    var isShowingLibrary: Bool { selection == .library }

    /// The name of a feed or a folder, for a screen that only has its identity.
    func title(of kind: SidebarItem.Kind) -> String? {
        sidebar.flatMap { [$0] + $0.children }.first { $0.kind == kind }?.title
    }

    func loadArticles() async {
        do {
            summaries =
                isShowingLibrary
                ? try await library.summaries(matching: searchText)
                : try await articles.summaries(filter, matching: query)
            dailyCounts = isShowingLibrary ? [:] : try await articles.dailyCounts(filter, matching: query)
            if let selectedArticle, !summaries.contains(where: { $0.id == selectedArticle }) {
                self.selectedArticle = nil
            }
        } catch {
            Log.store.error("The articles could not be read : \(error, privacy: .public)")
        }
    }

    /// Opens an article, wherever it was tapped.
    func open(article id: UUID) async {
        selectedArticle = id
        await openSelectedArticle()
    }

    private func openSelectedArticle() async {
        guard let selectedArticle else {
            article = nil
            return
        }

        let known = summaries + storyArticles.values.flatMap { $0 } + looseArticles
        let origin = known.first { $0.id == selectedArticle }?.origin ?? .stream

        do {
            switch origin {
            case .library:
                // A kept article was read the day it was kept, and reading it
                // again changes nothing about it.
                article = try await library.article(id: selectedArticle)

            case .stream:
                article = try await articles.article(id: selectedArticle)
                // Opening an article is what marks it read. Nothing waits on
                // anything : the row changes now.
                try await articles.setRead([selectedArticle], to: true)
                await refreshCounts(markingRead: selectedArticle)
            }
        } catch {
            Log.store.error("The article could not be opened : \(error, privacy: .public)")
        }
    }

    /// Goes to the page for an article whose feed gave a summary.
    ///
    /// Only for the article being read, and only once for its life : see
    /// ``FullText``. The reader has the feed's version on screen the whole
    /// time, so a page that never answers costs them nothing but the wait they
    /// were not made to sit through.
    private func fetchFullText(of id: UUID) async {
        guard let opened = article, opened.id == id, !opened.hasFullText,
            FullText.isWorthFetching(url: opened.url, feedHTML: opened.bodyHTML, extractedHTML: nil)
        else { return }

        isFetchingFullText = true
        defer { isFetchingFullText = false }

        guard await FullText(database).extract(id) != nil else { return }

        // The reader may have moved on while the page was being fetched, and
        // an article arriving under a different one is worse than none.
        guard selectedArticle == id else { return }
        article = try? await articles.article(id: id)
    }

    /// Fetches the page for an article the reader asked for by hand.
    func fetchFullText() async {
        guard let id = selectedArticle else { return }
        await fetchFullText(of: id)
    }

    /// Updates what is on screen after a read state changed, without refetching
    /// the whole list.
    private func refreshCounts(markingRead id: UUID?) async {
        guard let id else { return }

        if let index = summaries.firstIndex(where: { $0.id == id }) { summaries[index].isRead = true }
        if let index = looseArticles.firstIndex(where: { $0.id == id }) { looseArticles[index].isRead = true }
        for (story, articles) in storyArticles {
            guard let index = articles.firstIndex(where: { $0.id == id }) else { continue }
            storyArticles[story]?[index].isRead = true
        }

        await loadSidebar()
    }

    // MARK: - Reading

    func toggleRead(_ summary: ArticleSummary) async {
        do {
            try await articles.setRead([summary.id], to: !summary.isRead)
            if let index = summaries.firstIndex(where: { $0.id == summary.id }) {
                summaries[index].isRead = !summary.isRead
            }
            await loadSidebar()
        } catch {
            Log.store.error("The read state could not be changed : \(error, privacy: .public)")
        }
    }

    /// Stars an article, which is what keeps it, or lets go of a kept one.
    func toggleStarred(_ summary: ArticleSummary) async {
        do {
            switch summary.origin {
            case .stream:
                let change = try await library.setStarred([summary.id], to: !summary.isStarred)
                if let index = summaries.firstIndex(where: { $0.id == summary.id }) {
                    summaries[index].isStarred = !summary.isStarred
                }
                await apply(change)
                await loadSidebar()

            case .library:
                await apply(try await library.remove([summary.id]))
                await load()
            }
        } catch {
            Log.store.error("The starred state could not be changed : \(error, privacy: .public)")
        }
    }

    /// Stars or unstars the article being read.
    func toggleStarredCurrent() async {
        guard let article else { return }

        do {
            switch article.origin {
            case .stream:
                let isStarred = !article.isStarred
                await apply(try await library.setStarred([article.id], to: isStarred))

                self.article?.isStarred = isStarred
                if let index = summaries.firstIndex(where: { $0.id == article.id }) {
                    summaries[index].isStarred = isStarred
                }
                await loadSidebar()

            case .library:
                await apply(try await library.remove([article.id]))
                selectedArticle = nil
                await load()
            }
        } catch {
            Log.store.error("The starred state could not be changed : \(error, privacy: .public)")
        }
    }

    /// Puts the article being read back in the unread pile, and closes it.
    ///
    /// A kept article has no unread state to go back to.
    ///
    /// Reading an article marks it read, so the only way this is ever asked for
    /// is deliberately, to come back to it later.
    func markCurrentUnread() async {
        guard let article, article.origin == .stream else { return }

        do {
            try await articles.setRead([article.id], to: false)
            if let index = summaries.firstIndex(where: { $0.id == article.id }) {
                summaries[index].isRead = false
            }
            selectedArticle = nil
            await loadSidebar()
        } catch {
            Log.store.error("The read state could not be changed : \(error, privacy: .public)")
        }
    }

    func markAllRead() async {
        do {
            _ = try await articles.markRead(filter)
            await load()
        } catch {
            Log.store.error("The view could not be marked read : \(error, privacy: .public)")
        }
    }

    // MARK: - Refreshing

    /// Refreshes every feed, which is what a pull means.
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        _ = await refresher.refreshAll()
        _ = try? await retention.purge()
        await digestService.rebuild()
        await cloud?.enqueueReadStates()
        await cloud?.enqueueCatchUp()
        await load()

        // The rebuild wrote new stories, briefs and subjects. Reading the
        // feeds back without reading the page back would leave the reader
        // looking at the page from before the pull.
        await loadDigest()
        await loadLooseArticles()
    }

    /// Refreshes the feeds that are due, on returning to the foreground.
    func refreshDue() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let summary = await refresher.refreshDue()
        guard summary.attempted > 0 else { return }
        await load()
    }

    // MARK: - Subscribing

    /// Follows a feed whose address is itself the secret.
    ///
    /// The address is spent once, here, to find out what the feed is called and
    /// where its site is. What the database keeps is a masked form : the origin
    /// the reader recognizes, and a digest in place of the part that must never
    /// be written down. The real address goes to the keychain, and every
    /// refresh asks for it back.
    func addPrivateFeed(at address: String) async {
        do {
            let url = try FeedURL.canonical(address)
            guard let masked = MaskedURL.mask(url) else {
                failure = .invalidAddress
                return
            }

            let found = try await finder.find(at: url.absoluteString)
            let subscription = try Subscription(
                url: masked,
                title: found.title ?? "",
                siteURL: found.siteURL,
                iconURL: found.iconURL
            )

            let result = try await subscriptions.subscribe(to: subscription)
            try credentials.setCredential(.secretURL(url), for: result.feed.id)

            await cloud?.enqueue(recordNames: [SyncRecords.name(forFeed: result.feed.url)])
            _ = await refresher.refresh(result.feed)
            selection = .feed(result.feed.id)
            await load()
        } catch let error as FeedFinderError {
            switch error {
            case .invalidAddress: failure = .invalidAddress
            case .unreachable: failure = .unreachableFeed
            case .noFeedFound: failure = .noFeedFound
            }
        } catch {
            // Never the address : an error message is one of the places section 9
            // says a secret must not appear.
            failure = .notSaved
        }
    }

    // MARK: - Sites the reader pays for

    /// The site an address belongs to, however the reader spelled it.
    static func site(of address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: withScheme).flatMap(FeedURL.room(of:))
    }

    /// Whether the reader has signed in to the site an address belongs to.
    func hasSession(for url: URL?) -> Bool {
        guard let url else { return false }
        return FullText.session(for: url, in: sessions) != nil
    }

    func loadSubscribedSites() async {
        let hosts = (try? sessions.hosts()) ?? []
        subscribedSites = hosts.compactMap { try? sessions.session(for: $0) }
    }

    /// Keeps the session a site left after the reader signed in.
    ///
    /// Only that site's own cookies : a login page loads a dozen third parties,
    /// and what they left has nothing to do with the reader being a subscriber.
    func saveSession(for host: String, cookies: [HTTPCookie]) async {
        let kept = cookies.compactMap(SessionCookie.init).filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return domain == host || domain.hasSuffix("." + host)
        }

        guard !kept.isEmpty else {
            failure = .notSignedIn
            return
        }

        // Kept under the site the cookies claim rather than the address the
        // reader happened to sign in at, so one sign-in covers every feed and
        // article of the site.
        let site = SiteSession.site(of: kept, signedInAt: host)
        let existing = try? sessions.session(for: site)
        let session = SiteSession(
            host: site,
            cookies: kept,
            signedInAt: Date(),
            // A fresh sign-in has not proved anything yet, and saying it worked
            // a moment ago would be saying something nobody has checked.
            lastWorkedAt: existing?.lastWorkedAt
        )

        try? sessions.setSession(session, for: site)
        // A session that used to sit under a subdomain is replaced by the one
        // that covers the site, rather than left behind to shadow it.
        if site != host { try? sessions.setSession(nil, for: host) }
        await loadSubscribedSites()
    }

    func signOut(of host: String) async {
        try? sessions.setSession(nil, for: host)
        await loadSubscribedSites()
    }

    /// Keeps what a feed needs to prove the reader is entitled to it.
    func setCredential(_ credential: FeedCredential?, for feedID: UUID) async {
        do {
            try credentials.setCredential(credential, for: feedID)
            await loadSidebar()
        } catch {
            failure = .notSaved
        }
    }

    /// Whether a feed has a credential, which is not the same as holding it.
    func hasCredential(_ feedID: UUID) -> Bool {
        authenticatedFeeds.contains(feedID)
    }

    func loadCredentials() async {
        authenticatedFeeds = (try? credentials.identifiers()) ?? []
    }

    func addFeed(at address: String) async {
        do {
            let found = try await finder.find(at: address)
            let subscription = try Subscription(
                url: found.url,
                title: found.title ?? "",
                siteURL: found.siteURL,
                iconURL: found.iconURL
            )
            let result = try await subscriptions.subscribe(to: subscription)
            await cloud?.enqueue(recordNames: [SyncRecords.name(forFeed: result.feed.url)])

            _ = await refresher.refresh(result.feed)
            selection = .feed(result.feed.id)
            await load()
        } catch let error as FeedFinderError {
            switch error {
            case .invalidAddress: failure = .invalidAddress
            case .unreachable: failure = .unreachableFeed
            case .noFeedFound: failure = .noFeedFound
            }
        } catch {
            failure = .notSaved
        }
    }

    func unsubscribe(_ id: UUID) async {
        do {
            let url = try await subscriptions.feed(id: id)?.url
            try await subscriptions.unsubscribe(id)
            if let url { await cloud?.enqueue(deletions: [SyncRecords.name(forFeed: url)]) }
            if case .feed(let selected) = selection, selected == id { selection = .unread }
            await load()
        } catch {
            Log.store.error("The feed could not be removed : \(error, privacy: .public)")
        }
    }

    func importOPML(from url: URL) async {
        do {
            report = try await opml(contentsOf: url)
            await cloud?.enqueueEverything()
            await load()
            await refreshAll()
        } catch let error as OPMLError {
            failure = .notOPML
            Log.store.error("The file is not an OPML document : \(String(describing: error), privacy: .public)")
        } catch let error as CocoaError {
            failure = .unreadableFile
            Log.store.error("The file could not be read : \(error, privacy: .public)")
        } catch {
            failure = .notSaved
            Log.store.error("The import could not be saved : \(error, privacy: .public)")
        }
    }
}
