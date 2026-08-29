//
//  SubscriptionStore.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB

/// Why a subscription operation could not be carried out.
nonisolated enum SubscriptionError: Error, Hashable, Sendable {
    case unknownFeed(UUID)
}

/// A folder, as the sidebar needs it.
nonisolated struct Folder: Identifiable, Hashable, Sendable {
    /// The full path, `Tech/iOS`.
    let path: String
    /// How many feeds sit in this exact folder, subfolders excluded.
    let feedCount: Int

    var id: String { path }
    var name: String { FolderPath.name(of: path) }
    var depth: Int { FolderPath.components(of: path).count }
}

/// What became of one subscription request.
nonisolated struct SubscriptionResult: Hashable, Sendable {
    let feed: Feed
    /// `false` when Flong was already following that URL.
    let isNew: Bool
}

/// The subscriptions : which feeds Flong follows, how they are called and where
/// they sit.
///
/// Every write goes through one transaction, so an import of a thousand feeds
/// either lands whole or not at all.
nonisolated struct SubscriptionStore: Sendable {
    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    // MARK: - Reading

    /// Every followed feed, in the order a list shows them.
    ///
    /// Sorting happens in SQLite through the localized collation, so `Écrans`
    /// files under E rather than after Z.
    func feeds() async throws -> [Feed] {
        try await database.writer.read { db in
            try Feed.all().orderedByTitle().fetchAll(db)
        }
    }

    /// The feeds sitting in one exact folder, or outside any folder for `nil`.
    func feeds(inFolder folder: String?) async throws -> [Feed] {
        let folder = FolderPath.normalized(folder)
        return try await database.writer.read { db in
            try Feed.filter(Feed.Columns.folder == folder).orderedByTitle().fetchAll(db)
        }
    }

    func feed(id: UUID) async throws -> Feed? {
        try await database.writer.read { db in try Feed.fetchOne(db, key: id) }
    }

    /// The feed followed at that address, whichever way the address is spelled.
    func feed(at address: String) async throws -> Feed? {
        let url = try FeedURL.canonical(address)
        return try await database.writer.read { db in
            try Feed.filter(Feed.Columns.url == url).fetchOne(db)
        }
    }

    func count() async throws -> Int {
        try await database.writer.read { db in try Feed.fetchCount(db) }
    }

    /// Every folder, including the ones no feed sits in directly.
    ///
    /// A feed in `Tech/iOS` implies `Tech`, which the sidebar has to draw even
    /// though nothing is filed there. `feedCount` stays the direct count.
    func folders() async throws -> [Folder] {
        let stored = try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT folder, COUNT(*) AS count FROM feed WHERE folder IS NOT NULL GROUP BY folder"
            )
            .map { (path: $0["folder"] as String, count: $0["count"] as Int) }
        }

        var counts: [String: Int] = [:]
        for folder in stored {
            counts[folder.path, default: 0] += folder.count
            for ancestor in FolderPath.ancestors(of: folder.path) where counts[ancestor] == nil {
                counts[ancestor] = 0
            }
        }

        return
            counts
            .map { Folder(path: $0.key, feedCount: $0.value) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: - Subscribing

    /// Follows a feed, or returns the one already followed at that address.
    @discardableResult
    func subscribe(to subscription: Subscription) async throws -> SubscriptionResult {
        try await database.writer.write { db in try Self.upsert(subscription, in: db) }
    }

    /// Follows a batch of feeds in one transaction, which is what an import needs.
    ///
    /// Results come back in the order they were asked for, so a caller can pair
    /// them with what it read from its file.
    @discardableResult
    func subscribe(to subscriptions: [Subscription]) async throws -> [SubscriptionResult] {
        try await database.writer.write { db in
            try subscriptions.map { try Self.upsert($0, in: db) }
        }
    }

    /// Adds a feed, or completes the one already there.
    ///
    /// An address already followed never overwrites what is stored : a title the
    /// user changed, or a folder they moved the feed to, outranks whatever a
    /// re-import carries. Only fields still empty are filled in.
    private static func upsert(_ subscription: Subscription, in db: Database) throws -> SubscriptionResult {
        if var feed = try Feed.filter(Feed.Columns.url == subscription.url).fetchOne(db) {
            var changed = false

            if feed.siteURL == nil, subscription.siteURL != nil {
                feed.siteURL = subscription.siteURL
                changed = true
            }
            if feed.iconURL == nil, subscription.iconURL != nil {
                feed.iconURL = subscription.iconURL
                changed = true
            }
            if feed.folder == nil, subscription.folder != nil {
                feed.folder = subscription.folder
                changed = true
            }

            if changed {
                try feed.update(db)
            }
            return SubscriptionResult(feed: feed, isNew: false)
        }

        let feed = Feed(
            url: subscription.url,
            siteURL: subscription.siteURL,
            iconURL: subscription.iconURL,
            title: subscription.title,
            folder: subscription.folder
        )
        try feed.insert(db)
        return SubscriptionResult(feed: feed, isNew: true)
    }

    // MARK: - Editing

    /// Renames a feed. An empty title falls back to the host.
    func rename(_ id: UUID, to title: String) async throws {
        try await update(id) { feed in
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            feed.title = title.isEmpty ? Subscription.fallbackTitle(for: feed.url) : title
        }
    }

    /// Moves a feed to another folder, or out of every folder for `nil`.
    func move(_ id: UUID, toFolder folder: String?) async throws {
        let folder = FolderPath.normalized(folder)
        try await update(id) { feed in feed.folder = folder }
    }

    /// Stops following a feed, which takes its articles and their bodies with it.
    func unsubscribe(_ id: UUID) async throws {
        let deleted = try await database.writer.write { db in
            try Feed.deleteOne(db, key: id)
        }
        guard deleted else { throw SubscriptionError.unknownFeed(id) }
    }

    private func update(_ id: UUID, _ change: @escaping @Sendable (inout Feed) -> Void) async throws {
        try await database.writer.write { db in
            guard var feed = try Feed.fetchOne(db, key: id) else { throw SubscriptionError.unknownFeed(id) }
            change(&feed)
            try feed.update(db)
        }
    }

    // MARK: - Folders

    /// Renames a folder and every folder below it.
    ///
    /// Renaming `Tech` to `Veille` moves `Tech/iOS` to `Veille/iOS` too : a
    /// folder is a path, and a path that no longer starts the same way would
    /// leave its children orphaned.
    @discardableResult
    func renameFolder(_ folder: String, to newFolder: String?) async throws -> Int {
        guard let source = FolderPath.normalized(folder) else { return 0 }
        let destination = FolderPath.normalized(newFolder)

        return try await database.writer.write { db in
            let feeds = try Feed.filter(Feed.Columns.folder != nil).fetchAll(db)
            var moved = 0

            for var feed in feeds {
                guard let current = feed.folder, Self.folder(current, isInside: source) else { continue }

                let suffix = FolderPath.components(of: current).dropFirst(FolderPath.components(of: source).count)
                feed.folder = FolderPath.normalized(([destination].compactMap { $0 } + suffix).joined(separator: "/"))
                try feed.update(db)
                moved += 1
            }
            return moved
        }
    }

    /// Removes a folder.
    ///
    /// A folder holds nothing of its own, so removing one never removes a feed :
    /// what sat directly in it moves outside every folder, and a subfolder
    /// floats up one level with its feeds.
    @discardableResult
    func removeFolder(_ folder: String) async throws -> Int {
        try await renameFolder(folder, to: nil)
    }

    /// Whether a path is that folder or sits below it.
    private static func folder(_ path: String, isInside folder: String) -> Bool {
        path == folder || path.hasPrefix(folder + String(FolderPath.separator))
    }
}
