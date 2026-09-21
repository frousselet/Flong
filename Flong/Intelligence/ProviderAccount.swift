//
//  ProviderAccount.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The kinds of model a reader may point a task at.
///
/// **Two wire formats and not twenty.** Almost every service that sells access
/// to a model speaks the OpenAI one, including the servers a reader runs on
/// their own machine ; Anthropic speaks its own. What separates one service
/// from another inside a kind is the address and the model name, which the
/// reader types.
nonisolated enum ProviderKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// The model on this device, which is the only one Flong ships with.
    case appleIntelligence
    case openAICompatible
    case anthropic

    /// What the address field is filled with when this kind is chosen.
    ///
    /// A starting point and never a constraint : the reader may point at
    /// anything, and a server on their own network is the case this exists to
    /// make one keystroke rather than twenty.
    var address: String? {
        switch self {
        case .appleIntelligence: nil
        case .openAICompatible: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        }
    }
}

/// What a server turned out to understand, learnt rather than assumed.
///
/// **Structured answers are a promise the OpenAI format makes and its
/// imitators keep unevenly.** Some take a schema and hold the model to it, some
/// take only `json_object` and want the schema said in words, and some take
/// neither. Asking is the only way to find out, so the answer is written down
/// on the account the first time it is learnt and the second call starts where
/// the first one ended.
nonisolated enum ProviderDialect: String, Codable, Hashable, Sendable {
    /// A schema, honoured.
    case strictSchema
    /// An object, with the schema said in the instructions.
    case jsonObject
    /// Neither, and the answer read out of whatever came back.
    case plainText
}

/// One model a reader has configured, and everything about it that is not a
/// secret.
///
/// **The address is split, and that is the whole of the design.** A private
/// endpoint hides a token in its path, so what is public is the origin and what
/// is not is everything after it. The origin cannot be a secret : the consent
/// names the host out loud and the log records it, and a promise about where
/// something went that would not name the place is not a promise.
nonisolated struct ProviderAccount: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var kind: ProviderKind
    /// What the reader called it, which is what the four pickers show.
    var name: String
    /// Scheme, host and port, and never more.
    var origin: URL?
    /// What follows the origin, when the reader has not said it is a secret.
    /// The whole address lives in the keychain when they have.
    var path: String
    var isEndpointSecret: Bool
    var model: String
    /// The names of the headers the reader added. The values are in the
    /// keychain, since one of them is a key on more than one gateway.
    var headerNames: [String]
    var dialect: ProviderDialect
    /// The last time a call actually came back whole, which is the only honest
    /// proof a provider still works. The field ``SiteSession`` keeps, for the
    /// same reason.
    var lastWorkedAt: Date?
    var addedAt: Date

    init(
        id: UUID = .v7(),
        kind: ProviderKind,
        name: String,
        origin: URL? = nil,
        path: String = "",
        isEndpointSecret: Bool = false,
        model: String = "",
        headerNames: [String] = [],
        dialect: ProviderDialect = .strictSchema,
        lastWorkedAt: Date? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.origin = origin
        self.path = path
        self.isEndpointSecret = isEndpointSecret
        self.model = model
        self.headerNames = headerNames
        self.dialect = dialect
        self.lastWorkedAt = lastWorkedAt
        self.addedAt = addedAt
    }

    /// The host, which is what the consent names and the log records.
    var host: String { origin?.host() ?? "" }

    // MARK: - Reading a blob written before a field was added

    /// The same reading ``ProviderSettings`` does, and for the same reason.
    ///
    /// An account is inside that blob, so a field added here fails the whole
    /// of it : Swift's synthesized reading demands every key rather than
    /// falling back on a property's default, and one missing key throws a
    /// failure that empties the accounts, the assignments and the consent
    /// together. Every field is read as optional against what it means when
    /// nobody has said anything, except the three an account cannot be without.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(ProviderKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        origin = try container.decodeIfPresent(URL.self, forKey: .origin)
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        isEndpointSecret = try container.decodeIfPresent(Bool.self, forKey: .isEndpointSecret) ?? false
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        headerNames = try container.decodeIfPresent([String].self, forKey: .headerNames) ?? []
        dialect = try container.decodeIfPresent(ProviderDialect.self, forKey: .dialect) ?? .strictSchema
        lastWorkedAt = try container.decodeIfPresent(Date.self, forKey: .lastWorkedAt)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }
}

/// Where one of the four things a model does is pointed.
///
/// **Three answers and not two.** An identifier or nothing would fold *the
/// device does this* into *nobody does this*, and they are different : the
/// first is the ordinary state and the second is a reader saying they would
/// rather have no headline than a written one.
nonisolated enum ModelChoice: Hashable, Sendable, Codable {
    case onDevice
    case provider(UUID)
    case nothing

    var account: UUID? {
        guard case .provider(let id) = self else { return nil }
        return id
    }

    // MARK: - Surviving a case this build has never heard of

    /// **A case written by a newer device used to cost the reader everything.**
    /// These travel through the key-value store, so a device one version ahead
    /// writes what a device one version behind has to read. The synthesized
    /// reading threw on a case it did not know, and the throw did not stop at
    /// the one task : ``Preferences/providers`` reads the whole settings blob
    /// through a `try?`, so one unknown word emptied the accounts, the
    /// assignments and the consent together, and the next write pushed that
    /// emptiness back to iCloud for every other device to receive. A reader
    /// would have lost the model they configured, on all of their devices, and
    /// nothing would have said why.
    ///
    /// So a case that is not recognized reads as the device, which is what a
    /// task nobody has spoken about already means, and everything around it
    /// survives. The writing is untouched and byte for byte what it has always
    /// been, `{"onDevice":{}}` and `{"provider":{"_0":"..."}}`, since the other
    /// device has to go on reading what this one writes.
    private enum CodingKeys: String, CodingKey {
        case onDevice
        case provider
        case nothing
    }

    /// The synthesized name for a single unlabelled associated value.
    private enum ProviderKeys: String, CodingKey {
        case value = "_0"
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .onDevice
            return
        }

        if container.contains(.provider),
            let nested = try? container.nestedContainer(keyedBy: ProviderKeys.self, forKey: .provider),
            let id = try? nested.decode(UUID.self, forKey: .value)
        {
            self = .provider(id)
        } else if container.contains(.nothing) {
            self = .nothing
        } else {
            self = .onDevice
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .onDevice:
            _ = container.nestedContainer(keyedBy: ProviderKeys.self, forKey: .onDevice)
        case .nothing:
            _ = container.nestedContainer(keyedBy: ProviderKeys.self, forKey: .nothing)
        case .provider(let id):
            var nested = container.nestedContainer(keyedBy: ProviderKeys.self, forKey: .provider)
            try nested.encode(id, forKey: .value)
        }
    }
}

/// What the reader has chosen about models.
///
/// A preference and not a record : it is a decision about themselves, like the
/// hours their editions come out, so it goes to the key-value store that
/// carries their other decisions between their devices. Nothing secret is in
/// here, and the one thing that would be, the key, is in the keychain under the
/// same identifier.
nonisolated struct ProviderSettings: Hashable, Sendable, Codable {
    var accounts: [ProviderAccount] = []

    /// Which model answers which task.
    ///
    /// A task with no entry, or one naming an account that has been removed,
    /// falls back to the model on the device. There is no state in which a task
    /// points at an account that is gone : removing one takes back everything
    /// aimed at it, so nothing has to have words for that.
    var assignment: [ModelTask: ModelChoice] = [:]

    /// Whether the reader has been asked, and said yes.
    ///
    /// **The gate sits here rather than only on the screen that asks.** This
    /// travels through the iCloud key-value store, so it can arrive changed
    /// from another device between one story and the next : the check has to be
    /// in the path every outgoing call passes through, and a call made without
    /// it is not made.
    var sendsToProviders = false

    init() {}

    /// Written out rather than left to be synthesized, since the reading below
    /// names it.
    private enum CodingKeys: String, CodingKey {
        case accounts
        case assignment
        case sendsToProviders
    }

    // MARK: - Reading a blob written before this version

    /// **A field added here used to cost the reader everything, too.** Swift's
    /// synthesized reading does not fall back on a property's default : it
    /// demands the key, so the first version to add a field would have failed
    /// to read every blob written before it, and ``Preferences/providers``
    /// reads through a `try?` that turns a failure into empty settings and
    /// then writes them back to iCloud. The day a field was added, every
    /// reader would have lost their accounts and their consent on every
    /// device. Measured, not feared : `keyNotFound` on today's own blob.
    ///
    /// Every field is read as optional and falls back on what it means when
    /// nobody has said anything, so a blob from any version reads, and so does
    /// a blob from a version that adds another field after this one.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try container.decodeIfPresent([ProviderAccount].self, forKey: .accounts) ?? []
        assignment = Self.readAssignment(in: container)
        sendsToProviders = try container.decodeIfPresent(Bool.self, forKey: .sendsToProviders) ?? false
    }

    /// The assignment read pair by pair, because one pair this build cannot
    /// read must not cost the others.
    ///
    /// **A dictionary keyed by anything but a string or a number is written as
    /// a flat list**, the task and then its choice, over and over :
    /// `["headlines", {...}, "search", {...}]`. Read as a dictionary in one go,
    /// a task named by a newer version fails the whole list, and the failure
    /// does not stop there : it fails the settings, which empties the accounts
    /// and the consent and writes that emptiness back to iCloud.
    ///
    /// So the key is read as the string it is written as, and a name this build
    /// has never heard of drops that one pair. Both reads are written so they
    /// always move forward : a pair that could not be read still advances the
    /// list, and nothing here can turn into a loop that does not end.
    private static func readAssignment(in container: KeyedDecodingContainer<CodingKeys>) -> [ModelTask: ModelChoice] {
        guard var list = try? container.nestedUnkeyedContainer(forKey: .assignment) else { return [:] }

        var read: [ModelTask: ModelChoice] = [:]
        while !list.isAtEnd {
            // A key that is not a string is a shape nothing here wrote, and
            // there is no telling where the next pair begins, so it stops.
            guard let name = try? list.decode(String.self) else { break }
            guard let choice = try? list.decode(ModelChoice.self) else { break }
            guard let task = ModelTask(rawValue: name) else { continue }
            read[task] = choice
        }
        return read
    }

    func account(_ id: UUID?) -> ProviderAccount? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    /// Where one task is pointed, the device being the answer for anything
    /// that has never been said.
    func choice(for task: ModelTask) -> ModelChoice {
        assignment[task] ?? .onDevice
    }

    /// The account answering one task, or nothing where the device answers it.
    func account(for task: ModelTask) -> ProviderAccount? {
        guard sendsToProviders else { return nil }
        return account(choice(for: task).account)
    }

    /// The same settings with one task pointed somewhere else.
    func pointing(_ task: ModelTask, at choice: ModelChoice) -> ProviderSettings {
        var settings = self
        settings.assignment[task] = choice
        return settings
    }

    /// The same settings without one account, and with nothing left pointing at
    /// it.
    ///
    /// The two go together : a task pointing at an account that is gone is a
    /// state nothing would ever repair, and a screen would have to have words
    /// for it.
    func without(_ id: UUID) -> ProviderSettings {
        var settings = self
        settings.accounts.removeAll { $0.id == id }
        settings.assignment = settings.assignment.filter { $0.value.account != id }
        return settings
    }

    /// The same settings with every task that was sent away back on the
    /// device.
    ///
    /// A task the reader switched off stays off : stopping is about what leaves
    /// the device and not about undoing every choice they made.
    func withNothingSent() -> ProviderSettings {
        var settings = self
        settings.assignment = settings.assignment.filter { $0.value == .nothing }
        settings.sendsToProviders = false
        return settings
    }

    /// The same settings with one account added or replaced.
    func keeping(_ account: ProviderAccount) -> ProviderSettings {
        var settings = self
        if let index = settings.accounts.firstIndex(where: { $0.id == account.id }) {
            settings.accounts[index] = account
        } else {
            settings.accounts.append(account)
        }
        return settings
    }
}
