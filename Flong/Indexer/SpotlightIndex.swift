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
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Hands the library to Spotlight.
///
/// Section 11 of the specification gives Spotlight the library and only the
/// library : a few thousand items, which is what it is good at, against the
/// hundred and twenty five thousand of the stream, which it is not. Two things
/// come of it at once : what the reader kept turns up in the system search, and
/// the semantic matching Spotlight does is had for nothing.
///
/// The index is local to the device and never shared between the devices of one
/// account. Each of them indexes for itself.
///
/// `CSSearchableIndex` is a proxy for a system service and is safe to use from
/// any thread, which its headers have never said in a way the compiler can read.
/// The unchecked conformance says exactly that and nothing more.
nonisolated struct SpotlightIndex: @unchecked Sendable {
    /// Everything Flong writes goes under one domain, so it can all be taken
    /// back in one call.
    static let domain = "library"

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
    private let library: LibraryStore

    init(_ library: LibraryStore, index: CSSearchableIndex = CSSearchableIndex(name: SpotlightIndex.indexName)) {
        self.library = library
        self.index = index
    }

    static var isAvailable: Bool { CSSearchableIndex.isIndexingAvailable() }

    // MARK: - Keeping Spotlight in step

    /// Adds or replaces items in the index.
    func index(_ items: [LibraryItem]) async throws {
        guard Self.isAvailable, !items.isEmpty else { return }
        try await index.indexSearchableItems(items.map(Self.searchableItem))
    }

    /// Takes items out of it.
    func remove(_ ids: [UUID]) async throws {
        guard Self.isAvailable, !ids.isEmpty else { return }
        try await index.deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
    }

    /// Writes the whole library, and tells Spotlight what it now holds.
    ///
    /// The client state is kept **by Spotlight**, not by Flong. That is what
    /// makes this self healing : if Spotlight loses its index, it loses the
    /// state with it, and the next check sees a mismatch and writes everything
    /// again. An application that remembered the state itself would confidently
    /// skip the rebuild it most needed.
    func rebuild() async throws {
        guard Self.isAvailable else { return }
        let items = try await library.allItems()

        index.beginBatch()
        try await index.deleteAllSearchableItems()
        if !items.isEmpty {
            try await index.indexSearchableItems(items.map(Self.searchableItem))
        }
        try await endBatch(state: Self.state(of: items))

        Log.index.notice("Wrote \(items.count) kept articles to Spotlight")
    }

    /// Rebuilds only when Spotlight and the library disagree about what it holds.
    func rebuildIfNeeded() async throws {
        guard Self.isAvailable else { return }

        let items = try await library.allItems()
        let expected = Self.state(of: items)
        guard try await lastState() != expected else { return }

        try await rebuild()
    }

    // MARK: - Shapes

    /// What Spotlight is told about a kept article.
    static func searchableItem(for item: LibraryItem) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = item.title
        attributes.displayName = item.title

        // `contentDescription` is capped around three hundred characters, which
        // is why the whole text goes to `textContent` instead : that is what
        // Spotlight actually searches through.
        attributes.contentDescription = item.plainText.map { String($0.prefix(300)) }
        attributes.textContent = item.plainText
        attributes.contentCreationDate = item.publishedAt ?? item.promotedAt
        attributes.contentModificationDate = item.promotedAt
        attributes.contentURL = item.url
        attributes.identifier = item.id.uuidString

        if let author = item.author { attributes.authorNames = [author] }
        if let feedTitle = item.feedTitle { attributes.contentSources = [feedTitle] }

        let searchable = CSSearchableItem(
            uniqueIdentifier: item.id.uuidString,
            domainIdentifier: domain,
            attributeSet: attributes
        )
        // The library is never purged, so neither is its index.
        searchable.expirationDate = .distantFuture
        return searchable
    }

    /// A short summary of what the library holds, for Spotlight to hand back.
    private static func state(of items: [LibraryItem]) -> Data {
        var hasher = Hasher()
        hasher.combine(items.count)
        for item in items.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(item.id)
            hasher.combine(item.promotedAt)
        }
        return withUnsafeBytes(of: hasher.finalize()) { Data($0) }
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
