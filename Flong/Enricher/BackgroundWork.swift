//
//  BackgroundWork.swift
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

/// A piece of work too long to finish in one go.
///
/// Section 15 of the specification requires every long task to be resumable :
/// idempotent batches, a resume point, and automatic resumption at the next
/// launch. `BGContinuedProcessingTask` is not reliable enough to assume that a
/// task which started will finish.
///
/// **The resume point is the data itself.** What is left to do is a question the
/// store answers : the feeds never fetched, the kept articles with no vector. A
/// checkpoint written beside them could only ever disagree with them, and a
/// checkpoint that disagrees is worse than no checkpoint, since it is believed.
nonisolated protocol ResumableJob: Sendable {
    /// What the job is called, for logs and for the system's own progress.
    var name: String { get }

    /// How much is left, which is what a progress bar shows and what tells the
    /// runner it can stop.
    func remaining() async throws -> Int

    /// Does one batch. Returns how many pieces of work it got through.
    func step() async throws -> Int
}

/// Computes the vectors of what the reader marked, a batch at a time.
nonisolated struct VectorizeJob: ResumableJob {
    let name = "vectorize"
    private let vectors: VectorStore
    private let onProgress: @Sendable ([Entry]) async -> Void

    init(_ database: AppDatabase, onProgress: @escaping @Sendable ([Entry]) async -> Void = { _ in }) {
        self.vectors = VectorStore(database)
        self.onProgress = onProgress
    }

    func remaining() async throws -> Int { try await vectors.outstandingCount() }

    func step() async throws -> Int {
        let items = try await vectors.itemsNeedingVectors()
        guard !items.isEmpty else { return 0 }

        let written = try await vectors.vectorize(items)
        // A vector computed here is worth telling the other devices about : it
        // spares each of them the same work.
        await onProgress(items)
        return written == 0 ? items.count : written
    }
}

/// Reads who the articles are about, a batch at a time.
///
/// **The long job this feature could not do without.** Splitting a byline is
/// string work and happens in the write that stores the article ; reading the
/// people out of a whole text is a model, and a corpus of a hundred thousand
/// articles is hours of it. So it is section 15's resumable work : idempotent
/// batches, a resume point that is the data itself, and automatic resumption at
/// the next launch.
///
/// The resume point is `entry.newsmakers_at`, which is why it exists : an
/// article that names nobody is a real answer, and one told apart from it only
/// by having no rows would be read again at every pass, for ever.
nonisolated struct NewsmakersJob: ResumableJob {
    let name = "newsmakers"
    private let newsmakers: NewsmakerStore

    init(_ database: AppDatabase) {
        self.newsmakers = NewsmakerStore(database)
    }

    func remaining() async throws -> Int { try await newsmakers.outstandingCount() }

    func step() async throws -> Int {
        let items = try await newsmakers.unread()
        guard !items.isEmpty else { return 0 }

        return try await newsmakers.read(items)
    }
}

/// Fetches the feeds that have never been fetched.
///
/// This is what an import leaves behind : a thousand subscriptions and nothing
/// in any of them. It is the long task section 15 has in mind, and the one the
/// milestone asks to survive being sent to the background.
nonisolated struct FirstFetchJob: ResumableJob {
    let name = "first-fetch"
    private let database: AppDatabase
    private let refresh: FeedRefresh

    init(_ database: AppDatabase, fetcher: FeedFetcher = FeedFetcher()) {
        self.database = database
        self.refresh = FeedRefresh(database: database, fetcher: fetcher)
    }

    func remaining() async throws -> Int {
        try await unfetched(limit: .max).count
    }

    func step() async throws -> Int {
        let feeds = try await unfetched(limit: FeedRefresh.concurrency * 2)
        guard !feeds.isEmpty else { return 0 }

        let summary = await refresh.refresh(feeds)
        // Even a feed that failed has been tried, and its failure count is what
        // stops it from being tried for ever.
        return max(summary.attempted, feeds.count)
    }

    private func unfetched(limit: Int) async throws -> [Feed] {
        try await database.writer.read { db in
            try Feed.filter(Column("last_success_at") == nil && Column("quarantined_at") == nil)
                .order(Column("created_at"))
                .limit(limit)
                .fetchAll(db)
        }
    }
}

/// Runs a job to its end, or to the end of the time it was given.
nonisolated struct JobRunner: Sendable {
    /// What a run came to.
    nonisolated struct Outcome: Hashable, Sendable {
        var done = 0
        var remaining = 0
        var isFinished: Bool { remaining == 0 }
    }

    private let job: any ResumableJob

    init(_ job: any ResumableJob) {
        self.job = job
    }

    /// Works until there is nothing left, the time runs out, or the task is
    /// cancelled.
    ///
    /// Every batch stands alone, so stopping between two of them loses nothing
    /// and the next run picks up exactly where this one left off.
    /// - Parameter breathing: how long to stand aside between two batches.
    ///   Nought for a pass the system granted time for, where nobody is
    ///   waiting and the point is to get through the queue. A moment for
    ///   anything run while a window is up : a batch is a read and a write of
    ///   the store and, for the people a story names, a pass of `NLTagger` over
    ///   its text, and one batch after another with nothing between them is a
    ///   background lane holding the database and the processor against a
    ///   reader who is trying to scroll. The work is resumable, so what this
    ///   costs is throughput nobody is watching.
    @discardableResult
    @concurrent
    func run(
        until deadline: Date? = nil,
        breathing: Duration = .zero,
        onProgress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> Outcome {
        var outcome = Outcome()

        while !Task.isCancelled {
            if let deadline, Date() >= deadline { break }

            do {
                let done = try await job.step()
                guard done > 0 else { break }

                outcome.done += done
                outcome.remaining = try await job.remaining()
                onProgress(outcome.done, outcome.done + outcome.remaining)

                // Always let go of the thread between two batches, and stand
                // aside for as long as the caller asked on top of that.
                await Task.yield()
                if breathing > .zero { try? await Task.sleep(for: breathing) }
            } catch {
                Log.enrich.error("\(job.name, privacy: .public) stopped : \(error, privacy: .public)")
                break
            }
        }

        outcome.remaining = (try? await job.remaining()) ?? outcome.remaining
        if outcome.done > 0 {
            Log.enrich.notice(
                "\(job.name, privacy: .public) did \(outcome.done), \(outcome.remaining) left"
            )
        }
        return outcome
    }
}
