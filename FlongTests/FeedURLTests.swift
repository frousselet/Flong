//
//  FeedURLTests.swift
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

@Suite("Feed URL")
struct FeedURLTests {
    @Test(
        "Spellings that mean the same address collapse into one",
        arguments: [
            ("feeds.example.com/atom.xml", "https://feeds.example.com/atom.xml"),
            ("  https://feeds.example.com/atom.xml  ", "https://feeds.example.com/atom.xml"),
            ("HTTPS://Feeds.Example.COM/Atom.xml", "https://feeds.example.com/Atom.xml"),
            ("https://feeds.example.com.:443/atom.xml", "https://feeds.example.com/atom.xml"),
            ("http://feeds.example.com:80/atom.xml", "http://feeds.example.com/atom.xml"),
            ("https://feeds.example.com", "https://feeds.example.com/"),
            ("https://feeds.example.com/atom.xml#recent", "https://feeds.example.com/atom.xml"),
            ("https://feeds.example.com/atom.xml?", "https://feeds.example.com/atom.xml"),
            ("feed://feeds.example.com/atom.xml", "https://feeds.example.com/atom.xml"),
            ("feed:https://feeds.example.com/atom.xml", "https://feeds.example.com/atom.xml"),
        ]
    )
    func canonicalForm(address: String, expected: String) throws {
        #expect(try FeedURL.canonical(address).absoluteString == expected)
    }

    @Test(
        "What carries meaning is left alone",
        arguments: [
            "http://feeds.example.com/atom.xml",
            "https://feeds.example.com:8443/atom.xml",
            "https://feeds.example.com/atom.xml?format=rss&lang=fr",
            "https://feeds.example.com/atom/",
        ]
    )
    func meaningfulPartsSurvive(address: String) throws {
        #expect(try FeedURL.canonical(address).absoluteString == address)
    }

    @Test("Canonicalizing twice changes nothing")
    func idempotence() throws {
        let once = try FeedURL.canonical("FEED://Feeds.Example.com:443/atom.xml#top")
        #expect(try FeedURL.canonical(once) == once)
    }

    @Test("An address that is not a feed URL is refused")
    func rejections() {
        #expect(throws: FeedURLError.empty) { try FeedURL.canonical("   ") }
        #expect(throws: FeedURLError.malformed) { try FeedURL.canonical("not an address") }
        #expect(throws: FeedURLError.malformed) { try FeedURL.canonical("https://") }
        #expect(throws: FeedURLError.unsupportedScheme("ftp")) {
            try FeedURL.canonical("ftp://feeds.example.com/atom.xml")
        }
        #expect(throws: FeedURLError.unsupportedScheme("javascript")) {
            try FeedURL.canonical("javascript:alert(1)")
        }
    }

    @Test("A password in the address is refused rather than stored")
    func credentialsAreRefused() {
        #expect(throws: FeedURLError.embeddedCredentials) {
            try FeedURL.canonical("https://alice:hunter2@feeds.example.com/atom.xml")
        }
    }
}

@Suite("Folder path")
struct FolderPathTests {
    @Test(
        "A path is trimmed down to its components",
        arguments: [
            ("Tech", "Tech"),
            ("/Tech/iOS/", "Tech/iOS"),
            ("Tech//iOS", "Tech/iOS"),
            (" Tech / iOS ", "Tech/iOS"),
        ]
    )
    func normalization(raw: String, expected: String) {
        #expect(FolderPath.normalized(raw) == expected)
    }

    @Test("A path holding nothing is no folder at all")
    func emptyPaths() {
        #expect(FolderPath.normalized(nil) == nil)
        #expect(FolderPath.normalized("") == nil)
        #expect(FolderPath.normalized("  /  / ") == nil)
    }

    @Test("A folder knows its name and the folders above it")
    func nameAndAncestors() {
        #expect(FolderPath.name(of: "Tech/iOS/SwiftUI") == "SwiftUI")
        #expect(FolderPath.ancestors(of: "Tech/iOS/SwiftUI") == ["Tech", "Tech/iOS"])
        #expect(FolderPath.ancestors(of: "Tech").isEmpty)
    }
}
