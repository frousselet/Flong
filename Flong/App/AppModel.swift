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

import Foundation
import OSLog

/// An entry of the sidebar.
struct SidebarItem: Identifiable, Hashable {
    /// What an entry stands for. It is also the selection, so it holds nothing
    /// that changes when a feed is renamed.
    enum Kind: Hashable {
        case unread, today, library, starred, all
        case folder(String)
        case feed(UUID)
    }

    let kind: Kind
    /// The name of a folder or a feed. Smart lists are named by the interface,
    /// in the reader's language.
    let title: String?
    let unreadCount: Int
    var children: [SidebarItem] = []

    var id: Kind { kind }

    var filter: ArticleFilter {
        switch kind {
        case .unread: .unread
        case .today: .today
        case .starred: .starred
        // The library is not a view over the stream : it is its own table, and
        // the list reads it directly.
        case .library, .all: .all
        case .folder(let path): .folder(path)
        case .feed(let id): .feed(id)
        }
    }
}

/// Why something the reader asked for did not happen.
enum AppFailure: Hashable, Identifiable {
    case unreadableFile
    case notOPML
    case notSaved
    case invalidAddress
    case unreachableFeed
    case noFeedFound

    var id: Self { self }

    var message: LocalizedStringResource {
        switch self {
        case .unreadableFile: "This file could not be opened."
        case .notOPML: "This file could not be read as OPML."
        case .notSaved: "The subscriptions could not be saved."
        case .invalidAddress: "This address is not one Flong can follow."
        case .unreachableFeed: "This address could not be reached."
        case .noFeedFound: "No feed was found at this address."
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
    private var cloud: CloudSync?
    private let refresher: FeedRefresh
    private let retention: Retention
    private let finder: FeedFinder
    private let opml: OPMLImport

    private(set) var sidebar: [SidebarItem] = []
    private(set) var summaries: [ArticleSummary] = []
    private(set) var article: Article?
    private(set) var isRefreshing = false
    private(set) var feedCount = 0

    /// What synchronization is doing, in terms the sidebar can show.
    private(set) var syncStatus = SyncStatus.idle(lastSynchronized: nil)

    /// Whether the list is showing the answer to a query rather than a view.
    var isShowingResults: Bool { query != nil }

    var selection: SidebarItem.Kind? = .unread {
        didSet { Task { await loadArticles() } }
    }
    var selectedArticle: UUID? {
        didSet { Task { await openSelectedArticle() } }
    }

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

    init(database: AppDatabase, fetcher: FeedFetcher = FeedFetcher()) {
        self.database = database
        let subscriptions = SubscriptionStore(database)
        self.subscriptions = subscriptions
        self.articles = ArticleStore(database)
        let library = LibraryStore(database)
        self.library = library
        self.spotlight = SpotlightIndex(library)
        self.refresher = FeedRefresh(database: database, fetcher: fetcher)
        self.retention = Retention(database)
        self.finder = FeedFinder(fetcher: fetcher)
        self.opml = OPMLImport(subscriptions)
    }

    /// The fixed views, which every reader has whatever they follow.
    var smartLists: [SidebarItem] {
        sidebar.filter { item in
            switch item.kind {
            case .unread, .today, .library, .starred, .all: true
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
        SidebarItem(kind: .feed(feed.id), title: feed.title, unreadCount: counts[feed.id] ?? 0)
    }

    /// Whether the list is showing the library rather than a view of the stream.
    var isShowingLibrary: Bool { selection == .library }

    func loadArticles() async {
        do {
            summaries =
                isShowingLibrary
                ? try await library.summaries(matching: searchText)
                : try await articles.summaries(filter, matching: query)
            if let selectedArticle, !summaries.contains(where: { $0.id == selectedArticle }) {
                self.selectedArticle = nil
            }
        } catch {
            Log.store.error("The articles could not be read : \(error, privacy: .public)")
        }
    }

    private func openSelectedArticle() async {
        guard let selectedArticle else {
            article = nil
            return
        }

        let origin = summaries.first { $0.id == selectedArticle }?.origin ?? .stream

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

    /// Updates what is on screen after a read state changed, without refetching
    /// the whole list.
    private func refreshCounts(markingRead id: UUID?) async {
        if let id, let index = summaries.firstIndex(where: { $0.id == id }), !summaries[index].isRead {
            summaries[index].isRead = true
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
        await cloud?.enqueueReadStates()
        await cloud?.enqueueCatchUp()
        await load()
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
