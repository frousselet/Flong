//
//  CredentialTests.swift
//  FlongTests
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

@Suite("What a paid feed needs to prove")
struct CredentialTests {
    // MARK: - The secret, and what stands in for it

    @Test("A secret address is masked to something the database may hold")
    func masking() throws {
        let secret = URL(string: "https://rss.example.com/u/9f3c2a11d4e5/feed.xml")!
        let masked = try #require(MaskedURL.mask(secret))

        // The origin the reader recognizes, and nothing of the secret.
        #expect(masked.host() == "rss.example.com")
        #expect(!masked.absoluteString.contains("9f3c2a11d4e5"))
        #expect(MaskedURL.isMasked(masked))

        // A real address is not mistaken for one of these.
        #expect(!MaskedURL.isMasked(secret))
        #expect(!MaskedURL.isMasked(URL(string: "https://rss.example.com/private/notadigest")!))
    }

    @Test("Two secret addresses on one platform stay two subscriptions")
    func maskingIsUnique() throws {
        let first = try #require(MaskedURL.mask(URL(string: "https://rss.example.com/u/aaa/feed.xml")!))
        let second = try #require(MaskedURL.mask(URL(string: "https://rss.example.com/u/bbb/feed.xml")!))

        #expect(first != second)
        // And the same address masks the same way every time, or a feed would
        // become a second feed on the next launch.
        #expect(MaskedURL.mask(URL(string: "https://rss.example.com/u/aaa/feed.xml")!) == first)
    }

    @Test("A masked address is a canonical one, so everything built on that works")
    func maskedIsCanonical() throws {
        let masked = try #require(MaskedURL.mask(URL(string: "https://rss.example.com/u/aaa/feed.xml")!))
        #expect(throws: Never.self) { try FeedURL.canonical(masked) }
    }

    // MARK: - What a request carries

    @Test("Each kind of credential is presented the way its platform asks")
    func headers() throws {
        let basic = FeedCredential.basic(user: "alice", password: "s3cret")
        let header = try #require(basic.header)

        #expect(header.name == "Authorization")
        // `alice:s3cret` in base64, which is what Basic is.
        #expect(header.value == "Basic YWxpY2U6czNjcmV0")

        #expect(FeedCredential.bearer("t0ken").header?.value == "Bearer t0ken")
        #expect(FeedCredential.header(name: "X-Auth", value: "k").header?.name == "X-Auth")

        // The secret was the address, and is spent before a request exists.
        #expect(FeedCredential.secretURL(URL(string: "https://a.example.com/s")!).header == nil)
    }

    @Test("What the interface says about a credential is never the credential")
    func summaries() {
        let credentials: [FeedCredential] = [
            .secretURL(URL(string: "https://rss.example.com/u/9f3c2a11/feed.xml")!),
            .basic(user: "alice", password: "s3cret"),
            .bearer("t0ken"),
            .header(name: "X-Auth", value: "k"),
        ]

        for credential in credentials {
            let shown = String(localized: credential.summary)
            #expect(!shown.contains("s3cret"))
            #expect(!shown.contains("t0ken"))
            #expect(!shown.contains("9f3c2a11"))
        }
        // A name is not a secret, and saying it is what makes the entry legible.
        #expect(String(localized: FeedCredential.basic(user: "alice", password: "s").summary).contains("alice"))
    }

    // MARK: - Keeping them

    @Test("A credential is kept, given back, and taken away")
    func storing() throws {
        let store = MemoryCredentials()
        let feed = UUID.v7()

        #expect(try store.credential(for: feed) == nil)
        #expect(try store.identifiers().isEmpty)

        try store.setCredential(.basic(user: "alice", password: "s3cret"), for: feed)
        #expect(try store.credential(for: feed) == .basic(user: "alice", password: "s3cret"))
        #expect(try store.identifiers() == [feed])

        try store.setCredential(.bearer("t0ken"), for: feed)
        #expect(try store.credential(for: feed) == .bearer("t0ken"))

        try store.setCredential(nil, for: feed)
        #expect(try store.credential(for: feed) == nil)
        #expect(try store.identifiers().isEmpty)
    }

    @Test("Every kind survives being written down and read back")
    func roundTrip() throws {
        let store = MemoryCredentials()
        let credentials: [FeedCredential] = [
            .secretURL(URL(string: "https://rss.example.com/u/9f3c2a11/feed.xml")!),
            .basic(user: "alice", password: "s3cret"),
            .bearer("t0ken"),
            .header(name: "X-Auth", value: "k"),
        ]

        for credential in credentials {
            let id = UUID.v7()
            try store.setCredential(credential, for: id)
            #expect(try store.credential(for: id) == credential)
        }
    }
}

/// The keychain itself, where the environment allows it.
///
/// A keychain refuses to answer at all in some test environments, and a suite
/// that fails for want of an entitlement says nothing about the code. This one
/// checks whether it works before asserting anything about it.
@Suite("The keychain, where there is one", .serialized)
struct KeychainCredentialTests {
    private static var isAvailable: Bool {
        let store = KeychainCredentials(service: "com.rslt.Flong.tests.probe")
        let id = UUID.v7()
        defer { try? store.setCredential(nil, for: id) }

        do {
            try store.setCredential(.bearer("probe"), for: id)
            return try store.credential(for: id) == .bearer("probe")
        } catch {
            return false
        }
    }

    @Test("A secret goes to the keychain and comes back", .enabled(if: KeychainCredentialTests.isAvailable))
    func keychainRoundTrip() throws {
        let store = KeychainCredentials(service: "com.rslt.Flong.tests.\(UUID().uuidString)")
        let feed = UUID.v7()
        defer { try? store.setCredential(nil, for: feed) }

        try store.setCredential(.basic(user: "alice", password: "s3cret"), for: feed)

        #expect(try store.credential(for: feed) == .basic(user: "alice", password: "s3cret"))
        #expect(try store.identifiers().contains(feed))

        // Written twice is stored once : the second write updates rather than
        // adding a duplicate the reader could never see or remove.
        try store.setCredential(.bearer("t0ken"), for: feed)
        #expect(try store.credential(for: feed) == .bearer("t0ken"))
        #expect(try store.identifiers().filter { $0 == feed }.count == 1)
    }
}

@Suite("What the reader has chosen")
struct PreferenceTests {
    private func preferences() -> Preferences {
        // A defaults of its own, and no iCloud : what a device with no account
        // has, which is a device Flong works perfectly well on.
        let defaults = UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        return Preferences(cloud: nil, local: defaults)
    }

    @Test("An article opens on what the feed sent until the reader says otherwise")
    func theDefault() {
        #expect(preferences().articleBody == .feed)
    }

    @Test("A choice is remembered")
    func remembered() {
        let store = preferences()

        store.articleBody = .page
        #expect(store.articleBody == .page)

        store.articleBody = .feed
        #expect(store.articleBody == .feed)
    }

    @Test("A value nobody wrote, or one nobody recognizes, is the default")
    func unreadableValue() {
        let defaults = UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        defaults.set("something else entirely", forKey: "article.body")

        // A version that wrote something this one does not know is not a reason
        // to open an article on nothing.
        #expect(Preferences(cloud: nil, local: defaults).articleBody == .feed)
    }
}
