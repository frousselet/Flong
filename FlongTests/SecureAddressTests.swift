//
//  SecureAddressTests.swift
//  FlongTests
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import Testing

@testable import Flong

/// Raising what the application fetches to TLS.
///
/// App Transport Security refuses a plain `http` request outright, and the
/// refusal is a `-1022` in the console rather than anything a reader can act
/// on : the picture is simply missing and nothing says why. A feed written
/// years ago states `http` for its pictures long after the site started
/// serving TLS, and the old address goes on working in a browser only because
/// the server redirects, which `URLSession` never gets far enough to be told.
@Suite("Addresses raised to TLS")
struct SecureAddressTests {
    @Test("A plain address is raised, and everything about it is left alone")
    func raised() throws {
        let raised = HTTPURL.secured(URL(string: "http://photorumors.com/wp/a-550x365.jpg?v=2#top")!)

        #expect(raised.absoluteString == "https://photorumors.com/wp/a-550x365.jpg?v=2#top")
    }

    @Test("An address already over TLS is untouched")
    func alreadySecure() {
        let url = URL(string: "https://example.com/a.jpg")!
        #expect(HTTPURL.secured(url) == url)
    }

    @Test("A port and a credential-free host survive the raise")
    func awkwardAddresses() throws {
        #expect(
            HTTPURL.secured(URL(string: "http://example.com:8080/a.jpg")!).absoluteString
                == "https://example.com:8080/a.jpg")
        // Not an address a server answers, and not one to rewrite either.
        let data = URL(string: "data:image/gif;base64,R0lGOD")!
        #expect(HTTPURL.secured(data) == data)
    }
}

@Suite("What an article is allowed to fetch")
struct SanitizerSchemeTests {
    @Test("A picture stated over plain http is raised to TLS")
    func pictures() {
        let html = HTMLSanitizer.sanitize(#"<p><img src="http://example.com/a.jpg" alt="A"></p>"#)

        #expect(html.contains(#"src="https://example.com/a.jpg""#))
        #expect(!html.contains("http://"))
    }

    @Test("A poster is raised too, being fetched the same way")
    func posters() {
        let html = HTMLSanitizer.sanitize(
            #"<video src="http://example.com/v.mp4" poster="http://example.com/p.jpg" controls></video>"#
        )

        #expect(html.contains(#"poster="https://example.com/p.jpg""#))
        #expect(html.contains(#"src="https://example.com/v.mp4""#))
    }

    @Test("A link is left exactly as the publisher wrote it")
    func links() {
        let html = HTMLSanitizer.sanitize(#"<a href="http://example.com/page">Là</a>"#)

        // It is handed to the browser, which is not bound by this policy and
        // has its own opinion about upgrading. Rewriting it would break the few
        // sites that genuinely serve nothing but `http`.
        #expect(html.contains(#"href="http://example.com/page""#))
    }

    @Test("A relative picture is still resolved against its article, then raised")
    func relative() {
        let html = HTMLSanitizer.sanitize(
            #"<img src="/wp/a.jpg">"#,
            relativeTo: URL(string: "http://example.com/article")
        )

        #expect(html.contains(#"src="https://example.com/wp/a.jpg""#))
    }
}

@Suite("The pictures already written down")
struct SecurePicturesMigrationTests {
    @Test("A stored article's pictures are raised, and its links are not")
    func migrated() throws {
        let queue = try DatabaseQueue()
        // The schema as it stood before anything raised an address.
        try AppDatabase.migrator.migrate(queue, upTo: "v19.marksThatArriveFirst")

        let feed = UUID.v7()
        let entry = UUID.v7()
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO feed (id, url, title, folder, created_at) VALUES (?, ?, ?, NULL, ?)",
                arguments: [feed, "https://feeds.example.com/f.xml", "A", Date()]
            )
            try db.execute(
                sql: "INSERT INTO entry (id, feed_id, guid, title, received_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [entry, feed, "urn:1", "Un article", Date()]
            )
            try db.execute(
                sql: "INSERT INTO entry_body (entry_id, sanitized_html, extracted_html) VALUES (?, ?, ?)",
                arguments: [
                    entry,
                    #"<p><img src="http://example.com/a.jpg"> <a href="http://example.com/p">là</a></p>"#,
                    #"<video poster="http://example.com/p.jpg"></video>"#,
                ]
            )
        }

        try AppDatabase.migrator.migrate(queue)

        let body = try queue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT sanitized_html, extracted_html FROM entry_body WHERE entry_id = ?",
                arguments: [entry]
            )
        }
        let sanitized = try #require(body?["sanitized_html"] as String?)
        let extracted = try #require(body?["extracted_html"] as String?)

        // Nothing would ever sanitize these again, so the articles a reader is
        // looking at now would have kept their holes.
        #expect(sanitized.contains(#"src="https://example.com/a.jpg""#))
        #expect(extracted.contains(#"poster="https://example.com/p.jpg""#))
        // The link is the publisher's, and stays theirs.
        #expect(sanitized.contains(#"href="http://example.com/p""#))
    }
}
