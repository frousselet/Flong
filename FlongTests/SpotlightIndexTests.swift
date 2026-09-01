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

/// What Spotlight is told about what the reader chose.
///
/// Whether Spotlight then finds it is the system's business and cannot be
/// asserted here : indexing is asynchronous, and a simulator often has no
/// indexer running at all. What is testable, and what actually breaks, is the
/// shape of what is handed over.
@Suite("Spotlight")
struct SpotlightIndexTests {
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    private func item() -> ArticleStore.Chosen {
        ArticleStore.Chosen(
            id: .v7(),
            title: "Une réforme du calendrier",
            plainText: String(repeating: "Le corps de l'article. ", count: 40),
            url: URL(string: "https://example.com/1"),
            author: "Camille Dupuis",
            feedTitle: "Le Quotidien",
            domain: "lequotidien.example.com",
            publishedAt: now.addingTimeInterval(-3600),
            markedAt: now
        )
    }

    @Test("A chosen article is described to Spotlight by what a reader would search for")
    func attributes() throws {
        let item = self.item()
        let searchable = SpotlightIndex.searchableItem(for: item)
        let attributes = searchable.attributeSet

        #expect(searchable.uniqueIdentifier == item.id.uuidString)
        #expect(searchable.domainIdentifier == SpotlightIndex.domain)
        #expect(attributes.title == "Une réforme du calendrier")
        #expect(attributes.authorNames == ["Camille Dupuis"])
        // Nothing known about the publisher yet, so the address stands in : it
        // is a name, and the feed's own title is the last resort.
        #expect(attributes.contentSources == ["lequotidien.example.com"])
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

    @Test("The system search names a source the way the application does")
    func publisherNamesTheSource() throws {
        let identity = SourceIdentity(
            domain: "lequotidien.example.com",
            name: "Le Quotidien",
            iconURL: nil,
            siteURL: URL(string: "https://lequotidien.example.com")
        )

        let attributes = SpotlightIndex.searchableItem(
            for: item(),
            publishedBy: ["lequotidien.example.com": identity]
        ).attributeSet

        // The publisher rather than the desk : an article that arrived through
        // `Le Quotidien - Sport` was published by Le Quotidien, and Spotlight
        // must not disagree with every row in the application.
        #expect(attributes.contentSources == ["Le Quotidien"])
    }

    @Test("What a purge never takes, Spotlight never expires")
    func expiry() throws {
        #expect(SpotlightIndex.searchableItem(for: item()).expirationDate == .distantFuture)
    }

    // MARK: - The stories

    private func story(summary: String? = "Trois rédactions en parlent depuis ce matin.") -> DigestStory {
        DigestStory(
            id: .v7(),
            title: "La rentrée décalée d'une semaine",
            summary: summary,
            isGenerated: true,
            articleCount: 6,
            feedMarks: [FeedMark(room: "lequotidien.example.com"), FeedMark(room: "lesoir.example.com")],
            feedCount: 2,
            firstAt: now.addingTimeInterval(-7200),
            lastAt: now,
            arrivals: [1, 2, 3],
            isLive: true,
            imageURL: nil,
            imageCredit: nil,
            topics: ["Éducation", "Politique"]
        )
    }

    @Test("A story is described to Spotlight by its headline, its subjects and its rooms")
    func storyAttributes() throws {
        let story = self.story()
        let identity = SourceIdentity(
            domain: "lequotidien.example.com",
            name: "Le Quotidien",
            iconURL: nil,
            siteURL: URL(string: "https://lequotidien.example.com")
        )
        let searchable = SpotlightIndex.searchableItem(
            for: story,
            publishedBy: ["lequotidien.example.com": identity]
        )
        let attributes = searchable.attributeSet

        #expect(searchable.domainIdentifier == SpotlightIndex.storyDomain)
        #expect(attributes.title == story.title)
        #expect(attributes.keywords == ["Éducation", "Politique"])
        // The rooms, named the way the application names them, and the address
        // where it knows no better.
        #expect(attributes.contentSources == ["Le Quotidien", "lesoir.example.com"])
        // A story is several articles from several rooms, so it is not a page
        // on anybody's site and must not pretend to be one.
        #expect(attributes.contentURL == nil)
    }

    @Test("A story leaves the index when it would leave the page")
    func storyExpiry() throws {
        let story = self.story()
        let searchable = SpotlightIndex.searchableItem(for: story)

        #expect(searchable.expirationDate == story.lastAt.addingTimeInterval(DigestStore.window))
        // Not the treatment an article gets : an article was chosen and is
        // kept, a story is on a page and ages off it.
        #expect(searchable.expirationDate != .distantFuture)
    }

    // MARK: - What a result stands for

    @Test("A result says which of the two things it is")
    func results() throws {
        let article = UUID.v7()
        let story = UUID.v7()

        // The article keeps the bare identifier it has always had, so nothing
        // already in the index is orphaned by the stories arriving beside it.
        #expect(SpotlightResult.article(article).identifier == article.uuidString)
        #expect(SpotlightResult(article.uuidString) == .article(article))

        #expect(SpotlightResult.story(story).identifier == "story/\(story.uuidString)")
        #expect(SpotlightResult(SpotlightResult.story(story).identifier) == .story(story))

        #expect(SpotlightResult("story/pas-un-identifiant") == nil)
        #expect(SpotlightResult("pas un identifiant du tout") == nil)
    }
}
