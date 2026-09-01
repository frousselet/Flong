//
//  FeedParserTests.swift
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

@Suite("Feed parser")
struct FeedParserTests {
    private let source = URL(string: "https://feeds.example.com/feed.xml")!

    private func parse(_ name: String) throws -> ParsedFeed {
        try FeedParser.parse(try Fixtures.data("Feeds/\(name)"), url: source)
    }

    // MARK: - Formats

    @Test("RSS 2.0, with the modules publishers actually use")
    func rss2() throws {
        let feed = try parse("rss2.xml")

        #expect(feed.format == .rss)
        #expect(feed.title == "Example Weekly")
        #expect(feed.siteURL?.absoluteString == "https://example.com/")
        #expect(feed.language == "en-gb")
        #expect(feed.iconURL?.absoluteString == "https://example.com/logo.png")
        #expect(feed.items.count == 2)

        let first = try #require(feed.items.first)
        #expect(first.title == "The first post")
        #expect(first.guid == "urn:example:1")
        #expect(first.url?.absoluteString == "https://example.com/posts/1")
        #expect(first.author == "Alice Author")
        #expect(first.summaryHTML?.contains("<a href=\"/relative\">") == true)
        #expect(first.contentHTML?.contains("<p>The body.</p>") == true)
        #expect(
            first.enclosures == [
                Enclosure(url: URL(string: "https://example.com/media/1.mp3")!, type: "audio/mpeg", length: 1234)
            ])
        #expect(first.publishedAt == Date(timeIntervalSince1970: 1_787_639_400))
    }

    @Test("A name beats the address RSS puts in its author element, whichever came first")
    func bylinesPreferAName() throws {
        // RSS 2.0 defines `author` as the author's e-mail address and Dublin
        // Core's creator as a name, and feeds routinely carry both. Which of
        // them the parser met last is no reason to prefer it.
        func item(_ inner: String) throws -> ParsedItem {
            let feed = try FeedParser.parse(
                Data(
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
                      <channel><title>P</title><link>https://example.com/</link>
                        <item><title>T</title><guid>urn:1</guid>\(inner)</item>
                      </channel>
                    </rss>
                    """.utf8
                ),
                url: source
            )
            return try #require(feed.items.first)
        }

        let creatorLast = try item(
            "<author>lawyer@boyer.net</author><dc:creator>Lawyer Boyer</dc:creator>"
        )
        #expect(creatorLast.author == "Lawyer Boyer")

        let creatorFirst = try item(
            "<dc:creator>Lawyer Boyer</dc:creator><author>lawyer@boyer.net</author>"
        )
        #expect(creatorFirst.author == "Lawyer Boyer")

        // On its own the address is all there is, and what survives of it is
        // the person in the brackets. See `Author`.
        let alone = try item("<author>lawyer@boyer.net (Lawyer Boyer)</author>")
        #expect(Author.name(from: alone.author) == "Lawyer Boyer")
    }

    @Test("Atom, including the xhtml body")
    func atom() throws {
        let feed = try parse("atom.xml")

        #expect(feed.format == .atom)
        #expect(feed.title == "Journal")
        #expect(feed.siteURL?.absoluteString == "https://example.org/")
        #expect(feed.language == "fr")
        #expect(feed.iconURL?.absoluteString == "https://example.org/icon.png")

        let first = try #require(feed.items.first)
        #expect(first.guid == "tag:example.org,2026:1")
        #expect(first.url?.absoluteString == "https://example.org/1")
        #expect(first.author == "Bernard Auteur")
        #expect(first.contentHTML?.contains("<em>corps</em>") == true)
        #expect(first.enclosures.first?.type == "video/mp4")
        #expect(first.publishedAt == Date(timeIntervalSince1970: 1_787_639_400))

        // A text body is escaped, so it renders as the author typed it.
        #expect(feed.items.last?.contentHTML == "Texte &amp; caractères")
    }

    @Test("RSS 1.0 over RDF, where items sit outside the channel")
    func rss1() throws {
        let feed = try parse("rss1.xml")

        #expect(feed.format == .rss)
        #expect(feed.title == "Old School")
        #expect(feed.items.count == 1)
        #expect(feed.items.first?.author == "Claire")
        #expect(feed.items.first?.publishedAt != nil)
    }

    @Test("JSON Feed 1.1")
    func jsonFeed() throws {
        let feed = try FeedParser.parse(
            try Fixtures.data("Feeds/jsonfeed.json"),
            url: URL(string: "https://json.example.com/feed.json")!
        )

        #expect(feed.format == .jsonFeed)
        #expect(feed.title == "JSON Weekly")
        #expect(feed.items.count == 2)
        #expect(feed.items.first?.author == "Dana")
        #expect(feed.items.first?.enclosures.first?.length == 99)
        // Plain text content is escaped rather than served as markup.
        #expect(feed.items.last?.contentHTML == "Plain &lt;text&gt;")
    }

    @Test("An h-feed page is its own feed")
    func hFeed() throws {
        let feed = try FeedParser.parse(
            try Fixtures.data("Feeds/hfeed.html"),
            url: URL(string: "https://personal.example/")!
        )

        #expect(feed.format == .hFeed)
        #expect(feed.title == "Notes")
        #expect(feed.items.count == 2)

        let first = try #require(feed.items.first)
        #expect(first.title == "A note")
        #expect(first.url?.absoluteString == "https://personal.example/notes/1")
        #expect(first.author == "Erin")
        #expect(first.publishedAt != nil)
        // The comment nested inside the entry is not the article.
        #expect(first.contentHTML?.contains("comment") == false)
    }

    // MARK: - Broken feeds

    @Test("A bare ampersand does not lose the feed")
    func bareAmpersand() throws {
        let feed = try parse("broken-ampersand.xml")

        #expect(feed.title == "Cook & Book")
        #expect(feed.items.first?.title.map { $0.hasPrefix("Café") } == true)
        #expect(feed.items.first?.url?.absoluteString == "https://broken.example.com/1?a=1&b=2")
    }

    @Test("A declaration lying about the encoding does not lose the feed")
    func wrongEncoding() throws {
        let feed = try parse("broken-encoding.xml")

        #expect(feed.title == "Écrans")
        #expect(feed.items.first?.title == "Une soirée à Nîmes")
    }

    @Test("A control character does not lose the feed")
    func controlCharacters() throws {
        let feed = try parse("broken-control.xml")

        #expect(feed.title == "Bellringer")
        #expect(feed.items.count == 1)
    }

    @Test("An article with nothing stable to identify it is dropped")
    func identity() throws {
        let feed = try parse("no-identity.xml")

        #expect(feed.items.count == 2)
        #expect(feed.items[0].identity == "https://careless.example.com/2")
        // A link paired with a date, as section 4 of the specification states.
        #expect(feed.items[1].identity?.hasPrefix("https://careless.example.com/3#") == true)
    }

    @Test("A page that is not a feed is refused")
    func notAFeed() throws {
        #expect(throws: FeedParserError.notAFeed) {
            try FeedParser.parse(try Fixtures.data("Feeds/page.html"), url: source)
        }
        #expect(throws: FeedParserError.self) {
            try FeedParser.parse(Data("not a feed at all".utf8), url: source)
        }
    }

    @Test("A feed cut off halfway keeps what it got through")
    func truncatedFeed() throws {
        let whole = try Fixtures.text("Feeds/rss2.xml")
        let cut = String(
            whole.prefix(whole.range(of: "<item>", options: .backwards)!.lowerBound.utf16Offset(in: whole)))

        let feed = try FeedParser.parse(Data(cut.utf8), url: source)
        #expect(feed.items.count == 1)
    }
}

@Suite("Feed discovery")
struct FeedDiscoveryTests {
    @Test("A page states where its feeds are")
    func discovery() throws {
        let links = FeedDiscovery.links(
            in: try Fixtures.text("Feeds/page.html"),
            relativeTo: URL(string: "https://site.example/blog/")!
        )

        #expect(
            links.map(\.absoluteString) == [
                "https://site.example/feed.xml",
                "https://cdn.example.com/feed.json",
            ])
    }

    @Test("A page that states nothing leaves the usual locations to try")
    func candidates() {
        let candidates = FeedDiscovery.candidates(under: URL(string: "https://site.example/blog/post?x=1")!)

        #expect(candidates.first?.absoluteString == "https://site.example/feed")
        #expect(candidates.count == FeedDiscovery.commonPaths.count)
    }
}

@Suite("Feed dates")
struct FeedDatesTests {
    @Test(
        "The spellings publishers actually use are read",
        arguments: [
            "Tue, 25 Aug 2026 08:30:00 GMT",
            "Tue, 25 Aug 2026 08:30:00 +0000",
            "25 Aug 2026 08:30:00 GMT",
            "2026-08-25T08:30:00Z",
            "2026-08-25T08:30:00.000Z",
            "2026-08-25 08:30:00",
        ]
    )
    func spellings(text: String) {
        #expect(FeedDates.date(from: text) == Date(timeIntervalSince1970: 1_787_646_600))
    }

    @Test("A date that means nothing stays nothing")
    func nonsense() {
        // Real feeds, and two spellings the formats did not cover.
        //
        // `senat.fr` writes no space after the weekday's comma, and
        // `cert.europa.eu` names a European zone that a POSIX locale has never
        // heard of. Both left an article with no date, which sorts it on the
        // day it arrived : a hundred and thirty of them in one store, wearing
        // the moment they were pulled as though it were the moment they were
        // written.
        // The comma with nothing after it reads as the same instant as the one
        // written properly.
        #expect(
            FeedDates.date(from: "Fri,28 Aug 2026 01:03:20 GMT")
                == FeedDates.date(from: "Fri, 28 Aug 2026 01:03:20 GMT")
        )

        // And a European zone is the offset it stands for, summer time
        // included : seventeen o'clock in Brussels is fifteen in London.
        #expect(
            FeedDates.date(from: "Mon, 03 Aug 2026 17:00:00 CEST")
                == FeedDates.date(from: "Mon, 03 Aug 2026 15:00:00 GMT")
        )
        #expect(
            FeedDates.date(from: "Mon, 03 Aug 2026 17:00:00 CET")
                == FeedDates.date(from: "Mon, 03 Aug 2026 16:00:00 GMT")
        )

        // `CEST` is never read as `CET` with a letter left over.
        #expect(
            FeedDates.date(from: "Mon, 03 Aug 2026 17:00:00 CEST")
                != FeedDates.date(from: "Mon, 03 Aug 2026 17:00:00 CET"))

        // Ambiguous by nature, so left alone : Indian, Irish and Israeli
        // standard time are three different offsets, and a wrong date sorts an
        // article into the wrong week.
        #expect(FeedDates.date(from: "Mon, 03 Aug 2026 17:00:00 IST") == nil)

        #expect(FeedDates.date(from: "") == nil)
        #expect(FeedDates.date(from: "soon") == nil)
    }
}
