//
//  ModelCatalogue.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// What a reader is told when a model of their own will not answer.
///
/// **Five, and never the service's own words.** A service is free to put
/// anything in the body of its own error and several put the prompt there ;
/// one of them puts the key back. So what reaches the screen is one of these,
/// written here, and the body is neither shown nor logged.
nonisolated enum ProviderTrouble: Error, Hashable, Sendable {
    case keyRefused
    case noSuchModel
    case unreachable
    case busy
    case unreadable

    var line: LocalizedStringResource {
        switch self {
        case .keyRefused: "The key was refused."
        case .noSuchModel: "There is no such model."
        case .unreachable: "The service could not be reached."
        case .busy: "The service is busy. Try again later."
        case .unreadable: "The service answered something Flong could not read."
        }
    }

    /// What a failure of the model itself looks like to a reader.
    ///
    /// Nothing for a failure that is about one story : those are ordinary, they
    /// are what the second voice and the fallback exist for, and a row that
    /// complained about them would be complaining about the news.
    init?(_ fault: ModelFault) {
        switch fault {
        case .declined, .tooLong:
            return nil
        case .unreadable:
            self = .unreadable
        case .busy:
            self = .busy
        case .unusable(let reason):
            switch reason {
            case .notEntitled: self = .keyRefused
            case .misconfigured: self = .noSuchModel
            case .absent, .unreachable: self = .unreachable
            case .cancelled: return nil
            }
        }
    }
}

/// What a test of a provider came to.
nonisolated enum ProviderProbe: Hashable, Sendable {
    /// It answered, in this long, with this model, having understood the
    /// question put this way, and offering this many models.
    case answered(seconds: TimeInterval, model: String?, dialect: ProviderDialect, models: Int)
    case trouble(ProviderTrouble)
    /// The address is private and the system would not let the request out.
    case localNetworkRefused
}

/// Which models a service offers, and whether it answers at all.
///
/// Both halves of the button the reader presses after typing a key : the list
/// fills a menu, and the round trip proves the key, the address, the model name
/// and the shape of the question all at once.
nonisolated struct ModelCatalogue: Sendable {
    let transport: CloudTransport

    init(transport: CloudTransport = CloudTransport()) {
        self.transport = transport
    }

    /// The models a service says it offers.
    ///
    /// **A four hundred and four is an answer and not a failure.** Several
    /// servers a reader may point Flong at route only the completion path : a
    /// gateway scoped to one model, a llama.cpp behind a key, some vLLM
    /// configurations. `The service will not say` is a perfectly good state,
    /// and the field beside the menu is where a reader types the name
    /// themselves. What is worth reporting is a refused key, because that means
    /// the key itself is wrong.
    func models(
        of account: ProviderAccount,
        with secret: ProviderSecret
    ) async -> Result<[ProviderModel], ProviderTrouble> {
        guard let wire = ModelDesk.wire(of: account.kind),
            let base = Self.base(of: account, with: secret)
        else { return .failure(.noSuchModel) }

        let request = wire.modelsRequest(at: wire.modelsEndpoint(from: base), with: secret, headers: [:])

        do {
            let (status, body, _) = try await transport.send(request)

            switch status {
            case 200..<300:
                return .success(Self.sorted(wire.models(from: body)))
            case 401, 403:
                return .failure(.keyRefused)
            case 404, 405, 501:
                return .success([])
            case 429, 500...599:
                return .failure(.busy)
            default:
                return .failure(.unreadable)
            }
        } catch {
            return .failure(ProviderTrouble(error) ?? .unreachable)
        }
    }

    /// Newest first where the service says, then by name.
    static func sorted(_ models: [ProviderModel]) -> [ProviderModel] {
        models.sorted { one, other in
            switch (one.addedAt, other.addedAt) {
            case (let a?, let b?): a > b
            case (_?, nil): true
            case (nil, _?): false
            default: one.id < other.id
            }
        }
    }

    /// One cheap round trip that proves the whole configuration.
    ///
    /// **It sends a fixed sentence and nothing of the reader's**, which is what
    /// makes it honest to offer before any consent has been given : a reader
    /// checking that their key works has not yet decided that their news may
    /// leave, and being made to decide first would be asking them to agree to
    /// something they cannot yet check.
    ///
    /// The list is asked for first, because it is free and it separates an
    /// address nothing answers from a key that is refused. Then the real
    /// endpoint, the real model and the whole shape machinery, for the smallest
    /// structured answer there is.
    func probe(_ account: ProviderAccount, with secret: ProviderSecret) async -> ProviderProbe {
        guard let base = Self.base(of: account, with: secret) else { return .trouble(.noSuchModel) }
        guard LocalNetwork.allowsPlainHTTP(base) else { return .localNetworkRefused }
        guard ModelDesk.wire(of: account.kind) != nil else { return .trouble(.noSuchModel) }

        var offered = 0
        switch await models(of: account, with: secret) {
        case .success(let models):
            offered = models.count
        case .failure(.keyRefused):
            return .trouble(.keyRefused)
        case .failure:
            // Anything else here proves nothing : the round trip below is what
            // actually decides.
            break
        }

        let provider = CloudProvider(
            account: account,
            secret: secret,
            wire: ModelDesk.wire(of: account.kind)!,
            transport: transport
        )
        let conversation = provider.conversation(saying: Self.instructions)
        let started = Date()

        do {
            _ = try await conversation.answer(to: Self.question, shaped: Self.shape, keeping: Self.budget)
        } catch {
            return .trouble(ProviderTrouble(error) ?? .unreadable)
        }

        return .answered(
            seconds: Date().timeIntervalSince(started),
            model: account.model,
            dialect: (conversation as? CloudConversation)?.learnt ?? account.dialect,
            models: offered
        )
    }

    /// The smallest structured answer there is.
    static let shape = ResponseShape.object(
        named: "Reply",
        fields: [.init("ok", "The word ok", .oneOf(named: "Ok", choices: ["ok"]))]
    )
    static let instructions = "You answer with the structure you are given and nothing else."
    static let question = "Answer with ok."
    /// A handful of tokens. A service that cannot manage this in half a minute
    /// is not one to file a night of articles through.
    static let budget = 16

    /// The whole address, which is in the keychain where the reader called it a
    /// secret and on the account where they did not.
    static func base(of account: ProviderAccount, with secret: ProviderSecret) -> URL? {
        CloudProvider(
            account: account,
            secret: secret,
            wire: OpenAICompatible(),
            transport: CloudTransport()
        ).base
    }
}
