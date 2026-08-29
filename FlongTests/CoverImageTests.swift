//
//  CoverImageTests.swift
//  FlongTests
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

@Suite("Cover images")
struct CoverImageTests {
    private let source = URL(string: "https://feeds.example.com/covers.xml")!

    private func item(_ index: Int) throws -> ParsedItem {
        let feed = try FeedParser.parse(try Fixtures.data("Feeds/covers.xml"), url: source)
        return try #require(feed.items.dropFirst(index).first)
    }

    // MARK: - What the feed states

    @Test("A thumbnail is the article's picture, not a file attached to it")
    func thumbnail() throws {
        let item = try item(0)

        #expect(item.imageURL?.absoluteString == "https://example.com/covers/1.jpg")
        // Otherwise every article of an illustrated feed wears a media badge.
        #expect(item.enclosures.isEmpty)
    }

    @Test("Media content that is an image is both an attachment and the picture")
    func mediaContent() throws {
        let item = try item(1)

        #expect(item.imageURL?.absoluteString == "https://example.com/covers/2.jpg")
        #expect(item.enclosures.count == 1)
    }

    @Test("A podcast states its episode art the iTunes way")
    func itunesImage() throws {
        let item = try item(2)

        #expect(item.imageURL?.absoluteString == "https://example.com/covers/3.jpg")
        #expect(item.enclosures.first?.type == "audio/mpeg")
        #expect(CoverImage.of(item)?.absoluteString == "https://example.com/covers/3.jpg")
    }

    @Test("JSON Feed states an image, or a banner")
    func jsonFeed() throws {
        let feed = try FeedParser.parse(
            try Fixtures.data("Feeds/jsonfeed.json"),
            url: URL(string: "https://json.example.com/feed.json")!
        )

        #expect(feed.items.first?.imageURL?.absoluteString == "https://json.example.com/1.jpg")
        #expect(feed.items.last?.imageURL?.absoluteString == "https://json.example.com/2-banner.jpg")
    }

    @Test("An h-entry's photograph is not its author's face")
    func hFeedPhoto() throws {
        let feed = try FeedParser.parse(
            try Fixtures.data("Feeds/hfeed.html"),
            url: URL(string: "https://personal.example/")!
        )

        #expect(feed.items.first?.imageURL?.absoluteString == "https://personal.example/notes/1.jpg")
    }

    // MARK: - The order

    @Test("What the feed states beats what it encloses, which beats the body")
    func order() throws {
        let stated = URL(string: "https://example.com/stated.jpg")!
        let enclosed = Enclosure(url: URL(string: "https://example.com/enclosed.jpg")!, type: "image/jpeg")
        let body = "<p>Text</p><img src=\"https://example.com/body.jpg\" width=\"800\">"

        var item = ParsedItem(guid: "urn:example:1", title: "One")
        item.enclosures = [enclosed]
        item.imageURL = stated
        #expect(CoverImage.of(item, sanitizedHTML: body) == stated)

        item.imageURL = nil
        #expect(CoverImage.of(item, sanitizedHTML: body) == enclosed.url)

        item.enclosures = []
        #expect(CoverImage.of(item, sanitizedHTML: body)?.absoluteString == "https://example.com/body.jpg")

        #expect(CoverImage.of(item, sanitizedHTML: "<p>No picture at all.</p>") == nil)
        #expect(CoverImage.of(item) == nil)
    }

    @Test("A sound is not a picture, whether it says so or not")
    func soundsAreNotPictures() throws {
        var item = ParsedItem(guid: "urn:example:1", title: "One")
        item.enclosures = [
            Enclosure(url: URL(string: "https://example.com/1.mp3")!, type: "audio/mpeg"),
            Enclosure(url: URL(string: "https://example.com/2.m4v")!, type: nil),
            Enclosure(url: URL(string: "https://example.com/3.PNG")!, type: nil),
        ]

        // The third is judged on its address, the others being ruled out by a
        // stated type and by an address that is not one.
        #expect(CoverImage.of(item)?.absoluteString == "https://example.com/3.PNG")
    }

    // MARK: - The body

    @Test("Furniture in a body is not the article's picture")
    func furniture() {
        let html = """
            <p><img src="https://example.com/share.png" width="24" height="24"></p>
            <p><img src="https://example.com/rule.gif" height="8"></p>
            <figure><img src="https://example.com/photo.jpg" width="1200" height="800"></figure>
            """

        #expect(CoverImage.inBody(html)?.absoluteString == "https://example.com/photo.jpg")
    }

    @Test("A picture that states no size is taken at its word")
    func unstated() {
        let html = "<p><img src=\"https://example.com/photo.jpg\" alt=\"Something\"></p>"
        #expect(CoverImage.inBody(html)?.absoluteString == "https://example.com/photo.jpg")
    }

    @Test("Only an address Flong would follow is followed")
    func schemes() {
        let html = """
            <img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=">
            <img src="/relative.jpg">
            <img src="https://example.com/photo.jpg">
            """

        // The sanitizer resolves and vets addresses before this ever runs, so a
        // relative one here means a body that never went through it.
        #expect(CoverImage.inBody(html)?.absoluteString == "https://example.com/photo.jpg")
    }
}
