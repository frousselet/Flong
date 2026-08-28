//
//  ServerAddressTests.swift
//  FlongTests
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

@Suite("Server address")
struct ServerAddressTests {
    @Test("A bare host is assumed to be served over HTTPS")
    func bareHost() {
        #expect(ServerAddress.normalized(from: "rss.example.com")?.absoluteString == "https://rss.example.com")
    }

    @Test("An explicit scheme is kept")
    func explicitScheme() {
        #expect(
            ServerAddress.normalized(from: "http://192.168.1.10:8080")?.absoluteString
                == "http://192.168.1.10:8080"
        )
    }

    /// The API path is appended to this URL, so a trailing slash would double the separator.
    @Test("Trailing slashes are dropped", arguments: ["https://rss.example.com/", "https://rss.example.com///"])
    func trailingSlashes(input: String) {
        #expect(ServerAddress.normalized(from: input)?.absoluteString == "https://rss.example.com")
    }

    @Test("Surrounding whitespace is ignored")
    func whitespace() {
        #expect(ServerAddress.normalized(from: "  rss.example.com  ")?.absoluteString == "https://rss.example.com")
    }

    @Test("A subpath is preserved, since an instance can be hosted under one")
    func subpath() {
        #expect(
            ServerAddress.normalized(from: "example.com/freshrss")?.absoluteString
                == "https://example.com/freshrss"
        )
    }

    @Test("Anything without a host is refused", arguments: ["", "   ", "https://", "not a host"])
    func rejected(input: String) {
        #expect(ServerAddress.normalized(from: input) == nil)
    }
}
