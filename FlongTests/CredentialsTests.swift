//
//  CredentialsTests.swift
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

@Suite("Credentials")
struct CredentialsTests {
    private let credentials = Credentials(
        serverURL: URL(string: "https://rss.example.com")!,
        username: "alice",
        password: "s3cret"
    )

    /// These values reach error paths and logs, where the password must not appear.
    @Test("The password is redacted when the value is printed")
    func redactedDescription() {
        let description = String(describing: credentials)
        #expect(!description.contains("s3cret"))
        #expect(description.contains("<redacted>"))
        #expect(description.contains("alice"))
    }

    @Test("Encoding and decoding preserves every field")
    func codingRoundTrip() throws {
        let data = try JSONEncoder().encode(credentials)
        #expect(try JSONDecoder().decode(Credentials.self, from: data) == credentials)
    }
}
