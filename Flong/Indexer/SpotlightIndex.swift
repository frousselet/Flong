//
//  SpotlightIndex.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreSpotlight
import CryptoKit
import Foundation
import OSLog
import UniformTypeIdentifiers

/// What a Spotlight result stands for.
///
/// Two things are indexed and they are not the same kind of thing, so the
/// identifier has to say which : an article is read, a story is a page of
/// several articles about one subject.
///
/// **An article keeps the bare identifier it has always had.** The prefix is on
/// the stories alone. A rename would leave every article already in the index
/// standing under a name nothing answers to, and nothing would notice : the
/// index is rebuilt when its contents disagree with the store, and renaming
/// what they are called changes neither side of that comparison.
nonisolated enum SpotlightResult: Hashable, Sendable {
    case article(UUID)
    case story(UUID)

    private static let storyPrefix = "story/"

    var identifier: String {
        switch self {
        case .article(let id): id.uuidString
        case .story(let id): Self.storyPrefix + id.uuidString
        }
    }

    init?(_ identifier: String) {
        if identifier.hasPrefix(Self.storyPrefix) {
            guard let id = UUID(uuidString: String(identifier.dropFirst(Self.storyPrefix.count))) else { return nil }
            self = .story(id)
        } else {
            guard let id = UUID(uuidString: identifier) else { return nil }
            self = .article(id)
        }
    }
}

/// Hands what the reader chose to Spotlight.
///
/// Section 11 of the specification gives Spotlight what the reader chose and
/// only that : a few thousand items, which is what it is good at, against the
/// hundreds of thousands of the whole stream, which it is not. Two things go
/// in, and each is chosen rather than collected.
///
/// **The articles** are the ones the reader picked out. One at a time, by
/// starring, writing on or filing them ; or once and for all that follows, by
/// singling out a publisher or a writer, which is worth that favourite's most
/// recent ``ArticleStore/perFavourite`` articles and no more : a favourite
/// daily would otherwise fill the whole budget by itself within the year.
///
/// **The stories** are the ones on the front page, no more and no less. A story
/// is where the digest starts and it is the thing a reader watching a subject
/// is actually looking for, so the system search has to be able to find one.
/// They are not marks and they are not kept : they age off the page, and they
/// age out of the index with it.
///
/// The index is local to the device and never shared between the devices of one
/// account. Each of them indexes for itself.
///
/// `CSSearchableIndex` is a proxy for a system service and is safe to use from
/// any thread, which its headers have never said in a way the compiler can read.
/// The unchecked conformance says exactly that and nothing more.
nonisolated struct SpotlightIndex: @unchecked Sendable {
    /// Where the articles go, so they can all be taken back in one call.
    ///
    /// The name is what it was called when only the library was indexed. It is
    /// an opaque identifier the system keys its own records on, and renaming it
    /// would abandon what is already indexed rather than replace it.
    static let domain = "library"

    /// Where the stories go.
    ///
    /// A domain of their own, and that is what makes `no more and no less`
    /// cheap : the page is written by emptying this one and writing it again,
    /// which needs no record of what was there before and cannot leave a story
    /// behind that has left the page.
    static let storyDomain = "stories"

    /// The index is a named one rather than the shared one.
    ///
    /// Only a named index supports batching and the client state, and the client
    /// state is the whole self healing mechanism : the shared index throws
    /// `Batching not supported` at the first call, as an Objective-C exception
    /// no Swift `catch` can stop. A named index is still the application's
    /// Spotlight index, and what goes into it turns up in the system search
    /// exactly the same.
    static let indexName = "flong-library"

    private let index: CSSearchableIndex
    private let articles: ArticleStore
    private let subscriptions: SubscriptionStore

    init(
        _ articles: ArticleStore,
        _ subscriptions: SubscriptionStore,
        index: CSSearchableIndex = CSSearchableIndex(name: SpotlightIndex.indexName)
    ) {
        self.articles = articles
        self.subscriptions = subscriptions
        self.index = index
    }

    static var isAvailable: Bool { CSSearchableIndex.isIndexingAvailable() }

    // MARK: - Keeping Spotlight in step

    /// Adds or replaces articles in the index.
    @concurrent
    func index(_ items: [ArticleStore.Chosen]) async throws {
        guard Self.isAvailable, !items.isEmpty else { return }
        let publishers = try await subscriptions.identities()
        try await index.indexSearchableItems(items.map { Self.searchableItem(for: $0, publishedBy: publishers) })
    }

    /// Takes articles out of it.
    @concurrent
    func remove(_ ids: [UUID]) async throws {
        guard Self.isAvailable, !ids.isEmpty else { return }
        try await index.deleteSearchableItems(withIdentifiers: ids.map { SpotlightResult.article($0).identifier })
    }

    /// Writes the stories the front page is showing, and takes out the ones
    /// that have left it.
    ///
    /// **The whole page, every time, rather than a difference.** There are at
    /// most sixty of them and they carry no body, so writing the lot costs less
    /// than keeping a record of what was written last time would, and it is the
    /// only way the index cannot drift : whatever it held before, it holds the
    /// page afterwards.
    ///
    /// The caller decides when the page has changed. This is called with the
    /// front page and never with a narrowed one : narrowing is a question about
    /// the window the reader is looking at, not about what the system search
    /// should be able to find.
    func index(stories: [DigestStory]) async throws {
        guard Self.isAvailable else { return }

        try await index.deleteSearchableItems(withDomainIdentifiers: [Self.storyDomain])
        guard !stories.isEmpty else { return }

        let publishers = try await subscriptions.identities()
        try await index.indexSearchableItems(stories.map { Self.searchableItem(for: $0, publishedBy: publishers) })

        Log.index.notice("Wrote \(stories.count) stories to Spotlight")
    }

    /// Writes everything the reader has chosen, and tells Spotlight what it
    /// holds.
    ///
    /// The client state is kept **by Spotlight**, not by Flong. That is what
    /// makes this self healing : if Spotlight loses its index, it loses the
    /// state with it, and the next check sees a mismatch and writes everything
    /// again. An application that remembered the state itself would confidently
    /// skip the rebuild it most needed.
    ///
    /// It empties the whole index, the stories with it, which is why
    /// ``rebuildIfNeeded()`` says whether it ran : the page has to be handed
    /// back afterwards by whoever is holding it.
    func rebuild() async throws {
        guard Self.isAvailable else { return }

        try await IndexBatches.shared.alone {
            try await rebuild(against: articles.choices())
        }
    }

    /// Rebuilds only when Spotlight and the store disagree about what it holds.
    ///
    /// **The question is asked of the identifiers alone.** Deciding costs one
    /// pass over the chosen articles' keys and dates ; deciding yes costs their
    /// full texts as well. The first happens on every catch-up that brought
    /// something, the second almost never, and only the second is allowed to be
    /// expensive.
    ///
    /// - Returns: whether the index was written again, which also means the
    ///   stories were emptied out of it.
    @discardableResult
    func rebuildIfNeeded() async throws -> Bool {
        guard Self.isAvailable else { return false }

        // **The decision is taken inside the gate and not before it.** Two
        // callers deciding at once would both decide yes, and the second would
        // then write the whole index again over an index that had just been
        // written. Inside, the second reads the state the first left and says
        // no, which is the answer it should have given.
        return try await IndexBatches.shared.alone {
            let choices = try await articles.choices()
            guard try await lastState() != Self.state(of: choices) else { return false }

            try await rebuild(against: choices)
            return true
        }
    }

    /// Empties the index and writes the chosen articles back into it.
    ///
    /// - Parameter choices: what the store held when the decision to write was
    ///   taken, which is what Spotlight is told it now holds. Taken before the
    ///   articles are read rather than from them : a mark that lands between the
    ///   two readings then leaves a state that is older than the index, and the
    ///   next check writes again. The other way round it would be newer, and the
    ///   next check would agree with itself about an index missing an article.
    private func rebuild(against choices: [ArticleStore.Choice]) async throws {
        let items = try await articles.chosen()
        let publishers = try await subscriptions.identities()

        index.beginBatch()
        try await index.deleteAllSearchableItems()
        if !items.isEmpty {
            try await index.indexSearchableItems(items.map { Self.searchableItem(for: $0, publishedBy: publishers) })
        }
        try await endBatch(state: Self.state(of: choices))

        Log.index.notice("Wrote \(items.count) chosen articles to Spotlight")
    }

    // MARK: - Shapes

    /// What Spotlight is told about an article the reader chose.
    ///
    /// - Parameter publishedBy: what each publisher is called, so the system
    ///   search names an article's source the way the application does. The
    ///   feed's own title stands in where the publisher is not known.
    static func searchableItem(
        for item: ArticleStore.Chosen,
        publishedBy publishers: [String: SourceIdentity] = [:]
    ) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = item.title
        attributes.displayName = item.title

        // `contentDescription` is capped around three hundred characters, which
        // is why the whole text goes to `textContent` instead : that is what
        // Spotlight actually searches through.
        attributes.contentDescription = item.plainText.map { String($0.prefix(300)) }
        attributes.textContent = item.plainText
        attributes.contentCreationDate = item.publishedAt ?? item.markedAt
        attributes.contentModificationDate = item.markedAt
        attributes.contentURL = item.url
        attributes.identifier = item.id.uuidString

        if let author = item.author { attributes.authorNames = [author] }
        // The publisher rather than the desk, as everywhere else : an article
        // from `Le Monde - Sport` was published by Le Monde.
        let source = item.domain.flatMap { publishers[$0]?.name } ?? item.domain ?? item.feedTitle
        if let source, !source.isEmpty { attributes.contentSources = [source] }

        let searchable = CSSearchableItem(
            uniqueIdentifier: SpotlightResult.article(item.id).identifier,
            domainIdentifier: domain,
            attributeSet: attributes
        )
        // Nothing is purged any more, so neither is its index.
        searchable.expirationDate = Date.distantFuture
        return searchable
    }

    /// What Spotlight is told about a story on the front page.
    ///
    /// A story has no address of its own : it is several articles from several
    /// rooms, and the one thing it is not is a page on somebody's site. So no
    /// `contentURL`, and the result opens the story in Flong, where it exists.
    ///
    /// **It expires when it would leave the page.** A story is on the front page
    /// while its last article is inside the digest's window, so the item is
    /// given exactly that moment as its expiry. The page is written again
    /// whenever it changes and that is what normally keeps the two in step ; the
    /// expiry is what holds `no more and no less` true on a device that was put
    /// down for a week.
    static func searchableItem(
        for story: DigestStory,
        publishedBy publishers: [String: SourceIdentity] = [:]
    ) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = story.title
        attributes.displayName = story.title
        attributes.contentDescription = story.summary.map { String($0.prefix(300)) }
        attributes.textContent = story.summary
        attributes.contentCreationDate = story.firstAt
        attributes.contentModificationDate = story.lastAt
        attributes.identifier = story.id.uuidString

        // The subjects the model filed it under. A reader searching for one of
        // their own subjects is searching for the stories under it.
        if !story.topics.isEmpty { attributes.keywords = story.topics }

        // Every room covering it, named the way the application names it. A
        // story is who is talking about it as much as it is what happened.
        let rooms = story.feedMarks.map { publishers[$0.room]?.name ?? $0.room }.filter { !$0.isEmpty }
        if !rooms.isEmpty { attributes.contentSources = rooms }

        let searchable = CSSearchableItem(
            uniqueIdentifier: SpotlightResult.story(story.id).identifier,
            domainIdentifier: storyDomain,
            attributeSet: attributes
        )
        searchable.expirationDate = story.lastAt.addingTimeInterval(DigestStore.window)
        return searchable
    }

    /// A short summary of what is chosen, for Spotlight to hand back.
    ///
    /// **A digest and not a hash.** `Hasher` is seeded afresh in every process,
    /// so the same articles hashed at two launches gave two different answers
    /// and the check they were for never once said `nothing has changed` : the
    /// whole index was written again at every launch, which is precisely the
    /// work the client state exists to avoid.
    private static func state(of choices: [ArticleStore.Choice]) -> Data {
        var digest = SHA256()
        for choice in choices {
            withUnsafeBytes(of: choice.id.uuid) { digest.update(bufferPointer: $0) }
            withUnsafeBytes(of: choice.chosenAt.timeIntervalSinceReferenceDate.bitPattern) {
                digest.update(bufferPointer: $0)
            }
        }
        return Data(digest.finalize())
    }

    private func lastState() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            index.fetchLastClientState { state, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: state)
                }
            }
        }
    }

    private func endBatch(state: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            index.endBatch(withClientState: state) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

/// One rebuild of the index at a time, whoever asked for it.
///
/// **`beginBatch()` on an index that already has one open throws an
/// Objective-C exception, and an Objective-C exception is not a Swift error :
/// it terminates the process.** The same reason a named index is used rather
/// than the shared one, one paragraph up, and the same lack of a `catch` to put
/// round it. What is left is not letting it happen.
///
/// **Two rebuilds overlap easily.** The window asks for one when it opens, a
/// catch-up that brought articles asks for another, and singling out a source,
/// a writer or a newsmaker asks for one apiece. Every one of those is an
/// `await` on the main actor, and awaits interleave : `SpotlightIndex` is a
/// value, `CSSearchableIndex` behind it is not, and nothing in between was
/// holding anybody back. It was caught by a test run dying rather than by a
/// reader, which is luck rather than design.
///
/// The queue is a chain of tasks rather than a lock : each caller waits on
/// whatever was queued before it, and the tail forgets both the result and the
/// failure, since what the next caller is waiting for is the index being free
/// and not what the last one made of it.
///
/// Not private, so the one property that matters can be tested without going
/// anywhere near a real `CSSearchableIndex` : a test that reproduced the crash
/// would be a test that terminates the process it runs in.
actor IndexBatches {
    static let shared = IndexBatches()

    private var tail: Task<Void, Never>?

    func alone<Answer: Sendable>(_ work: @Sendable @escaping () async throws -> Answer) async throws -> Answer {
        let queued = tail
        let mine = Task {
            await queued?.value
            return try await work()
        }
        tail = Task { _ = try? await mine.value }

        return try await mine.value
    }
}
