//
//  ServiceImport.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import OSLog

/// What an import of a remote account did.
///
/// The same shape as an OPML file's report, for the same reason : a single feed
/// nobody can make sense of is listed rather than fatal, and the reader decides
/// whether to care.
nonisolated struct ServiceImportReport: Hashable, Sendable {
    var added = 0
    var merged = 0
    var skipped: [SkippedFeed] = []
    var articles = 0
    var favourites = 0
    /// Favourites of sources this device does not follow.
    ///
    /// A starred article belongs to a feed, and a source the reader unticked is
    /// a source there is no row to hang one off. They are counted and said,
    /// never guessed into a subscription nobody asked for.
    var favouritesElsewhere = 0
    /// Whether everything asked for actually happened. `false` means the import
    /// is paused rather than finished, and the row saying where it got to is on
    /// disk.
    var isComplete = false
    /// The articles this run starred, which have to reach Spotlight and the
    /// reader's other devices.
    var starred: [UUID] = []

    var sources: Int { added + merged }
}

/// What the import is doing, for the bar that says so.
nonisolated struct ServiceImportProgress: Hashable, Sendable {
    nonisolated enum Stage: Hashable, Sendable {
        case subscribing
        case articles
        case favourites

        var title: LocalizedStringResource {
            switch self {
            case .subscribing: "Taking the subscriptions"
            case .articles: "Bringing the articles"
            case .favourites: "Bringing the favourites"
            }
        }
    }

    var stage: Stage = .subscribing
    var done = 0
    /// What there is to get through, or nought where nothing can count it : the
    /// starred stream says how long it is only by ending.
    var total = 0
    /// The source being read, where one is.
    var source: String?

    var fraction: Double? {
        guard total > 0 else { return nil }
        return min(Double(done) / Double(total), 1)
    }
}

/// Brings a FreshRSS account in, once.
///
/// **Once, and then nothing.** Section 19 of the specification makes a remote
/// service a one-shot import source : the subscriptions, the articles and the
/// stars are read, and afterwards Flong collects the feeds itself and has no
/// further business with the server. Nothing here writes a state back, and the
/// account is forgotten the moment the import ends.
///
/// **Three passes, in this order, and each resumes on its own.** The
/// subscriptions first, because everything else needs a row to hang off ; the
/// history of each chosen source next ; the favourites last, since by then the
/// sources they belong to are settled. Where each pass got to is written down
/// after every page, so an application put away halfway through carries on from
/// the page after rather than from the start.
///
/// **Everything it writes is idempotent.** A subscription is matched by its
/// canonical address and an article by its identity within its feed, so running
/// the whole import twice adds nothing the second time. That is what makes a
/// resumption safe even where the page it resumes from has already landed.
nonisolated struct ServiceImport: Sendable {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let jobs: ImportJobStore

    init(_ database: AppDatabase) {
        self.database = database
        self.subscriptions = SubscriptionStore(database)
        self.jobs = ImportJobStore(database)
    }

    // MARK: - Starting one

    /// Writes down what the reader chose, before a single article is fetched.
    ///
    /// The list is the picker's, tick by tick, so an import finished tomorrow
    /// brings what was chosen today rather than what the account holds tomorrow.
    func begin(
        account: ServiceAccount,
        password: String,
        listed: [GoogleReaderSubscription],
        chosen: Set<String>,
        depth: ImportDepth,
        wantsArticles: Bool,
        wantsFavourites: Bool,
        credentials: CredentialStoring
    ) async throws -> ImportJob {
        let job = ImportJob(
            endpoint: account.endpoint,
            username: account.username,
            depth: depth,
            wantsFavourites: wantsFavourites
        )

        let sources = listed.compactMap { subscription -> ImportSource? in
            guard let address = subscription.url, !address.isEmpty else { return nil }
            let isChosen = chosen.contains(subscription.id)
            return ImportSource(
                jobID: job.id,
                streamID: subscription.id,
                address: address,
                title: subscription.title ?? "",
                siteAddress: subscription.htmlUrl,
                iconAddress: subscription.iconUrl,
                isChosen: isChosen,
                wantsArticles: isChosen && wantsArticles
            )
        }

        // The secret goes to the keychain and nowhere else, under the job's own
        // identifier : `docs/technical/credentials.md` states the rule, and an
        // API password is a password whatever it opens. It is deleted in
        // ``finish(_:credentials:)``, whether the import ran to the end or the
        // reader gave up on it.
        try credentials.setCredential(.basic(user: account.username, password: password), for: job.id)
        try await jobs.start(job, sources: sources)
        return job
    }

    /// The import waiting to be finished, where there is one.
    func standing() async throws -> ImportJob? { try await jobs.job() }

    /// The API password of an import waiting to be finished.
    func password(of job: ImportJob, credentials: CredentialStoring) throws -> String? {
        guard case .basic(_, let password) = try credentials.credential(for: job.id) else { return nil }
        return password
    }

    /// Takes the import away, and the secret with it.
    ///
    /// What it brought in stays : the subscriptions and the articles are the
    /// reader's now, and have nothing further to do with the account they came
    /// from.
    func finish(_ job: ImportJob, credentials: CredentialStoring) async throws {
        try? credentials.setCredential(nil, for: job.id)
        try await jobs.finish()
    }

    // MARK: - Running it

    /// Carries the import as far as it goes, from wherever it stands.
    ///
    /// Cancellation is not a failure : an application being put away cancels the
    /// task, the report says the import is not complete, and the row holding
    /// where every stream got to is already on disk.
    @concurrent
    func run(
        _ job: ImportJob,
        using client: GoogleReaderClient,
        onProgress: @escaping @Sendable (ServiceImportProgress) -> Void = { _ in }
    ) async throws -> ServiceImportReport {
        var job = job
        var report = ServiceImportReport(
            added: job.added,
            merged: job.merged,
            articles: job.articles,
            favourites: job.favourites,
            favouritesElsewhere: job.favouritesElsewhere
        )

        if !job.tookSubscriptions {
            onProgress(ServiceImportProgress(stage: .subscribing))
            try await follow(&job, into: &report)
        }

        try await bringArticles(&job, into: &report, using: client, onProgress: onProgress)
        try await bringFavourites(&job, into: &report, using: client, onProgress: onProgress)

        report.isComplete = try await isSettled(job)
        return report
    }

    /// Whether there is anything left to do, which is what says an import is
    /// over rather than merely paused.
    private func isSettled(_ job: ImportJob) async throws -> Bool {
        guard let standing = try await jobs.job() else { return true }
        guard standing.tookSubscriptions else { return false }
        guard !standing.wantsFavourites || standing.tookFavourites else { return false }
        return try await jobs.outstanding(of: job.id).isEmpty
    }

    // MARK: - The subscriptions

    /// Follows what the reader ticked, merging what is already followed.
    ///
    /// One transaction, as an OPML import is : sixty feeds land whole or not at
    /// all. What is already followed keeps everything the reader decided about
    /// it, since ``SubscriptionStore`` only ever fills in what is still empty.
    private func follow(_ job: inout ImportJob, into report: inout ServiceImportReport) async throws {
        let sources = try await jobs.sources(of: job.id).filter(\.isChosen)

        var wanted: [Subscription] = []
        var unusable: [ImportSource] = []
        for source in sources {
            do {
                wanted.append(
                    try Subscription(
                        address: source.address,
                        title: source.title,
                        siteURL: source.siteAddress.flatMap { try? FeedURL.canonical($0) },
                        iconURL: source.iconAddress.flatMap(URL.init(string:))
                    )
                )
            } catch {
                report.skipped.append(SkippedFeed(title: source.title, address: source.address, reason: error))
                unusable.append(source)
            }
        }

        for result in try await subscriptions.subscribe(to: wanted) {
            if result.isNew { report.added += 1 } else { report.merged += 1 }
        }

        // A source with no address anything can follow has no stream to walk
        // either, so it stops being outstanding rather than being asked for
        // again at every resumption.
        for var source in unusable {
            source.wantsArticles = false
            source.isDone = true
            try await jobs.save(source)
        }

        job.added = report.added
        job.merged = report.merged
        job.tookSubscriptions = true
        try await jobs.save(job)
    }

    // MARK: - The history

    /// Walks each chosen source's stream, newest first, page by page.
    private func bringArticles(
        _ job: inout ImportJob,
        into report: inout ServiceImportReport,
        using client: GoogleReaderClient,
        onProgress: @escaping @Sendable (ServiceImportProgress) -> Void
    ) async throws {
        let wanted = try await jobs.sources(of: job.id).filter(\.wantsArticles)
        guard !wanted.isEmpty else { return }

        var outstanding = try await jobs.outstanding(of: job.id)
        var done = wanted.count - outstanding.count

        while !outstanding.isEmpty {
            var source = outstanding.removeFirst()
            guard !Task.isCancelled else { return }

            onProgress(
                ServiceImportProgress(stage: .articles, done: done, total: wanted.count, source: source.title)
            )

            if let feed = try await subscriptions.feed(at: source.address) {
                try await walk(&source, of: feed, limit: job.wantedDepth.limit, using: client, into: &report)
            } else {
                // Ticked, and not followed : the reader took the source away
                // between two runs of the import, which is an answer.
                source.isDone = true
                try await jobs.save(source)
            }

            done += 1
            job.articles = report.articles
            job.favourites = report.favourites
            try await jobs.save(job)
        }

        onProgress(ServiceImportProgress(stage: .articles, done: done, total: wanted.count))
    }

    /// One source's stream, from wherever its last page ended.
    private func walk(
        _ source: inout ImportSource,
        of feed: Feed,
        limit: Int?,
        using client: GoogleReaderClient,
        into report: inout ServiceImportReport
    ) async throws {
        while !source.isDone {
            guard !Task.isCancelled else { return }

            let remaining = limit.map { $0 - source.fetched }
            if let remaining, remaining <= 0 { break }

            let asked = min(remaining ?? GoogleReaderClient.pageSize, GoogleReaderClient.pageSize)
            let was = source.continuation
            let page = try await client.page(of: source.streamID, continuation: was, count: asked)

            let written = try await write(page.items, into: [source.streamID: feed])
            report.articles += written.articles
            report.favourites += written.favourites
            report.starred += written.starred

            source.fetched += page.items.count
            source.continuation = page.continuation
            // A missing continuation is the end of the stream, and it is the
            // only thing that says so short of the reader's own limit. A server
            // handing back the page just read would otherwise be walked for
            // ever, so a token that did not move ends the walk too.
            source.isDone = page.continuation == nil || page.items.isEmpty || page.continuation == was
            try await jobs.save(source)
        }

        guard !source.isDone else { return }
        source.isDone = true
        try await jobs.save(source)
    }

    // MARK: - The favourites

    /// Walks the starred stream, which spans every source of the account.
    ///
    /// It runs last on purpose : a favourite belongs to a feed, and which feeds
    /// this device follows is settled by the time it starts.
    private func bringFavourites(
        _ job: inout ImportJob,
        into report: inout ServiceImportReport,
        using client: GoogleReaderClient,
        onProgress: @escaping @Sendable (ServiceImportProgress) -> Void
    ) async throws {
        guard job.wantsFavourites, !job.tookFavourites else { return }

        // What the service calls each stream, against the source this device
        // follows at that address, so a starred article can be placed by its
        // `origin.streamId` alone.
        let followed = Dictionary(
            try await subscriptions.feeds().map { ($0.url, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let feeds = try await jobs.sources(of: job.id).reduce(into: [String: Feed]()) { found, source in
            guard let address = try? FeedURL.canonical(source.address), let feed = followed[address] else { return }
            found[source.streamID] = feed
        }

        while !job.tookFavourites {
            guard !Task.isCancelled else { return }

            onProgress(ServiceImportProgress(stage: .favourites, done: report.favourites))

            let was = job.favouritesContinuation
            let page = try await client.page(of: GoogleReader.starred, continuation: was)

            report.favouritesElsewhere += page.items.count { item in
                guard let stream = item.origin?.streamId else { return true }
                return feeds[stream] == nil
            }

            let written = try await write(page.items, into: feeds)
            report.articles += written.articles
            report.favourites += written.favourites
            report.starred += written.starred

            job.favouritesContinuation = page.continuation
            job.tookFavourites = page.continuation == nil || page.items.isEmpty || page.continuation == was
            job.articles = report.articles
            job.favourites = report.favourites
            job.favouritesElsewhere = report.favouritesElsewhere
            try await jobs.save(job)
        }
    }

    // MARK: - Writing the articles down

    /// What one batch of articles came to.
    private struct Written {
        var articles = 0
        var favourites = 0
        var starred: [UUID] = []
    }

    /// Writes a page of articles into the sources they belong to, in one
    /// transaction.
    ///
    /// **The same write a refresh does**, through ``FeedRefresh/store(_:of:feed:at:read:in:)``,
    /// so an imported article is spelled exactly like a fetched one : the same
    /// canonical key, the same duplicate rule, the same byline, the same
    /// sanitized body. What is added on top is the one thing the service knows
    /// and a publisher does not, the read and the starred state.
    ///
    /// **Those two are a union and never a correction.** An article read here
    /// and unread there stays read : the account is one more thing with an
    /// opinion about an article, not the authority on it, and an import that
    /// could mark a hundred read articles unread is an import nobody dares run
    /// twice. It is the rule section 7 already applies between the reader's own
    /// devices, and for the same reason.
    private func write(_ items: [GoogleReaderItem], into feeds: [String: Feed]) async throws -> Written {
        guard !items.isEmpty, !feeds.isEmpty else { return Written() }

        let now = Date()
        return try await database.writer.write { db in
            var written = Written()

            for item in items {
                guard let stream = item.origin?.streamId, let feed = feeds[stream] else { continue }
                guard
                    let write = try FeedRefresh.store(
                        Self.parsed(item),
                        of: ParsedFeed(format: .rss),
                        feed: feed,
                        at: now,
                        read: [],
                        // An account brought over is a history the reader
                        // already had, whatever this device's clock makes of
                        // its arrival. A notice per article would be thousands
                        // of interruptions about pieces they have already seen.
                        isBacklog: true,
                        in: db
                    )
                else { continue }

                if write.isNew { written.articles += 1 }

                if item.isRead {
                    try db.execute(
                        sql: """
                            UPDATE entry SET is_read = 1, read_at = COALESCE(read_at, ?)
                            WHERE id = ? AND is_read = 0
                            """,
                        arguments: [now, write.id]
                    )
                }

                if item.isStarred {
                    try db.execute(
                        sql: "UPDATE entry SET is_starred = 1 WHERE id = ? AND is_starred = 0",
                        arguments: [write.id]
                    )
                    if db.changesCount > 0 {
                        written.favourites += 1
                        written.starred.append(write.id)
                    }
                }
            }

            return written
        }
    }

    /// The article, as the parser would have handed it over.
    ///
    /// **Its identity is the address it lives at**, and that is a considered
    /// guess rather than the article's real GUID : the API serves the service's
    /// own numeric identifier and never the one the feed stated, so there is
    /// nothing to carry across. A permalink is what the great majority of feeds
    /// put in their `guid`, so guessing it means the same article fetched from
    /// the publisher tomorrow lands in the row imported today, wearing the read
    /// state and the star the account had for it.
    ///
    /// **Where the guess misses, nothing breaks.** The canonical key is computed
    /// from the same address by the same rule, so the copy arriving from the
    /// publisher recognizes the imported one, points at it and is shown nowhere.
    /// The reader sees one article either way : see ``ArticleKey``.
    private static func parsed(_ item: GoogleReaderItem) -> ParsedItem {
        let link = item.link

        return ParsedItem(
            guid: link?.absoluteString ?? item.id,
            url: link,
            title: item.title,
            contentHTML: item.bodyHTML,
            author: item.author,
            publishedAt: item.publishedAt,
            updatedAt: item.updatedAt,
            enclosures: item.attachments
        )
    }
}
