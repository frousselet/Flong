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
