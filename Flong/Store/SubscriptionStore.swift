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
    /// The address asked for is the one another source is already served at,
    /// and a feed is identified by its address, so the two cannot both have it.
    case addressAlreadyFollowed(UUID)
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

/// What a reader wrote in the editor of one source.
///
/// **Text rather than a `URL` and a `TimeInterval`**, because text is what a
/// reader types. Canonicalizing it is the store's business and happens in one
/// place, under the rules of `docs/technical/feed-identity.md`, so that the
/// editor cannot become a second way of spelling an address.
nonisolated struct SourceEdit: Hashable, Sendable {
    /// What to call it. Empty falls back to the host, as it does everywhere.
    var title: String = ""
    /// Where it is served.
    ///
    /// Empty leaves it exactly where it is, which is what a source whose
    /// address is itself a secret sends : the editor never shows that address,
    /// so it has none to send back.
    var address: String = ""
    /// The site it belongs to, which decides which publisher it files under and
    /// where its icon is looked for. Empty takes it off.
    var siteAddress: String = ""
    /// A manual interval in seconds, or `nil` for the rhythm the feed itself
    /// shows. Bounded by ``RefreshSchedule`` either way.
    var refreshInterval: TimeInterval?
    var isFavourite: Bool = false
    /// Whether every article this source publishes is worth interrupting the
    /// reader for.
    var notifiesNewArticles: Bool = false
    /// Whether this source is one of those the reader offers the others.
    ///
    /// Only ever consulted for a reader who contributes at all, which is a
    /// separate question asked once : see ``Feed/isShared``.
    var isShared: Bool = true
}

/// What editing one source came to, and what has to follow it outside the store.
///
/// The address is the whole of the difficulty. Everything iCloud holds about a
/// source is named after the address it is served at, so a source that moves is
/// a set of records under names nothing has ever written, and another set under
/// names nothing will ever write again.
nonisolated struct SourceChange: Hashable, Sendable {
    /// The source as it now stands.
    let feed: Feed
    /// Where it was served before, and `nil` when the address did not move.
    let previousURL: URL?
    /// The articles the reader had marked under it, whose records are named
    /// after the address they arrived at and have to be written again under the
    /// new one.
    let marked: [Unsubscription.Marked]
    /// The publisher whose name went, when the move was the last source leaving
    /// it.
    let forgottenName: String?

    var movedAddress: Bool { previousURL != nil }
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
    @concurrent
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
    @concurrent
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

    /// Asks to be told about every article one source publishes, or stops
    /// asking.
    ///
    /// It says nothing about the favourite beside it and nothing about the
    /// articles : a source the reader wants near the top of their lists is not
    /// the same as one they want to be interrupted for, and a reader with forty
    /// favourites would otherwise have forty notifications a day.
    func setNotifies(_ id: UUID, _ notifies: Bool) async throws {
        try await update(id) { feed in feed.notifiesNewArticles = notifies }
    }

    /// The sources the reader asked to be told about, in the order a list shows
    /// them.
    func announcing() async throws -> [Feed] {
        try await database.writer.read { db in
            try Feed.filter(Feed.Columns.notifiesNewArticles == true).orderedByTitle().fetchAll(db)
        }
    }

    /// Edits one source : its name, its address, the site it belongs to, how
    /// often it is asked and whether it is one of the reader's own.
    ///
    /// **One transaction, because the address drags the rest along.** A source
    /// that moves takes with it the marks still waiting under the old address,
    /// the conditional state that belonged to the old server and, when it was
    /// the last source of its publisher, the name the reader had written over
    /// that publisher. A half-applied edit would leave a row pointing at an
    /// address nothing else in the store agrees with.
    ///
    /// **Every field is written**, so a caller sends the whole of what the
    /// reader was looking at rather than the part they touched. An editor is a
    /// screen showing a state, and a partial edit would be a screen that half
    /// remembers.
    ///
    /// What comes back is what the window has to carry outside the store :
    /// iCloud names every record after the address, and Spotlight holds the
    /// name of the publisher on every article of it.
    @discardableResult
    func edit(_ id: UUID, to edited: SourceEdit) async throws -> SourceChange {
        let address = edited.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let asked = address.isEmpty ? nil : try FeedURL.canonical(address)

        let site = edited.siteAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let siteURL = site.isEmpty ? nil : try FeedURL.canonical(site)

        return try await database.writer.write { db in
            guard var feed = try Feed.fetchOne(db, key: id) else { throw SubscriptionError.unknownFeed(id) }
            let publisher = feed.domain

            var moved: URL?
            if let asked { moved = try Self.move(&feed, to: asked, in: db) }

            let title = edited.title.trimmingCharacters(in: .whitespacesAndNewlines)
            feed.title = title.isEmpty ? Subscription.fallbackTitle(for: feed.url) : title
            feed.siteURL = siteURL
            feed.refreshInterval = edited.refreshInterval.map(Self.bounded)
            feed.isFavourite = edited.isFavourite
            feed.notifiesNewArticles = edited.notifiesNewArticles
            feed.isShared = edited.isShared
            try feed.update(db)

            return SourceChange(
                feed: feed,
                previousURL: moved,
                // Only when the address moved. They are here to be named again
                // in the reader's iCloud, and nothing else about a source
                // changes what its marks are called.
                marked: moved == nil ? [] : try Self.marked(ofFeed: feed.id, in: db),
                forgottenName: publisher == feed.domain ? nil : try Self.forgetName(ofEmptied: publisher, in: db)
            )
        }
    }

    /// Moves a source to the address another device says it is served at now.
    ///
    /// **The whole point is that the row is moved rather than replaced.** A
    /// source that moved arrives as a record under a name this device has never
    /// seen and a deletion of the one it knows, and taking those at face value
    /// would delete the articles, the stars, the notes and the filings of a
    /// source that has not gone anywhere.
    ///
    /// `nil`, and nothing done, when there is nothing here at the old address,
    /// or when something is already at the new one. Both mean this device has
    /// already followed the move or never knew the source, and neither is an
    /// error : records are replayed, and a second application has to change
    /// nothing.
    @discardableResult
    func readdress(from previous: URL, to url: URL) async throws -> SourceChange? {
        try await database.writer.write { db in
            guard var feed = try Feed.filter(Feed.Columns.url == previous).fetchOne(db),
                try Feed.filter(Feed.Columns.url == url).fetchOne(db) == nil
            else { return nil }

            let publisher = feed.domain
            guard let moved = try Self.move(&feed, to: url, in: db) else { return nil }
            try feed.update(db)

            return SourceChange(
                feed: feed,
                previousURL: moved,
                marked: try Self.marked(ofFeed: feed.id, in: db),
                forgottenName: publisher == feed.domain ? nil : try Self.forgetName(ofEmptied: publisher, in: db)
            )
        }
    }

    /// Takes on what another device decided about a source already followed.
    ///
    /// **The upsert completes a feed and never overwrites it, which is right
    /// for an import and wrong for what arrives from iCloud.** A name the
    /// reader wrote on their iPad, a site they corrected and a source they
    /// singled out are decisions, and a decision that did not travel is one
    /// they made and then watched disappear on the next device they picked up.
    /// Asking to be told about a source is the same kind of thing : the reader
    /// asked about the publisher, not about the device they happened to be
    /// holding.
    ///
    /// A field the record does not state is not a decision to unset it. An
    /// older record carries no favourite, no notification and may carry no
    /// site, and nothing said is not the same as `no`.
    @discardableResult
    func adopt(
        _ subscription: Subscription,
        isFavourite: Bool?,
        notifies: Bool? = nil,
        at id: UUID
    ) async throws -> Bool {
        try await database.writer.write { db in
            guard var feed = try Feed.fetchOne(db, key: id) else { throw SubscriptionError.unknownFeed(id) }
            var changed = false

            if feed.title != subscription.title {
                feed.title = subscription.title
                changed = true
            }
            if let site = subscription.siteURL, feed.siteURL != site {
                feed.siteURL = site
                changed = true
            }
            if let icon = subscription.iconURL, feed.iconURL != icon {
                feed.iconURL = icon
                changed = true
            }
            if let isFavourite, feed.isFavourite != isFavourite {
                feed.isFavourite = isFavourite
                changed = true
            }
            if let notifies, feed.notifiesNewArticles != notifies {
                feed.notifiesNewArticles = notifies
                changed = true
            }

            guard changed else { return false }
            try feed.update(db)
            return true
        }
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
        let marked = try Self.marked(ofFeed: feed.id, in: db)

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
        let forgotName = try Self.forgetName(ofEmptied: feed.domain, in: db) != nil

        return Unsubscription(feed: feed, marked: marked, forgotName: forgotName)
    }

    /// Puts a source at another address, with everything that was named after
    /// the old one.
    ///
    /// Answers with the address it came from, or `nil` when it was already
    /// there, so that a caller can tell an edit that moved a source from one
    /// that only renamed it.
    private static func move(_ feed: inout Feed, to url: URL, in db: Database) throws -> URL? {
        guard url != feed.url else { return nil }

        if let other = try Feed.filter(Feed.Columns.url == url).fetchOne(db), other.id != feed.id {
            throw SubscriptionError.addressAlreadyFollowed(other.id)
        }

        let previous = feed.url

        // A mark that arrived before its article is keyed by the address it
        // arrived under, which is the only thing it has to find its article by.
        // Left where it was, it would wait for ever on an address nothing is
        // going to ask for again. `OR REPLACE` because one may already be
        // waiting under the new address, and two marks for one article is one
        // mark : the one that has been waiting is the one that named the
        // article correctly at the time.
        try db.execute(
            sql: "UPDATE OR REPLACE pending_mark SET feed_url = ? WHERE feed_url = ?",
            arguments: [url.absoluteString, previous.absoluteString]
        )

        feed.previousURL = previous
        feed.url = url

        // **The conditional state belongs to the address and not to the
        // source.** An `ETag` replayed at a server that never issued it is a
        // question about somebody else's file, and the `304` it may well answer
        // with would keep the new address empty for as long as the reader
        // waited. The health record goes with it, since a 304 rate mixing two
        // servers' answers measures neither, and so do the failures : a reader
        // who edits an address is usually repairing a source that had stopped
        // answering, and the quarantine is exactly what they are undoing.
        feed.etag = nil
        feed.lastModified = nil
        feed.fetchCount = 0
        feed.notModifiedCount = 0
        feed.failureCount = 0
        feed.lastFailureReason = nil
        feed.lastFetchAt = nil
        feed.lastSuccessAt = nil
        feed.quarantinedAt = nil

        return previous
    }

    /// The articles of one source the reader had said something about.
    private static func marked(ofFeed id: UUID, in db: Database) throws -> [Unsubscription.Marked] {
        try Row.fetchAll(
            db,
            sql: "SELECT id, guid FROM entry WHERE feed_id = ? AND \(Retention.marked)",
            arguments: [id]
        )
        .map { Unsubscription.Marked(id: $0["id"], guid: $0["guid"]) }
    }

    /// Takes the name off a publisher nothing is followed from any more.
    ///
    /// A group is worked out from the addresses of its feeds and never survives
    /// them, so a name left behind would be a row nothing can reach : not shown
    /// anywhere, not editable anywhere, and silently reappearing over the group
    /// if the reader ever came back to that publisher.
    ///
    /// Answers with the domain whose name went, so that the caller knows there
    /// is a record of it to delete.
    private static func forgetName(ofEmptied domain: String, in db: Database) throws -> String? {
        guard try !Feed.fetchAll(db).contains(where: { $0.domain == domain }) else { return nil }
        guard try SourceName.filter(SourceName.Columns.domain == domain).deleteAll(db) > 0 else { return nil }
        return domain
    }

    /// A manual interval, held inside the bounds section 8 sets for every feed.
    ///
    /// The editor offers a handful of intervals that are all inside them, so
    /// this is for what arrives from anywhere else.
    private static func bounded(_ interval: TimeInterval) -> TimeInterval {
        min(max(interval, RefreshSchedule.minimumInterval), RefreshSchedule.maximumInterval)
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
