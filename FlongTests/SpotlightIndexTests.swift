//
//  SpotlightIndexTests.swift
//  FlongTests
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreSpotlight
import Foundation
import Testing

@testable import Flong

/// What Spotlight is told about a kept article.
///
/// Whether Spotlight then finds it is the system's business and cannot be
/// asserted here : indexing is asynchronous, and a simulator often has no
/// indexer running at all. What is testable, and what actually breaks, is the
/// shape of what is handed over.
@Suite("Spotlight")
struct SpotlightIndexTests {
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    private func item(annotated: Bool = false) -> LibraryItem {
        LibraryItem(
            entryID: .v7(),
            feedURL: URL(string: "https://quotidien.example.com/f.xml"),
            feedTitle: "Le Quotidien",
            guid: "urn:example:1",
            url: URL(string: "https://example.com/1"),
            title: "Une réforme du calendrier",
            author: "Camille Dupuis",
            language: "fr",
            publishedAt: now.addingTimeInterval(-3600),
            promotedAt: now,
            contentHTML: "<p>Le corps.</p>",
            plainText: String(repeating: "Le corps de l'article. ", count: 40),
            annotation: annotated ? "À relire" : nil
        )
    }

    @Test("A kept article is described to Spotlight by what a reader would search for")
    func attributes() throws {
        let item = self.item()
        let searchable = SpotlightIndex.searchableItem(for: item)
        let attributes = searchable.attributeSet

        #expect(searchable.uniqueIdentifier == item.id.uuidString)
        #expect(searchable.domainIdentifier == SpotlightIndex.domain)
        #expect(attributes.title == "Une réforme du calendrier")
        #expect(attributes.authorNames == ["Camille Dupuis"])
        #expect(attributes.contentSources == ["Le Quotidien"])
        #expect(attributes.contentURL == item.url)
        #expect(attributes.contentCreationDate == item.publishedAt)
    }

    @Test("The whole text goes where Spotlight searches, not where it is capped")
    func textContent() throws {
        let item = self.item()
        let attributes = SpotlightIndex.searchableItem(for: item).attributeSet

        // `contentDescription` is capped around three hundred characters, which
        // is why the body goes to `textContent` as well.
        #expect((attributes.contentDescription?.count ?? 0) <= 300)
        #expect(attributes.textContent == item.plainText)
        #expect((attributes.textContent?.count ?? 0) > 300)
    }

    @Test("What the library never purges, Spotlight never expires")
    func expiry() throws {
        #expect(SpotlightIndex.searchableItem(for: item()).expirationDate == .distantFuture)
    }
}
