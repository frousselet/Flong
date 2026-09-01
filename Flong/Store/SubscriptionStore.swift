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

/// What went with a source, and what is left to take away elsewhere.
///
/// The store empties itself : the articles, their bodies, their rows of the
/// index, their place in a story and their filings all go with the feed. Three
/// things it cannot reach go with them, and this is what the window needs in
/// order to reach them : the secret in the keychain, the marked articles
/// Spotlight is holding, and the records the reader's iCloud has for the
/// subscription and for what they marked under it.
nonisolated struct Unsubscription: Hashable, Sendable {
    /// One article the reader had said something about.
    ///
    /// Its identifier is what Spotlight files it under, and its GUID is half of
    /// what names its record, the other half being the address of the feed.
    nonisolated struct Marked: Hashable, Sendable {
        let id: UUID
        let guid: String
    }

    /// The source as it was, which nothing can be read back from now.
    let feed: Feed
    /// The articles of it the reader had starred, written on or filed.
    let marked: [Marked]
    /// Whether the name the reader had written over the publisher went too,
    /// which happens when this was the last of its sources.
    let forgotName: Bool
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

    /// What each publisher is called and the mark it wears, by domain.
    ///
    /// One entry per group, which is the whole point : it is what lets a paper
    /// with six feeds be one name and one favicon everywhere it is shown.
    func identities() async throws -> [String: SourceIdentity] {
        Dictionary(try await groups().map { ($0.domain, $0.identity) }, uniquingKeysWith: { first, _ in first })
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

    /// Stops following a source and takes everything it brought with it.
    ///
    /// **One transaction, so a source never half goes.** Most of what a feed
    /// owns leaves on the foreign keys : the articles, their bodies, their
    /// place in a story and, through the triggers of the schema, their rows of
    /// the full-text index. What is done by hand here is the four things no key
    /// reaches, and every one of them would otherwise be a row pointing at
    /// something that no longer exists.
    @discardableResult
    func unsubscribe(_ id: UUID) async throws -> Unsubscription {
        try await database.writer.write { db in
            guard let feed = try Feed.fetchOne(db, key: id) else { throw SubscriptionError.unknownFeed(id) }
            return try Self.remove(feed, in: db)
        }
    }

    /// Stops following every source of one publisher.
    ///
    /// A group is the address its sources share and is not a row, so removing
    /// one is removing its sources : there is nothing else of it to delete, and
    /// the heading goes because the last thing under it did. In one
    /// transaction, since a publisher half removed is a heading over the desks
    /// that happened to fail.
    @discardableResult
    func unsubscribe(fromPublisher domain: String) async throws -> [Unsubscription] {
        try await database.writer.write { db in
            try Feed.all().orderedByTitle().fetchAll(db)
                .filter { $0.domain == domain }
                .map { try Self.remove($0, in: db) }
        }
    }

    /// Takes one source away, and everything that was only there because of it.
    private static func remove(_ feed: Feed, in db: Database) throws -> Unsubscription {
        // Read before anything is deleted : this is what the window has to take
        // out of Spotlight and out of the reader's iCloud, and in a moment
        // there will be nothing left to read it from.
        let marked = try Row.fetchAll(
            db,
            sql: "SELECT id, guid FROM entry WHERE feed_id = ? AND \(Retention.marked)",
            arguments: [feed.id]
        )
        .map { Unsubscription.Marked(id: $0["id"], guid: $0["guid"]) }

        // A filing carries no foreign key, since it points at one of three
        // tables, so nothing takes it away with the article it names. Left
        // behind it is a row of a collection standing for an article that has
        // gone, which every count of that collection then has to step over.
        try db.execute(
            sql: """
                DELETE FROM tag_binding
                WHERE target_kind = ? AND target_id IN (SELECT id FROM entry WHERE feed_id = ?)
                """,
            arguments: [CollectionStore.targetKind, feed.id]
        )

        // A mark waiting for an article that is never going to arrive now. It
        // is keyed by the address of the feed rather than by a row of it, which
        // is the whole point of it, and so no key reaches it either.
        try db.execute(
            sql: "DELETE FROM pending_mark WHERE feed_url = ?",
            arguments: [feed.url.absoluteString]
        )

        // The source itself, and with it the articles and everything keyed on
        // them.
        try feed.delete(db)

        // A story is several rooms covering one event. Take a room away and
        // some of them are one article, or none, and a front page would go on
        // showing a headline over nothing.
        try StoryBuilder.removeEmptyStories(in: db)

        // The name the reader wrote over the publisher, when this was the last
        // source under it. A group is worked out from the addresses of the
        // feeds and never survives them, so a name left here would be a row
        // nothing can reach : not shown anywhere, not editable anywhere, and
        // silently reappearing over the group if the reader ever subscribes to
        // that publisher again.
        let stillFollowed = try Feed.fetchAll(db).contains { $0.domain == feed.domain }
        let forgotName =
            try !stillFollowed
            && SourceName.filter(SourceName.Columns.domain == feed.domain).deleteAll(db) > 0

        return Unsubscription(feed: feed, marked: marked, forgotName: forgotName)
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
