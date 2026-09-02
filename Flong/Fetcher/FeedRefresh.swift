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
    /// Feeds the pass never got to, or never got to ask : the budget ran out,
    /// or the system would not send the request.
    var skipped = 0

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
    private let marks: MarkStore
    private let credentials: CredentialStoring

    init(
        database: AppDatabase,
        fetcher: FeedFetcher = FeedFetcher(),
        credentials: CredentialStoring = KeychainCredentials()
    ) {
        self.database = database
        self.fetcher = fetcher
        self.readStates = ReadStateStore(database)
        self.marks = MarkStore(database)
        self.credentials = credentials
    }

    // MARK: - Refreshing

    /// Refreshes every feed that is due, the most overdue first.
    ///
    /// **The order is what makes a budget survivable.** A background refresh is
    /// given about twenty-five seconds and is cancelled when they are up. The
    /// feeds used to be taken in the order the database returned them, which
    /// for UUIDv7 keys is the order they were subscribed to : a reader with
    /// three hundred feeds and a budget that ran out at the eightieth had the
    /// next two hundred and twenty never refreshed in the background at all,
    /// since the following pass started from the same end and was cut off at
    /// the same place.
    ///
    /// Sorted by how overdue each one is against its own rhythm, the budget
    /// goes to what is most likely to have something, and a feed that misses
    /// one pass is nearer the front of the next.
    func refreshDue(
        now: Date = Date(),
        sparingly: Bool = false,
        until deadline: Date? = nil,
        onProgress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> RefreshSummary {
        let device = DeviceStagger.deviceIdentifier()
        let feeds = (try? await allFeeds()) ?? []

        let due =
            feeds
            .compactMap { feed -> (Feed, Double)? in
                let interval = feed.refreshInterval ?? feed.observedInterval ?? RefreshSchedule.defaultInterval
                let stagger = DeviceStagger.offset(for: feed.id, interval: interval, device: device)
                guard RefreshSchedule.isDue(feed, now: now, stagger: stagger) else { return nil }
                return (feed, RefreshSchedule.lateness(feed, now: now, stagger: stagger))
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)

        return await refresh(due, sparingly: sparingly, until: deadline, onProgress: onProgress)
    }

    /// Refreshes every feed, due or not, which is what asking for a refresh
    /// means.
    func refreshAll(
        until deadline: Date? = nil,
        onProgress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> RefreshSummary {
        let feeds = (try? await allFeeds()) ?? []
        return await refresh(feeds.filter { $0.quarantinedAt == nil }, until: deadline, onProgress: onProgress)
    }

    /// Refreshes a list of feeds, in the order given, for as long as it is
    /// given.
    ///
    /// **The deadline is honoured between feeds, not inside one.** A pass that
    /// runs out of time stops handing out work and lets what is in flight
    /// finish, so nothing is cancelled mid-write and every feed the pass did
    /// reach is fully recorded. What is left is simply the most overdue thing
    /// at the head of the next pass, which is what makes the whole of this
    /// resumable without a checkpoint.
    ///
    /// It used to have no deadline at all, so a background refresh spent its
    /// entire twenty-five seconds here and was then cancelled by the system
    /// mid-flight, which cancelled the writes too and reported the whole task
    /// as failed.
    func refresh(
        _ feeds: [Feed],
        sparingly: Bool = false,
        until deadline: Date? = nil,
        onProgress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> RefreshSummary {
        guard !feeds.isEmpty else { return RefreshSummary() }
        let total = feeds.count

        // Said before anything is asked for, so whatever is measuring the pass
        // has a denominator from the start rather than guessing one. Nothing
        // else knows how many feeds are due : that is worked out here, and a
        // caller that tried to count them again would be doing the same work
        // twice and getting a different answer.
        onProgress(0, total)

        return await withTaskGroup(of: RefreshResult.self) { group in
            var iterator = feeds.makeIterator()
            var running = 0

            while running < Self.concurrency, let feed = iterator.next() {
                group.addTask { await refresh(feed, sparingly: sparingly) }
                running += 1
            }

            var summary = RefreshSummary()
            var done = 0
            for await result in group {
                summary.add(result)
                done += 1
                // A parameter and never a stored property, so this stays a
                // `Sendable` struct that captures nothing. The consumer loop is
                // serial, so it is never called against itself, and it is
                // synchronous, so waiting on it cannot slow the fetching.
                onProgress(done, total)

                guard !Task.isCancelled, deadline.map({ Date() < $0 }) ?? true else { continue }
                if let feed = iterator.next() {
                    group.addTask { await refresh(feed, sparingly: sparingly) }
                }
            }

            // Whatever the iterator still holds was never asked for.
            while iterator.next() != nil { summary.skipped += 1 }
            return summary
        }
    }

    /// Refreshes one feed, and writes down what happened either way.
    @discardableResult
    func refresh(_ feed: Feed, sparingly: Bool = false) async -> RefreshResult {
        // A feed the reader pays for is fetched with what proves they do. A
        // keychain that will not answer is a feed fetched without, which the
        // server answers 401 to and section 9 quarantines : that is a better
        // outcome than refusing to try.
        let credential = try? credentials.credential(for: feed.id)

        // The secret is the address itself, and the address in the database is
        // a masked one that no server has ever heard of.
        let url = credential.flatMap { if case .secretURL(let url) = $0 { url } else { nil } } ?? feed.url

        let request = FetchRequest(
            url: url,
            etag: feed.etag,
            lastModified: feed.lastModified,
            credential: credential,
            isExpensiveNetworkAllowed: !sparingly
        )

        switch await fetcher.fetch(request) {
        case .notModified:
            try? await recordSuccess(feed, notModified: true)
            return .notModified

        case .failed(.notAttempted), .failed(.cancelled):
            // Nothing was asked, so there is nothing to write down. Recording
            // these was how a reader who spent two days on a tethered
            // connection, or a background pass the system cut short, came back
            // to feeds quarantined for a fault that was never theirs.
            return .skipped

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
                // A star another device set on one of these may have arrived
                // before the article did, and this is the moment it can be
                // written.
                if new > 0 { _ = try? await marks.drain() }
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
            // What the prose said before this refresh, so that a piece a
            // publisher actually rewrote can be told from the same piece served
            // again unchanged, which is what almost every refresh serves.
            let wasTitled = entry.title
            let wasExcerpted = entry.excerpt
            let wasWritten = try String.fetchOne(
                db,
                sql: "SELECT plain_text FROM entry_body WHERE entry_id = ?",
                arguments: [entry.id]
            )

            // What the reader did to an article is theirs : an update rewrites
            // the article, never its read or starred state.
            entry.title = item.title ?? entry.title
            entry.url = item.url ?? entry.url
            entry.excerpt = excerpt ?? entry.excerpt
            entry.author = Author.name(from: item.author) ?? entry.author
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
            // **Who the piece is about follows the prose it is read out of.**
            // Nobody is read here : that is a model over a whole text and this
            // is the ingestion write, which is exactly where it may not run.
            // The article goes back in the queue and `NewsmakersJob` reads it
            // again. See ``NewsmakerStore``.
            //
            // Only where the prose really changed. A refresh serves the twenty
            // most recent articles of a feed every time, and re-reading all of
            // them at every pass would be the whole corpus, hourly, for a
            // handful of pieces a publisher touched.
            let rewritten =
                entry.title != wasTitled || entry.excerpt != wasExcerpted
                || (plainText != nil && plainText != wasWritten)
            if rewritten { entry.newsmakersAt = nil }

            try entry.update(db)
            // A publisher who rewrites a byline changes who wrote the piece,
            // so the people beside it are written again rather than added to.
            try AuthorStore.index(entry.id, byline: entry.author, in: db)

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
        // One field holds a whole newsroom, so the people it names are written
        // out beside the article : see ``AuthorStore/index(_:byline:in:)``.
        try AuthorStore.index(entry.id, byline: entry.author, in: db)

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
        case .notAttempted: "not attempted"
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
            skipped += 1
        }
    }
}
