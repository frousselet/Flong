//
//  OPMLReaderTests.swift
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

@Suite("OPML reader")
struct OPMLReaderTests {
    private func read(_ opml: String) throws -> OPMLDocument {
        try OPMLReader.read(Data(opml.utf8))
    }

    @Test("A file keeps its title, and every feed at every level of it")
    func standardFile() throws {
        let document = try read(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head><title>Subscriptions</title></head>
              <body>
                <outline text="Tech" title="Tech">
                  <outline type="rss" text="Example" xmlUrl="https://feeds.example.com/1.xml"
                           htmlUrl="https://example.com"/>
                  <outline text="iOS">
                    <outline type="rss" text="Nested" xmlUrl="https://feeds.example.com/2.xml"/>
                  </outline>
                </outline>
                <outline type="rss" text="Loose" xmlUrl="https://feeds.example.com/3.xml"/>
              </body>
            </opml>
            """
        )

        #expect(document.title == "Subscriptions")

        let feeds = document.feeds
        #expect(
            feeds.map(\.address) == [
                "https://feeds.example.com/1.xml",
                "https://feeds.example.com/2.xml",
                "https://feeds.example.com/3.xml",
            ])
        #expect(feeds[0].title == "Example")
        #expect(feeds[0].siteAddress == "https://example.com")
    }

    @Test("Attributes are read whatever case they were written in")
    func attributeCase() throws {
        let document = try read(
            """
            <opml><body>
              <outline TYPE="RSS" TEXT="Shouting" XMLURL="https://feeds.example.com/1.xml"/>
              <outline text="Quiet" xmlurl="https://feeds.example.com/2.xml"/>
            </body></opml>
            """
        )

        #expect(document.feeds.map(\.title) == ["Shouting", "Quiet"])
    }

    @Test("An address makes a feed, whatever the type says")
    func typeIsNotASignal() throws {
        let document = try read(
            """
            <opml><body>
              <outline text="No type" xmlUrl="https://feeds.example.com/1.xml"/>
              <outline type="link" text="Wrong type" xmlUrl="https://feeds.example.com/2.xml"/>
              <outline type="rss" text="No address"/>
            </body></opml>
            """
        )

        #expect(document.feeds.count == 2)
    }

    @Test("The title attribute wins over the text one")
    func titleWinsOverText() throws {
        let document = try read(
            """
            <opml><body>
              <outline text="Fallback" title="Preferred" xmlUrl="https://feeds.example.com/1.xml"/>
            </body></opml>
            """
        )

        #expect(document.feeds.first?.title == "Preferred")
    }

    @Test("A folder outline is descended and not kept")
    func nestingIsWalkedThrough() throws {
        let document = try read(
            """
            <opml><body>
              <outline text="Filed" category="/Tech/iOS,/Veille" xmlUrl="https://feeds.example.com/1.xml"/>
              <outline text="Nested" category="/Ignored">
                <outline text="Inside" xmlUrl="https://feeds.example.com/2.xml"/>
              </outline>
            </body></opml>
            """
        )

        // A folder outline carries no address of its own, so it is not a feed ;
        // what it holds is, at whatever depth, and neither the nesting nor the
        // `category` attribute survives the reading. Flong groups sources by
        // the publisher serving them, which their own address already says.
        #expect(
            document.feeds.map(\.address) == [
                "https://feeds.example.com/1.xml",
                "https://feeds.example.com/2.xml",
            ])
        #expect(document.feeds.map(\.title) == ["Filed", "Inside"])
    }

    @Test("A bare ampersand does not lose the file")
    func bareAmpersandIsRepaired() throws {
        let document = try read(
            """
            <opml><body>
              <outline text="Cook & Book" xmlUrl="https://feeds.example.com/1.xml?a=1&b=2"/>
              <outline text="Caf&#233; &amp; Th&eacute;" xmlUrl="https://feeds.example.com/2.xml"/>
            </body></opml>
            """
        )

        #expect(document.feeds.count == 2)
        #expect(document.feeds[0].title == "Cook & Book")
        #expect(document.feeds[0].address == "https://feeds.example.com/1.xml?a=1&b=2")
        // A numeric entity is left alone ; an HTML one XML does not know is not.
        #expect(document.feeds[1].title.hasPrefix("Café"))
    }

    @Test("A control character does not lose the file")
    func controlCharacterIsRepaired() throws {
        let document = try read(
            "<opml><body><outline text=\"Bell\u{0007}ringer\" xmlUrl=\"https://feeds.example.com/1.xml\"/></body></opml>"
        )

        #expect(document.feeds.first?.title == "Bellringer")
    }

    @Test("A declaration lying about the encoding does not lose the file")
    func wrongEncodingIsRepaired() throws {
        let opml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml><body><outline text="Écrans" xmlUrl="https://feeds.example.com/1.xml"/></body></opml>
            """
        let latin1 = try #require(opml.data(using: .isoLatin1))

        let document = try OPMLReader.read(latin1)

        #expect(document.feeds.first?.title == "Écrans")
    }

    @Test("A file that is not a subscription list is refused")
    func refusals() {
        #expect(throws: OPMLError.unreadable) { try OPMLReader.read(Data("not xml at all <<<".utf8)) }
        #expect(throws: OPMLError.notOPML) { try OPMLReader.read(Data("<rss><channel/></rss>".utf8)) }
    }

    @Test("An empty subscription list holds no feed")
    func emptyBody() throws {
        let document = try read("<opml><head><title>Empty</title></head><body/></opml>")

        #expect(document.title == "Empty")
        #expect(document.feeds.isEmpty)
    }
}
