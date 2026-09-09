//
//  ProviderSecretTests.swift
//  FlongTests
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

/// The key of a model the reader brought of their own.
///
/// Every address here is `models.example.com` and every key is obviously not
/// one : a fixture that carried a real key would be a real key in the history
/// of this repository for ever.
@Suite("What a model of the reader's own needs to answer")
struct ProviderSecretTests {
    @Test("A key goes in and comes back")
    func roundTrip() throws {
        let store = MemoryProviderSecrets()
        let id = UUID.v7()

        try store.setSecret(ProviderSecret(key: "not-a-real-key"), for: id)

        #expect(try store.secret(for: id)?.key == "not-a-real-key")
        #expect(try store.identifiers() == [id])
    }

    @Test("A second key replaces the first rather than standing beside it")
    func replaces() throws {
        let store = MemoryProviderSecrets()
        let id = UUID.v7()

        try store.setSecret(ProviderSecret(key: "first"), for: id)
        try store.setSecret(ProviderSecret(key: "second"), for: id)

        #expect(try store.secret(for: id)?.key == "second")
        #expect(try store.identifiers().count == 1)
    }

    /// A secret with nothing in it is no secret. Stored as an empty one it
    /// would read as a provider that is configured and answers nothing.
    @Test("A secret with nothing in it is deleted rather than stored")
    func emptyIsAbsent() throws {
        let store = MemoryProviderSecrets()
        let id = UUID.v7()

        try store.setSecret(ProviderSecret(key: "something"), for: id)
        try store.setSecret(ProviderSecret(), for: id)

        #expect(try store.secret(for: id) == nil)
        #expect(try store.identifiers().isEmpty)
    }

    @Test("A whole address the reader called a secret goes in with the key")
    func aSecretAddressTravelsWithIt() throws {
        let store = MemoryProviderSecrets()
        let id = UUID.v7()
        let endpoint = URL(string: "https://models.example.com/v1/t-0000000000/chat")!

        try store.setSecret(ProviderSecret(key: "not-a-real-key", endpoint: endpoint), for: id)

        #expect(try store.secret(for: id)?.endpoint == endpoint)
    }

    @Test("A reset takes every key, whichever provider it belonged to")
    func aResetTakesTheLot() throws {
        let store = MemoryProviderSecrets()
        try store.setSecret(ProviderSecret(key: "one"), for: .v7())
        try store.setSecret(ProviderSecret(key: "two"), for: .v7())

        try store.removeEverything()

        #expect(try store.identifiers().isEmpty)
    }
}

/// What the reader has chosen about models.
@Suite("Which model answers what")
struct ProviderSettingsTests {
    private func account(_ name: String) -> ProviderAccount {
        ProviderAccount(kind: .openAICompatible, name: name, origin: URL(string: "https://models.example.com/v1"))
    }

    @Test("Nothing is sent before the reader has said so")
    func nothingLeavesBeforeTheYes() {
        var settings = ProviderSettings()
        let mine = account("Mine")
        settings.accounts = [mine]
        settings = settings.pointing(.headlines, at: mine.id)

        // The assignment is made and the answer is still the device : the gate
        // is the consent and not the picker.
        #expect(settings.account(for: .headlines) == nil)

        settings.sendsToProviders = true
        #expect(settings.account(for: .headlines) == mine)
    }

    /// A task pointing at an account that is gone is a state nothing would ever
    /// repair, and a screen would have to have words for it.
    @Test("Removing a provider takes back every task pointed at it")
    func removingTakesBackWhatPointedAtIt() {
        var settings = ProviderSettings()
        let mine = account("Mine")
        settings.accounts = [mine]
        settings.sendsToProviders = true
        settings = settings.pointing(.headlines, at: mine.id).pointing(.editions, at: mine.id)

        settings = settings.without(mine.id)

        #expect(settings.accounts.isEmpty)
        #expect(settings.assignment.isEmpty)
        #expect(settings.account(for: .headlines) == nil)
    }

    @Test("Stopping puts every task back on the device and keeps the accounts")
    func stoppingKeepsTheAccounts() {
        var settings = ProviderSettings()
        let mine = account("Mine")
        settings.accounts = [mine]
        settings.sendsToProviders = true
        settings = settings.pointing(.search, at: mine.id)

        settings = settings.withNothingSent()

        #expect(settings.accounts == [mine])
        #expect(!settings.sendsToProviders)
        #expect(settings.account(for: .search) == nil)
    }

    /// The four choices and the accounts travel between the reader's devices
    /// with their other decisions, and a reset takes them.
    @Test("What the reader chose travels, and a reset forgets it")
    func choicesTravelAndAreForgotten() throws {
        let defaults = try #require(UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)"))
        let preferences = Preferences(cloud: nil, local: defaults)

        var settings = ProviderSettings()
        let mine = account("Mine")
        settings.accounts = [mine]
        settings.sendsToProviders = true
        preferences.providers = settings.pointing(.subjects, at: mine.id)

        #expect(preferences.providers.accounts.map(\.name) == ["Mine"])
        #expect(preferences.providers.assignment[.subjects] == mine.id)

        preferences.forgetEverything()

        #expect(preferences.providers.accounts.isEmpty)
        // Nothing, and not a refusal : forgetting has to put the question back
        // to never asked, or a reset would leave a no the reader never gave.
        #expect(!preferences.providers.sendsToProviders)
    }
}

/// The real keychain, where there is one.
///
/// The keychain refuses to answer at all in some test environments, so the
/// suite asks whether it works before claiming anything about it : a suite that
/// cannot run is a suite that says nothing.
@Suite("The keychain, where there is one", .serialized)
struct KeychainProviderSecretTests {
    private static var isAvailable: Bool {
        let store = KeychainProviderSecrets(service: "com.rslt.Flong.tests.probe")
        let id = UUID.v7()
        defer { try? store.setSecret(nil, for: id) }
        do {
            try store.setSecret(ProviderSecret(key: "probe"), for: id)
            return try store.secret(for: id)?.key == "probe"
        } catch {
            return false
        }
    }

    @Test("A key goes to the keychain and comes back", .enabled(if: KeychainProviderSecretTests.isAvailable))
    func keychainRoundTrip() throws {
        let store = KeychainProviderSecrets(service: "com.rslt.Flong.tests.\(UUID().uuidString)")
        let id = UUID.v7()
        defer { try? store.removeEverything() }

        try store.setSecret(ProviderSecret(key: "not-a-real-key"), for: id)
        // Written twice on purpose : the write updates before it adds, and one
        // item is what proves it.
        try store.setSecret(ProviderSecret(key: "not-a-real-key-either"), for: id)

        #expect(try store.secret(for: id)?.key == "not-a-real-key-either")
        #expect(try store.identifiers() == [id])

        try store.setSecret(nil, for: id)
        #expect(try store.secret(for: id) == nil)
    }
}
