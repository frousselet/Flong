//
//  FeedRefresh.swift
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
import OSLog

/// What one feed's refresh came to.
nonisolated enum RefreshResult: Hashable, Sendable {
    case updated(newArticles: Int)
    case notModified
    case failed(reason: String)
    /// Not due yet, or quarantined.
    case skipped
}

/// What a whole refresh came to.
nonisolated struct RefreshSummary: Hashable, Sendable {
    var refreshed = 0
    var unchanged = 0
    var failed = 0
    var newArticles = 0

    var attempted: Int { refreshed + unchanged + failed }
}

/// Fetches feeds, reads them, and writes what they hold into the store.
///
/// This is where the four modules meet : the fetcher brings bytes, the parser
/// turns them into articles, the sanitizer decides what of an article may be
/// kept, and the store recognizes what it has already seen.
nonisolated struct FeedRefresh: Sendable {
    /// How many feeds are fetched at once.
    ///
    /// The throttle already spaces out one host ; this bounds the work in
    /// flight, which is what keeps memory flat on a phone refreshing a thousand
    /// feeds.
    static let concurrency = 6

    /// Consecutive failures before a feed stops being asked for.
    ///
    /// Credentials that no longer work, or a feed that is gone, are settled
    /// after three, per section 9. Anything that might be an outage gets six.
    static let quarantineAfterRejection = 3
    static let quarantineAfterFailure = 6

    private let database: AppDatabase
    private let fetcher: FeedFetcher
    private let readStates: ReadStateStore

    init(database: AppDatabase, fetcher: FeedFetcher = FeedFetcher()) {
        self.database = database
        self.fetcher = fetcher
        self.readStates = ReadStateStore(database)
    }

    // MARK: - Refreshing

    /// Refreshes every feed that is due.
    func refreshDue(now: Date = Date()) async -> RefreshSummary {
        let device = DeviceStagger.deviceIdentifier()
        let feeds = (try? await allFeeds()) ?? []

        let due = feeds.filter { feed in
            let interval = feed.refreshInterval ?? feed.observedInterval ?? RefreshSchedule.defaultInterval
            let stagger = DeviceStagger.offset(for: feed.id, interval: interval, device: device)
            return RefreshSchedule.isDue(feed, now: now, stagger: stagger)
        }

        return await refresh(due)
    }

    /// Refreshes every feed, due or not, which is what a pull to refresh means.
    func refreshAll() async -> RefreshSummary {
        let feeds = (try? await allFeeds()) ?? []
        return await refresh(feeds.filter { $0.quarantinedAt == nil })
    }

    func refresh(_ feeds: [Feed]) async -> RefreshSummary {
        guard !feeds.isEmpty else { return RefreshSummary() }

        return await withTaskGroup(of: RefreshResult.self) { group in
            var iterator = feeds.makeIterator()
            var running = 0

            while running < Self.concurrency, let feed = iterator.next() {
                group.addTask { await refresh(feed) }
                running += 1
            }

            var summary = RefreshSummary()
            for await result in group {
                summary.add(result)
                if let feed = iterator.next() {
                    group.addTask { await refresh(feed) }
                }
            }
            return summary
        }
    }

    /// Refreshes one feed, and writes down what happened either way.
    @discardableResult
    func refresh(_ feed: Feed) async -> RefreshResult {
        let request = FetchRequest(url: feed.url, etag: feed.etag, lastModified: feed.lastModified)

        switch await fetcher.fetch(request) {
        case .notModified:
            try? await recordSuccess(feed, notModified: true)
            return .notModified

        case .failed(let failure):
            try? await recordFailure(feed, failure: failure)
            return .failed(reason: Self.reason(for: failure))

        case .updated(let document):
            do {
                let parsed = try FeedParser.parse(document.data, url: document.url, contentType: document.contentType)
                // An article fetched today may have been read on another device
                // last week, and has to land read rather than announce itself.
                let read = (try? await readStates.fingerprints()) ?? []
                let new = try await store(parsed, from: document, into: feed, read: read)
                return .updated(newArticles: new)
            } catch {
                // Bytes arrived and made no sense. That is the publisher's
                // problem to fix, and the feed's health has to show it.
                try? await recordFailure(feed, failure: .unreachable, reason: "unreadable")
                return .failed(reason: "unreadable")
            }
        }
    }

    // MARK: - Storing

    private func allFeeds() async throws -> [Feed] {
        try await database.writer.read { db in try Feed.fetchAll(db) }
    }

    /// Writes a parsed feed and its articles down, in one transaction.
    private func store(
        _ parsed: ParsedFeed,
        from document: FetchedDocument,
        into feed: Feed,
        read: Set<ArticleFingerprint>
    ) async throws -> Int {
        let now = Date()

        return try await database.writer.write { db in
            guard var stored = try Feed.fetchOne(db, key: feed.id) else { return 0 }

            // A feed names itself only while nothing else has named it. A title
            // that came from an OPML file is already somebody's choice, and a
            // rename certainly is ; neither is overwritten by a refresh.
            let isUnnamed = stored.title.isEmpty || stored.title == Subscription.fallbackTitle(for: stored.url)
            if isUnnamed, let title = parsed.title, !title.isEmpty {
                stored.title = title
            }
            if stored.siteURL == nil { stored.siteURL = parsed.siteURL }
            if stored.iconURL == nil { stored.iconURL = parsed.iconURL }
            if stored.language == nil { stored.language = parsed.language }

            stored.etag = document.etag
            stored.lastModified = document.lastModified
            stored.fetchCount += 1
            stored.lastFetchAt = now
            stored.lastSuccessAt = now
            stored.failureCount = 0
            stored.lastFailureReason = nil
            stored.quarantinedAt = nil

            var newArticles = 0
            for item in parsed.items {
                if try Self.store(item, of: parsed, feed: stored, at: now, read: read, in: db) { newArticles += 1 }
            }

            // The interval a feed suggests is read from what it just served,
            // which is the only history that is certain to be complete.
            let dates = parsed.items.compactMap(\.publishedAt)
            if let interval = RefreshSchedule.observedInterval(from: dates) {
                stored.observedInterval = interval
            }

            try stored.update(db)
            return newArticles
        }
    }

    /// Writes one article down, and says whether it had never been seen.
    private static func store(
        _ item: ParsedItem,
        of parsed: ParsedFeed,
        feed: Feed,
        at now: Date,
        read: Set<ArticleFingerprint>,
        in db: Database
    ) throws -> Bool {
        guard let identity = item.identity else { return false }

        let base = item.url ?? feed.siteURL
        let bodyHTML = item.contentHTML ?? item.summaryHTML
        let sanitized = bodyHTML.map { HTMLSanitizer.sanitize($0, relativeTo: base) }
        let plainText = sanitized.map(HTMLSanitizer.plainText)
        let excerpt = Self.excerpt(of: item)
        let cover = CoverImage.of(item, sanitizedHTML: sanitized)
        let key = ArticleKey.of(
            url: item.url,
            title: item.title ?? "",
            publishedAt: item.publishedAt,
            room: FeedURL.room(of: feed.siteURL ?? feed.url)
        )

        // Detected once, at ingestion, since the index and the stemmer both
        // want to know and neither may guess again later.
        let language = LanguageDetection.language(
            stated: item.language ?? parsed.language,
            title: item.title,
            body: plainText
        )

        let existing =
            try Entry
            .filter(Column("feed_id") == feed.id && Column("guid") == identity)
            .fetchOne(db)

        if var entry = existing {
            // What the reader did to an article is theirs : an update rewrites
            // the article, never its read or starred state.
            entry.title = item.title ?? entry.title
            entry.url = item.url ?? entry.url
            entry.excerpt = excerpt ?? entry.excerpt
            entry.author = item.author ?? entry.author
            entry.publishedAt = item.publishedAt ?? entry.publishedAt
            entry.updatedAt = item.updatedAt ?? entry.updatedAt
            entry.language = language ?? entry.language
            if !item.enclosures.isEmpty {
                entry.enclosures = item.enclosures
                entry.hasMedia = true
            }
            // A publisher who illustrates an article after publishing it is
            // improving it ; one who drops the picture has usually just
            // reworded the feed, and the picture already shown stays.
            entry.imageURL = cover ?? entry.imageURL
            entry.canonicalKey = key ?? entry.canonicalKey
            try entry.update(db)

            if let sanitized {
                try EntryBody(
                    entryID: entry.id, sanitizedHTML: sanitized, plainText: HTMLSanitizer.plainText(sanitized)
                )
                .upsert(db)
            }
            return false
        }

        let fingerprint = ArticleFingerprint(feedURL: feed.url, guid: identity)

        var entry = Entry(
            feedID: feed.id,
            guid: identity,
            url: item.url,
            title: item.title ?? String(localized: "Untitled"),
            excerpt: excerpt,
            author: item.author,
            language: language,
            publishedAt: item.publishedAt,
            updatedAt: item.updatedAt,
            receivedAt: now,
            isRead: read.contains(fingerprint),
            enclosures: item.enclosures.isEmpty ? nil : item.enclosures,
            imageURL: cover,
            canonicalKey: key
        )
        entry.hasMedia = !item.enclosures.isEmpty

        // The same article reaching the reader through a second feed of the
        // same newsroom. It keeps its row, since it belongs to a feed they
        // follow, and points at the copy that arrived first.
        entry.duplicateOf = key.flatMap { try? Self.original(of: $0, in: db) }
        try entry.insert(db)

        if let sanitized {
            try EntryBody(entryID: entry.id, sanitizedHTML: sanitized, plainText: plainText).insert(db)
        }
        return true
    }

    /// The first copy of an article, wherever it came from.
    ///
    /// Whatever feed, this one included. A feed that gives its articles a
    /// fresh identifier on every build hands the same piece over again and
    /// again, and the identifier is exactly what stops the ordinary path from
    /// noticing. The key notices.
    ///
    /// Never a duplicate itself, so a third copy points at the original rather
    /// than at the second.
    private static func original(of key: String, in db: Database) throws -> UUID? {
        try Entry
            .filter(Column("canonical_key") == key && Column("duplicate_of") == nil)
            .order(Column("received_at"))
            .fetchOne(db)?
            .id
    }

    private static func excerpt(of item: ParsedItem) -> String? {
        for html in [item.summaryHTML, item.contentHTML] {
            guard let html else { continue }
            let excerpt = HTMLSanitizer.excerpt(html)
            if !excerpt.isEmpty { return excerpt }
        }
        return nil
    }

    // MARK: - Health

    private func recordSuccess(_ feed: Feed, notModified: Bool) async throws {
        let now = Date()

        try await database.writer.write { db in
            guard var stored = try Feed.fetchOne(db, key: feed.id) else { return }

            stored.fetchCount += 1
            if notModified { stored.notModifiedCount += 1 }
            stored.lastFetchAt = now
            stored.lastSuccessAt = now
            stored.failureCount = 0
            stored.lastFailureReason = nil
            try stored.update(db)
        }
    }

    private func recordFailure(_ feed: Feed, failure: FetchFailure, reason: String? = nil) async throws {
        let now = Date()
        let reason = reason ?? Self.reason(for: failure)
        let settled = Self.isSettled(failure)

        try await database.writer.write { db in
            guard var stored = try Feed.fetchOne(db, key: feed.id) else { return }

            stored.fetchCount += 1
            stored.failureCount += 1
            stored.lastFetchAt = now
            stored.lastFailureReason = reason

            let threshold = settled ? Self.quarantineAfterRejection : Self.quarantineAfterFailure
            if stored.failureCount >= threshold {
                stored.quarantinedAt = now
                Log.fetch.notice("A feed was quarantined after \(stored.failureCount) failures : \(reason)")
            }

            try stored.update(db)
        }
    }

    /// Whether the answer is a decision rather than an accident.
    private static func isSettled(_ failure: FetchFailure) -> Bool {
        switch failure {
        case .unauthorized, .gone: true
        default: false
        }
    }

    /// A short, safe reason. A private feed's address never appears in one.
    private static func reason(for failure: FetchFailure) -> String {
        switch failure {
        case .unreachable: "unreachable"
        case .unauthorized(let status): "rejected (\(status))"
        case .gone(let status): "gone (\(status))"
        case .rateLimited: "rate limited"
        case .http(let status): "http \(status)"
        case .tooLarge: "too large"
        case .cancelled: "cancelled"
        }
    }
}

nonisolated extension RefreshSummary {
    fileprivate mutating func add(_ result: RefreshResult) {
        switch result {
        case .updated(let new):
            refreshed += 1
            newArticles += new
        case .notModified:
            unchanged += 1
        case .failed:
            failed += 1
        case .skipped:
            break
        }
    }
}
