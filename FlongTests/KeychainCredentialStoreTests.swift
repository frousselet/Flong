//
//  KeychainCredentialStoreTests.swift
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

/// Exercises the real keychain, under a service name of its own so it can never
/// touch what the app stores. Every test clears up after itself.
@Suite("Keychain credential store", .serialized)
struct KeychainCredentialStoreTests {
    private let store = KeychainCredentialStore(service: "com.rslt.Flong.tests")

    private let credentials = Credentials(
        serverURL: URL(string: "https://rss.example.com")!,
        username: "alice",
        password: "s3cret"
    )

    /// The whole point of the store : the item goes to the synchronizable
    /// keychain, which is what iCloud Keychain carries to the other devices.
    @Test("Credentials are stored for every device of the account")
    func storesForSyncing() throws {
        defer { try? store.clear() }

        let storage = try store.saveCredentials(credentials)
        #expect(storage == .syncedAcrossDevices)

        let stored = try #require(try store.loadCredentials())
        #expect(stored.credentials == credentials)
        #expect(stored.storage == .syncedAcrossDevices)
    }

    @Test("Saving again replaces the previous credentials")
    func overwrites() throws {
        defer { try? store.clear() }
        try store.saveCredentials(credentials)

        var updated = credentials
        updated.username = "bob"
        try store.saveCredentials(updated)

        #expect(try store.loadCredentials()?.credentials.username == "bob")
    }

    /// The token is a per-device cache, rebuildable from the credentials, so it
    /// must not travel with them.
    @Test("The session token is kept on this device only")
    func sessionTokenStaysLocal() throws {
        defer { try? store.clear() }

        try store.saveSessionToken("alice/token")
        #expect(try store.loadSessionToken() == "alice/token")

        try store.saveSessionToken(nil)
        #expect(try store.loadSessionToken() == nil)
    }

    @Test("Clearing removes the credentials and the token")
    func clearing() throws {
        try store.saveCredentials(credentials)
        try store.saveSessionToken("alice/token")

        try store.clear()

        #expect(try store.loadCredentials() == nil)
        #expect(try store.loadSessionToken() == nil)
    }

    @Test("An empty store reports nothing rather than failing")
    func emptyStore() throws {
        try store.clear()
        #expect(try store.loadCredentials() == nil)
    }
}
