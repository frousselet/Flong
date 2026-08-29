//
//  HTMLSanitizerTests.swift
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

@Suite("HTML tokenizer and tree")
struct HTMLDocumentTests {
    @Test("Tags, attributes and text come apart")
    func tokenizing() {
        let tokens = HTMLTokenizer.tokens(in: "<p class=\"lead\">Hello <em>world</em></p>")

        #expect(
            tokens == [
                .startTag(name: "p", attributes: [HTMLAttribute(name: "class", value: "lead")], isSelfClosing: false),
                .text("Hello "),
                .startTag(name: "em", attributes: [], isSelfClosing: false),
                .text("world"),
                .endTag(name: "em"),
                .endTag(name: "p"),
            ])
    }

    @Test("Attributes are read however they were written")
    func attributeSpellings() {
        let tokens = HTMLTokenizer.tokens(in: "<a HREF=x.html title='Un caf&eacute;' hidden data-x=\"1\">")

        guard case .startTag(_, let attributes, _) = tokens.first else {
            Issue.record("No start tag")
            return
        }
        #expect(attributes.map(\.name) == ["href", "title", "hidden", "data-x"])
        #expect(attributes[0].value == "x.html")
        #expect(attributes[1].value == "Un café")
        #expect(attributes[2].value.isEmpty)
    }

    @Test("A stray angle bracket stays text")
    func strayAngleBracket() {
        let document = HTMLDocument("<p>5 < 6 and 7 > 6</p>")
        #expect(document.textContent == "5 < 6 and 7 > 6")
    }

    @Test("What a script holds is never markup")
    func scriptContentIsText() {
        let document = HTMLDocument("<div><script>if (a < b) { alert('<img src=x>') }</script>Text</div>")

        #expect(document.elements(named: "img").isEmpty)
        #expect(document.textContent == "Text")
    }

    @Test("Elements that cannot nest close each other")
    func implicitClosing() {
        let document = HTMLDocument("<ul><li>One<li>Two</ul><p>First<p>Second")

        #expect(document.elements(named: "li").count == 2)
        #expect(document.elements(named: "li").map(\.textContent) == ["One", "Two"])
        #expect(document.elements(named: "p").map(\.textContent) == ["First", "Second"])
    }

    @Test("An end tag that closes nothing is dropped")
    func strayEndTag() {
        let document = HTMLDocument("<p>Text</span> more</p>")
        #expect(document.elements(named: "p").first?.textContent == "Text more")
    }

    @Test("An element left open is closed by its parent")
    func unclosedElement() {
        let document = HTMLDocument("<div><p>Text</div>")
        #expect(document.elements(named: "div").first?.textContent == "Text")
    }
}

@Suite("HTML sanitizer")
struct HTMLSanitizerTests {
    private let base = URL(string: "https://example.com/posts/1")!

    @Test("Ordinary markup goes through untouched")
    func markupSurvives() {
        let html = "<p>A <strong>bold</strong> claim.</p><ul><li>One</li></ul>"
        #expect(HTMLSanitizer.sanitize(html) == html)
    }

    @Test(
        "A script, a frame or a form goes, and takes its content with it",
        arguments: [
            "<script>alert(1)</script>",
            "<iframe src=\"https://ads.example.com\"></iframe>",
            "<form action=\"/x\"><input name=\"card\"><button>Pay</button></form>",
            "<style>body { display: none }</style>",
            "<svg onload=\"alert(1)\"><circle/></svg>",
            "<object data=\"x.swf\"></object>",
        ]
    )
    func dangerousElementsAreDropped(html: String) {
        #expect(HTMLSanitizer.sanitize("<p>Before</p>\(html)<p>After</p>") == "<p>Before</p><p>After</p>")
    }

    @Test("An attribute that is not on the list does not survive")
    func attributesAreWhitelisted() {
        let sanitized = HTMLSanitizer.sanitize(
            "<p onclick=\"steal()\" style=\"position:fixed\" class=\"ad\" id=\"x\" lang=\"fr\">Text</p>"
        )
        #expect(sanitized == "<p lang=\"fr\">Text</p>")
    }

    @Test(
        "An address that is not one Flong follows is not a link",
        arguments: [
            "javascript:alert(1)",
            "data:text/html;base64,PHNjcmlwdD4=",
            "vbscript:msgbox(1)",
            "file:///etc/passwd",
        ]
    )
    func dangerousSchemes(address: String) {
        let sanitized = HTMLSanitizer.sanitize("<a href=\"\(address)\">Click</a>")
        #expect(sanitized == "Click")
    }

    @Test("A relative address is resolved against the article")
    func relativeAddresses() {
        let sanitized = HTMLSanitizer.sanitize(
            "<a href=\"../other\">There</a><img src=\"/media/1.png\" alt=\"\">",
            relativeTo: base
        )

        #expect(sanitized.contains("href=\"https://example.com/other\""))
        #expect(sanitized.contains("src=\"https://example.com/media/1.png\""))
    }

    @Test("A link out of the article hands nothing to where it goes")
    func linksCarryRel() {
        let sanitized = HTMLSanitizer.sanitize("<a href=\"https://example.com/\" target=\"_blank\">There</a>")

        #expect(sanitized == "<a href=\"https://example.com/\" rel=\"noopener noreferrer\">There</a>")
    }

    @Test(
        "An image sized to disappear is a tracker, not an image",
        arguments: [
            "<img src=\"https://track.example.com/p.gif\" width=\"1\" height=\"1\">",
            "<img src=\"https://track.example.com/p.gif\" height=\"0\">",
            "<img src=\"https://track.example.com/p.gif\" width=\"1px\">",
        ]
    )
    func trackingPixels(html: String) {
        #expect(HTMLSanitizer.sanitize("<p>Text</p>\(html)") == "<p>Text</p>")
    }

    @Test("An image is kept when it is meant to be looked at")
    func realImagesSurvive() {
        let html = "<img src=\"https://example.com/photo.jpg\" alt=\"A photo\" width=\"640\" height=\"480\">"
        let sanitized = HTMLSanitizer.sanitize(html)

        #expect(sanitized.contains("alt=\"A photo\""))
        #expect(sanitized.contains("width=\"640\""))
    }

    @Test("An unknown element is unwrapped rather than lost")
    func unknownElementsAreUnwrapped() {
        #expect(HTMLSanitizer.sanitize("<center><font size=\"3\">Text</font></center>") == "Text")
        #expect(HTMLSanitizer.sanitize("<my-widget>Text</my-widget>") == "Text")
    }

    @Test("Text that looks like markup is escaped, not executed")
    func textIsEscaped() {
        #expect(HTMLSanitizer.sanitize("<p>5 &lt; 6 &amp; 7 &gt; 6</p>") == "<p>5 &lt; 6 &amp; 7 &gt; 6</p>")
    }

    @Test("Sanitizing twice changes nothing")
    func idempotence() {
        let once = HTMLSanitizer.sanitize(
            "<div><p>Text <a href=\"/x\">link</a></p><script>x</script></div>",
            relativeTo: base
        )
        #expect(HTMLSanitizer.sanitize(once, relativeTo: base) == once)
    }

    @Test("Plain text keeps the shape of the article")
    func plainText() {
        let text = HTMLSanitizer.plainText(
            "<h1>Title</h1><p>First   line<br>second line</p><script>alert(1)</script><ul><li>One</li></ul>"
        )

        #expect(text == "Title\nFirst line\nsecond line\nOne")
    }

    @Test("An excerpt stops on a word")
    func excerpt() {
        let excerpt = HTMLSanitizer.excerpt("<p>The quick brown fox jumps over the lazy dog</p>", limit: 20)

        #expect(excerpt == "The quick brown fox")
    }
}
