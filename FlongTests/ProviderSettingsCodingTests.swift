//
//  ProviderSettingsCodingTests.swift
//  FlongTests
//
//  Created by François Rousselet on 21/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

/// What the reader's model settings survive on their way between devices.
///
/// **These settings travel through the key-value store, so two versions read
/// each other's writing.** A device one version ahead writes what a device one
/// version behind has to read, and `Preferences.providers` reads the whole blob
/// at once : a single word it does not know used to empty the accounts, the
/// assignments and the consent together, and the next write pushed that
/// emptiness back to iCloud for every other device to receive. The reader would
/// have lost the model they configured, everywhere, with nothing said.
///
/// Both readings are tolerant now, and these hold them to it. They are written
/// against the bytes rather than against the types, because the bytes are what
/// actually crosses.
@Suite("What the model settings survive")
struct ProviderSettingsCodingTests {
    private static let account = ProviderAccount(
        id: UUID(uuidString: "0198F0A0-0000-7000-8000-000000000001")!,
        kind: .anthropic,
        name: "Chez moi"
    )

    /// The shape written by every version up to this one.
    private static func blobOfToday() throws -> Data {
        var settings = ProviderSettings()
        settings.accounts = [account]
        settings.sendsToProviders = true
        settings.assignment = [.headlines: .provider(account.id), .search: .onDevice]
        return try JSONEncoder().encode(settings)
    }

    @Test("What is written is what has always been written")
    func theWritingIsUnchanged() throws {
        let written = try JSONEncoder().encode(ModelChoice.provider(Self.account.id))
        let text = String(decoding: written, as: UTF8.self)

        // Pinned to the byte, since the other device reads it : the reading
        // below is free to be generous, the writing is not free to move.
        #expect(text == #"{"provider":{"_0":"0198F0A0-0000-7000-8000-000000000001"}}"#)
        #expect(String(decoding: try JSONEncoder().encode(ModelChoice.onDevice), as: UTF8.self) == #"{"onDevice":{}}"#)
        #expect(String(decoding: try JSONEncoder().encode(ModelChoice.nothing), as: UTF8.self) == #"{"nothing":{}}"#)
    }

    /// Built from what this version actually writes, with one word swapped,
    /// so the fixture cannot drift away from the real shape.
    ///
    /// The assignment is a flat list and not an object, which is what a
    /// dictionary keyed by anything but a string or a number is written as.
    private static func blobOfTomorrow() throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: try blobOfToday()) as? [String: Any],
            var list = json["assignment"] as? [Any]
        else {
            Issue.record("The settings are no longer written as an object holding a list")
            return Data()
        }

        // The pairs are a task and then its choice, and their order is the
        // dictionary's rather than anything this can count on, so the task is
        // found by name and its choice is the element after it.
        guard let named = list.firstIndex(where: { ($0 as? String) == "headlines" }) else {
            Issue.record("The task that was pointed somewhere is not in what was written")
            return Data()
        }
        list[named + 1] = ["somethingNewerDevicesKnow": [String: Any]()]
        // And a task nobody here has a name for, with a choice of its own.
        list.append(contentsOf: ["aTaskFromLater", ["onDevice": [String: Any]()]])
        json["assignment"] = list
        return try JSONSerialization.data(withJSONObject: json)
    }

    @Test("A choice written by a newer device costs that task and nothing else")
    func anUnknownChoiceCostsOneTask() throws {
        let read = try JSONDecoder().decode(ProviderSettings.self, from: Self.blobOfTomorrow())

        // The task nobody here can serve falls back on the device, which is
        // what a task nobody has spoken about already means.
        #expect(read.choice(for: .headlines) == .onDevice)
        // And everything else is still there, which is the whole point.
        #expect(read.accounts.map(\.id) == [Self.account.id])
        #expect(read.sendsToProviders)
        #expect(read.choice(for: .search) == .onDevice)
    }

    @Test("An account missing a field a later version added still reads")
    func anOlderAccountStillReads() throws {
        let bare =
            #"{"accounts":[{"id":"0198F0A0-0000-7000-8000-000000000001","kind":"anthropic","name":"Chez moi"}],"sendsToProviders":true}"#
        let read = try JSONDecoder().decode(ProviderSettings.self, from: Data(bare.utf8))

        #expect(read.accounts.map(\.name) == ["Chez moi"])
        #expect(read.accounts.first?.dialect == .strictSchema)
        #expect(read.sendsToProviders)
    }

    @Test("A blob written before a field was added still reads")
    func anOlderBlobStillReads() throws {
        let read = try JSONDecoder().decode(ProviderSettings.self, from: Self.blobOfToday())

        #expect(read.accounts.map(\.id) == [Self.account.id])
        #expect(read.sendsToProviders)
        #expect(read.choice(for: .headlines) == .provider(Self.account.id))
    }

    /// The reading falls back field by field, so the version that adds the next
    /// field does not have to remember any of this.
    @Test("A blob missing every field is empty settings rather than no settings")
    func anEmptyBlobReads() throws {
        let read = try JSONDecoder().decode(ProviderSettings.self, from: Data("{}".utf8))

        #expect(read.accounts.isEmpty)
        #expect(!read.sendsToProviders)
        #expect(read.choice(for: .headlines) == .onDevice)
    }

    @Test("A consent that was given survives a choice nobody here understands")
    func theConsentSurvives() throws {
        let fromTheFuture = #"{"assignment":["editions",{"aThingFromLater":{"_0":"x"}}],"sendsToProviders":true}"#
        let read = try JSONDecoder().decode(ProviderSettings.self, from: Data(fromTheFuture.utf8))

        // The consent is the one thing a reader would never think to check, and
        // losing it silently is how nothing is sent and nobody knows why.
        #expect(read.sendsToProviders)
        #expect(read.choice(for: .editions) == .onDevice)
    }

    /// The list is read forward, so a pair that cannot be read never turns into
    /// a loop that does not end. Written down because the failure would be a
    /// launch that hangs rather than a test that fails.
    @Test("A list this build cannot follow stops rather than spins")
    func aMalformedListStops() throws {
        let broken = #"{"assignment":[12,{"onDevice":{}},"search",{"onDevice":{}}],"sendsToProviders":true}"#
        let read = try JSONDecoder().decode(ProviderSettings.self, from: Data(broken.utf8))

        #expect(read.sendsToProviders)
        #expect(read.choice(for: .search) == .onDevice)
    }

    // MARK: - Words a newer version writes

    /// An account of a kind this build has no name for is left out rather than
    /// guessed at, and everything beside it survives. Guessed at, it would send
    /// a reader's articles to their own service in a shape it does not speak.
    @Test("An account of a kind this build cannot read costs that account alone")
    func anUnknownKindCostsOneAccount() throws {
        let mixed = #"""
            {"accounts":[\
            {"id":"0198F0A0-0000-7000-8000-000000000001","kind":"anthropic","name":"Chez moi"},\
            {"id":"0198F0A0-0000-7000-8000-000000000002","kind":"aKindFromLater","name":"Ailleurs"}],\
            "sendsToProviders":true,"privateCloud":"agreed"}
            """#
            .replacingOccurrences(of: "\\\n", with: "")

        let read = try JSONDecoder().decode(ProviderSettings.self, from: Data(mixed.utf8))

        #expect(read.accounts.map(\.name) == ["Chez moi"])
        #expect(read.sendsToProviders)
        #expect(read.privateCloud == .agreed)
    }

    /// A dialect is a hint that is learnt again, so it is forgotten rather than
    /// thrown over.
    @Test("A dialect this build cannot read is forgotten, not fatal")
    func anUnknownDialectIsForgotten() throws {
        let odd =
            #"{"accounts":[{"id":"0198F0A0-0000-7000-8000-000000000001","kind":"anthropic","name":"Chez moi","dialect":"aDialectFromLater"}]}"#
        let read = try JSONDecoder().decode(ProviderSettings.self, from: Data(odd.utf8))

        #expect(read.accounts.map(\.name) == ["Chez moi"])
        #expect(read.accounts.first?.dialect == .strictSchema)
    }

    /// Anything that is not a yes this build understands is not a yes.
    @Test("A consent this build cannot read is never taken for agreement")
    func anUnknownConsentIsNotAYes() throws {
        let later = #"{"accounts":[],"sendsToProviders":false,"privateCloud":"agreedForSomethingElse"}"#
        let read = try JSONDecoder().decode(ProviderSettings.self, from: Data(later.utf8))

        #expect(read.privateCloud == .unasked)
        for task in ModelTask.allCases {
            #expect(read.choice(for: task, withPrivateCloud: true) == .onDevice)
        }
    }
}
