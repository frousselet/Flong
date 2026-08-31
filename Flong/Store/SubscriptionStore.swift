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

/// What became of one subscription request.
nonisolated struct SubscriptionResult: Hashable, Sendable {
    let feed: Feed
    /// `false` when Flong was already following that URL.
    let isNew: Bool
}

/// The subscriptions : which feeds Flong follows, how they are called and which
/// publisher they belong to.
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

    /// Every publisher followed, with the sources it serves.
    ///
    /// The grouping is worked out here rather than stored : a group is the
    /// address its feeds share, so there is never a group without feeds and
    /// never a feed without a group. Only the names the reader wrote are read
    /// back off the disk.
    func groups() async throws -> [SourceGroup] {
        let (feeds, names) = try await database.writer.read { db in
            (try Feed.all().orderedByTitle().fetchAll(db), try SourceName.fetchAll(db))
        }
        return Self.groups(of: feeds, named: names)
    }

    /// The names the reader wrote, which is all a group ever stores.
    func names() async throws -> [SourceName] {
        try await database.writer.read { db in
            try SourceName.order(SourceName.Columns.domain).fetchAll(db)
        }
    }

    func name(ofDomain domain: String) async throws -> SourceName? {
        try await database.writer.read { db in
            try SourceName.filter(SourceName.Columns.domain == domain).fetchOne(db)
        }
    }

    /// The groups a set of feeds falls into, in the order a list shows them.
    static func groups(of feeds: [Feed], named names: [SourceName]) -> [SourceGroup] {
        let written = Dictionary(names.map { ($0.domain, $0.name) }, uniquingKeysWith: { first, _ in first })

        return Dictionary(grouping: feeds, by: \.domain)
            .map { SourceGroup(domain: $0.key, name: written[$0.key], feeds: $0.value) }
            .sorted(by: SourceGroup.before)
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
    /// user changed outranks whatever a re-import carries, and so does the
    /// group they named it into. Only fields still empty are filled in.
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

            if changed {
                try feed.update(db)
            }
            return SubscriptionResult(feed: feed, isNew: false)
        }

        let feed = Feed(
            url: subscription.url,
            siteURL: subscription.siteURL,
            iconURL: subscription.iconURL,
            title: subscription.title
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

    /// Singles a source out, or stops.
    ///
    /// It says nothing whatever about the articles underneath : section 13 of
    /// the specification keeps the star an article wears a judgement about that
    /// article, and this is a judgement about the publisher.
    func setFavourite(_ id: UUID, _ isFavourite: Bool) async throws {
        try await update(id) { feed in feed.isFavourite = isFavourite }
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

    // MARK: - Groups

    /// Names a publisher, or takes the name back off it.
    ///
    /// **A group is never created and never removed**, so this writes the one
    /// thing about it that is not already known. An empty name, or the address
    /// written out again, is not a name : the row goes and the group is called
    /// what it is, which is what lets a reader undo a renaming without having
    /// to remember what the address was.
    ///
    /// The sources do not move. A group is where a feed already is, not
    /// somewhere it was put.
    @discardableResult
    func rename(domain: String, to raw: String?, at date: Date = Date()) async throws -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = (trimmed?.isEmpty == false && trimmed != domain) ? trimmed : nil

        try await database.writer.write { db in
            guard let kept else {
                _ = try SourceName.filter(SourceName.Columns.domain == domain).deleteAll(db)
                return
            }

            if var written = try SourceName.filter(SourceName.Columns.domain == domain).fetchOne(db) {
                written.name = kept
                try written.update(db)
            } else {
                try SourceName(domain: domain, name: kept, createdAt: date).insert(db)
            }
        }
        return kept
    }
}
