//
//  SecretParameterTests.swift
//  FlongTests
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

/// What comes off an address on the way out, and what stays on it.
@Suite("Secret parameters")
struct SecretParameterTests {

    // MARK: - The designation

    @Test("A name is folded, so one designation covers every spelling of it")
    func foldsNames() {
        var designated = SecretParameters(["Token", "  USER  "])

        #expect(designated.contains("token"))
        #expect(designated.contains("TOKEN"))
        #expect(designated.contains("user"))

        designated.insert("Key")
        #expect(designated.contains("key"))

        designated.remove("KEY")
        #expect(!designated.contains("key"))
    }

    @Test("A name that is only whitespace is not a name")
    func refusesEmptyNames() {
        var designated = SecretParameters(["", "   ", "token"])
        #expect(designated.names == ["token"])

        designated.insert("  ")
        #expect(designated.names == ["token"])
    }

    @Test("The names of an address are offered in the order it carries them")
    func listsNames() throws {
        let url = try #require(URL(string: "https://feeds.example.com/rss?format=atom&token=abc&page=2"))
        #expect(SecretParameters.names(of: url) == ["format", "token", "page"])
    }

    @Test("A name repeated in one address is offered once")
    func listsNamesOnce() throws {
        let url = try #require(URL(string: "https://feeds.example.com/rss?tag=a&tag=b"))
        #expect(SecretParameters.names(of: url) == ["tag"])
    }

    @Test("An address with no query has nothing to ask the reader about")
    func listsNothing() throws {
        let url = try #require(URL(string: "https://feeds.example.com/rss"))
        #expect(SecretParameters.names(of: url).isEmpty)
    }

    // MARK: - What leaves

    @Test("What the reader designated comes off")
    func removesDesignated() throws {
        let url = try #require(URL(string: "https://example.com/article/1?token=s3cr3t&page=2"))
        let stripped = PublicURL.of(url, without: SecretParameters(["token"]))

        #expect(stripped.absoluteString == "https://example.com/article/1?page=2")
    }

    /// The whole reason this is a designation and not a heuristic.
    ///
    /// `docs/technical/feed-identity.md` keeps the query string because it
    /// selects the feed on plenty of sites. A parameter nobody designated is a
    /// parameter that stays, whatever it looks like.
    @Test("What nobody designated stays, however much it looks like a secret")
    func keepsUndesignated() throws {
        let url = try #require(URL(string: "https://example.com/feed?format=rss&key=abcdef123456"))
        let stripped = PublicURL.of(url, without: SecretParameters(["token"]))

        #expect(stripped.absoluteString == "https://example.com/feed?format=rss&key=abcdef123456")
    }

    @Test("An address with nothing designated keeps everything but its tracking")
    func keepsEverythingWithoutADesignation() throws {
        let url = try #require(URL(string: "https://example.com/article/1?page=2&utm_source=newsletter"))
        #expect(PublicURL.of(url).absoluteString == "https://example.com/article/1?page=2")
    }

    @Test("Tracking comes off whether anything was designated or not")
    func removesTracking() throws {
        let url = try #require(URL(string: "https://example.com/a?utm_campaign=x&fbclid=y&id=7"))
        #expect(PublicURL.of(url, without: SecretParameters(["token"])).absoluteString == "https://example.com/a?id=7")
    }

    @Test("A designation is matched whatever case the address spells it in")
    func removesWhateverTheCase() throws {
        let url = try #require(URL(string: "https://example.com/a?Token=s3cr3t&id=7"))
        #expect(PublicURL.of(url, without: SecretParameters(["token"])).absoluteString == "https://example.com/a?id=7")
    }

    @Test("Every occurrence of a designated name comes off, not only the first")
    func removesEveryOccurrence() throws {
        let url = try #require(URL(string: "https://example.com/a?token=one&id=7&token=two"))
        #expect(PublicURL.of(url, without: SecretParameters(["token"])).absoluteString == "https://example.com/a?id=7")
    }

    /// An empty query is no query, which is what a canonical address says too.
    @Test("An address left with no parameters is left with no question mark")
    func dropsAnEmptyQuery() throws {
        let url = try #require(URL(string: "https://example.com/article/1?token=s3cr3t"))
        let stripped = PublicURL.of(url, without: SecretParameters(["token"]))

        #expect(stripped.absoluteString == "https://example.com/article/1")
    }

    @Test("An address with no query at all is handed back as it was")
    func leavesAPlainAddressAlone() throws {
        let url = try #require(URL(string: "https://example.com/article/1#comments"))
        #expect(PublicURL.of(url, without: SecretParameters(["token"])) == url)
    }

    /// The one place a secret sits in an address without being a parameter.
    @Test("A credential written into the address itself comes off")
    func removesUserInfo() throws {
        let url = try #require(URL(string: "https://reader:p4ssw0rd@example.com/feed?id=7"))
        #expect(PublicURL.of(url).absoluteString == "https://example.com/feed?id=7")
    }

    @Test("The path, the port and the fragment are none of this function's business")
    func keepsTheRest() throws {
        let url = try #require(URL(string: "https://example.com:8443/a/b/c?token=x&id=7#part-2"))
        let stripped = PublicURL.of(url, without: SecretParameters(["token"]))

        #expect(stripped.absoluteString == "https://example.com:8443/a/b/c?id=7#part-2")
    }

    // MARK: - What the reader is shown before they answer

    /// The screen exists because some of these are secrets, so it is a strange
    /// place to print one where it can be read over a shoulder.
    @Test("A value is shown with enough of it to recognize and not enough to use")
    func masksAValue() {
        #expect(AddressParameter.mask("rss") == "•••")
        #expect(AddressParameter.mask("s3cr3ttoken") == "s3•••••••••")
        // A long one says only that it is long.
        #expect(AddressParameter.mask(String(repeating: "x", count: 64)) == "xx" + String(repeating: "•", count: 12))
    }

    @Test("A parameter with nothing in it still shows as a parameter")
    func masksAnEmptyValue() {
        #expect(AddressParameter.mask("") == "•")
    }

    // MARK: - Where they are kept

    @Test("A designation is kept per feed, and given back per feed")
    func keepsPerFeed() throws {
        let store = MemoryCredentials()
        let one = UUID()
        let other = UUID()

        try store.setSecretParameters(SecretParameters(["token"]), for: one)
        try store.setSecretParameters(SecretParameters(["sig", "user"]), for: other)

        #expect(try store.secretParameters(for: one)?.names == ["token"])
        #expect(try store.secretParameters(for: other)?.names == ["sig", "user"])
        #expect(try store.secretParameters(for: UUID()) == nil)
        #expect(try store.everySecretParameter().count == 2)
    }

    @Test("A designation of nothing is no designation")
    func storesNoEmptyDesignation() throws {
        let store = MemoryCredentials()
        let id = UUID()

        try store.setSecretParameters(SecretParameters(["token"]), for: id)
        try store.setSecretParameters(SecretParameters(), for: id)

        #expect(try store.secretParameters(for: id) == nil)
    }

    @Test("A designation is not a credential, and neither stands for the other")
    func staysBesideTheCredential() throws {
        let store = MemoryCredentials()
        let id = UUID()

        try store.setSecretParameters(SecretParameters(["token"]), for: id)

        // The interface says a feed is authenticated from this, and a feed
        // whose links carry a token is not thereby an authenticated feed.
        #expect(try store.identifiers().isEmpty)

        try store.setCredential(.bearer("abc"), for: id)
        #expect(try store.identifiers() == [id])
        #expect(try store.secretParameters(for: id)?.names == ["token"])
    }

    @Test("A reset takes the designations with the credentials")
    func removesEverything() throws {
        let store = MemoryCredentials()
        let id = UUID()

        try store.setCredential(.bearer("abc"), for: id)
        try store.setSecretParameters(SecretParameters(["token"]), for: id)

        try store.removeEverything()

        #expect(try store.credential(for: id) == nil)
        #expect(try store.secretParameters(for: id) == nil)
    }

    /// The keychain refuses to answer in some environments, so this suite says
    /// what it can and skips rather than failing where it cannot.
    @Test("The keychain keeps a designation apart from the credential of one feed")
    func keepsBothInTheKeychain() throws {
        let store = KeychainCredentials(service: "com.rslt.Flong.tests.\(UUID().uuidString)")
        let id = UUID()

        do {
            try store.setCredential(.bearer("abc"), for: id)
        } catch {
            // No usable keychain here, which is not this test's finding.
            return
        }
        defer { try? store.removeEverything() }

        try store.setSecretParameters(SecretParameters(["Token"]), for: id)

        #expect(try store.credential(for: id) == .bearer("abc"))
        #expect(try store.secretParameters(for: id)?.names == ["token"])
        #expect(try store.everySecretParameter() == [id: SecretParameters(["token"])])

        try store.removeEverything()
        #expect(try store.credential(for: id) == nil)
        #expect(try store.secretParameters(for: id) == nil)
    }
}
