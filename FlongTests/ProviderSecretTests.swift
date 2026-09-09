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
        settings = settings.pointing(.headlines, at: .provider(mine.id))

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
        settings = settings.pointing(.headlines, at: .provider(mine.id)).pointing(.editions, at: .provider(mine.id))

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
        settings = settings.pointing(.search, at: .provider(mine.id))

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
        preferences.providers = settings.pointing(.subjects, at: .provider(mine.id))

        #expect(preferences.providers.accounts.map(\.name) == ["Mine"])
        #expect(preferences.providers.choice(for: .subjects) == .provider(mine.id))

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

/// One account being written down or changed.
@Suite("Writing down a model of the reader's own")
struct ProviderDraftTests {
    private let account = ProviderAccount(
        kind: .openAICompatible,
        name: "Mine",
        origin: URL(string: "https://models.example.com/v1"),
        model: "a-model"
    )

    /// **A key is minted by the service, shown once by the service, and
    /// reissued at will.** There is nothing to compare it against, so showing
    /// it again buys nothing and costs the one thing a keychain is for. A
    /// secret feed address is shown in dots for the opposite reason, which
    /// `docs/technical/credentials.md` sets out.
    @Test("A stored key is never offered back, only replaced")
    func aStoredKeyIsNeverShownAgain() {
        let held = ProviderDraft(account, hasStoredKey: true)
        #expect(held.hasStoredKey)
        #expect(!held.isReplacingKey)

        held.isReplacingKey = true
        #expect(held.isReplacingKey, "and the field comes back only when they ask for it")

        let fresh = ProviderDraft(nil, hasStoredKey: false)
        #expect(!fresh.hasStoredKey, "a new one asks for a key")
    }

    @Test("A new draft starts on the kind's own address")
    func aNewDraftStartsSomewhere() {
        let fresh = ProviderDraft(nil, hasStoredKey: false)

        #expect(fresh.isNew)
        #expect(fresh.address == ProviderKind.openAICompatible.address)
        #expect(!fresh.isComplete, "and is not saveable until it is finished")
    }

    @Test("A draft is finished when it has a name, an address and a model")
    func aDraftKnowsWhenItIsFinished() {
        let draft = ProviderDraft(account, hasStoredKey: true)

        #expect(draft.isComplete)
        #expect(draft.chosenModel == "a-model")
        #expect(draft.account.origin?.absoluteString == "https://models.example.com/v1")
    }

    /// A model server the reader runs has no TLS and never will ; a public host
    /// spoken to in the clear is a mistake the editor refuses with a sentence
    /// rather than a number.
    @Test("A plain address is warned about at home and refused abroad")
    func plainAddressesAreJudged() {
        let draft = ProviderDraft(nil, hasStoredKey: false)

        draft.address = "http://192.168.1.20:11434/v1"
        #expect(draft.isPlainAndPrivate)
        #expect(!draft.isPlainAndPublic)

        draft.address = "http://api.example.com/v1"
        #expect(draft.isPlainAndPublic)
        #expect(!draft.isPlainAndPrivate)

        draft.address = "https://api.example.com/v1"
        #expect(!draft.isPlainAndPublic)
        #expect(!draft.isPlainAndPrivate)
    }
}
