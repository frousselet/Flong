//
//  CloudProvider.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// One turn of an exchange with a service.
///
/// What the model wrote is kept **verbatim**. `The model sees what it just
/// wrote` means literally that : a re-serialisation with its keys in another
/// order is not what it wrote, and asking it to correct a thing it did not say
/// is asking it to correct somebody else.
nonisolated enum CloudTurn: Hashable, Sendable {
    case asked(String)
    case answered(String)
}

/// What is put to a service in one call.
nonisolated struct CloudExchange: Sendable {
    let instructions: String
    let turns: [CloudTurn]
    let shape: ResponseShape
    let budget: Int
    let model: String
    let dialect: ProviderDialect
    let endpoint: URL
    let secret: ProviderSecret
    let headers: [String: String]
}

/// What came back, once it is JSON of the shape that was asked for.
nonisolated struct CloudAnswer: Sendable {
    let json: JSONValue
    /// Exactly what the model wrote, to be replayed as the next turn.
    let written: String
    /// What the service says the whole transcript cost, where it says.
    let promptTokens: Int?
    let answerTokens: Int?
    /// Which model actually answered, which is not always the one asked for.
    let model: String?
}

/// One model a service offers.
nonisolated struct ProviderModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let addedAt: Date?
}

/// Why a call did not come back with an answer, in terms one rung of the
/// ladder can act on.
nonisolated enum CloudTrouble: Error, Sendable {
    case fault(ModelFault)
    /// The service refused the way the question was shaped. The next rung down
    /// is worth exactly one try.
    case wrongDialect
    /// The cap on the answer is named the other way round on this service.
    case wrongTokenField
}

/// One service's own words for the same exchange.
nonisolated protocol CloudWire: Sendable {
    /// Where a question is put, built from the base the reader typed.
    func endpoint(from base: URL) -> URL
    /// Where the list of models is asked for.
    func modelsEndpoint(from base: URL) -> URL

    func request(for exchange: CloudExchange, cappingWith field: TokenField) throws(ModelFault) -> URLRequest
    func read(status: Int, body: Data, retryAfter: TimeInterval?, shaped: ResponseShape) -> Result<
        CloudAnswer, CloudTrouble
    >

    func modelsRequest(at endpoint: URL, with secret: ProviderSecret, headers: [String: String]) -> URLRequest
    func models(from body: Data) -> [ProviderModel]
}

/// What the cap on an answer is called on this service.
///
/// OpenAI's reasoning models refuse `max_tokens` by name and want
/// `max_completion_tokens` ; most of the services that copied the format have
/// never heard of the second. There is no way to know but to ask, so a four
/// hundred naming either drops to the other and is remembered.
nonisolated enum TokenField: String, Hashable, Sendable {
    case maxTokens = "max_tokens"
    case maxCompletionTokens = "max_completion_tokens"

    var other: TokenField { self == .maxTokens ? .maxCompletionTokens : .maxTokens }
}

/// A model the reader configured, seen as one provider among the others.
nonisolated struct CloudProvider: ModelProvider {
    let account: ProviderAccount
    let secret: ProviderSecret
    let wire: any CloudWire
    let transport: CloudTransport

    var name: String { account.name }

    var identity: String { account.id.uuidString }

    var host: String? { base?.host() }

    /// **True, and the run of failures is what says otherwise.** A key that has
    /// expired, an address that answers nothing, a service that is down : none
    /// of those can be known without asking, and all three are what
    /// ``ModelPatience`` is for. What is checked here is only whether there is
    /// enough to make a request out of.
    var isAvailable: Bool { base != nil && !account.model.isEmpty }

    var absence: LocalizedStringResource? {
        guard base == nil || account.model.isEmpty else { return nil }
        return "This provider has no address or no model yet."
    }

    /// **True, and it is an honest guess rather than an answer.** There is no
    /// asking a service which languages its model writes. The check on the
    /// answer itself is the one that catches it, through the system's own
    /// recognizer, and it triggers the same retry it always did.
    func writes(_ locale: Locale) -> Bool { true }

    /// One at a time. A call is seconds and the reader's own money, so a slice
    /// of work that overruns should overrun by one story rather than by three.
    var batch: Int { 1 }

    /// **False.** The second voice exists because Apple's guardrails refuse a
    /// third of ordinary news, and putting the same story again as published
    /// headlines condensed recovers four in ten of those. A service that
    /// declines declines for reasons of its own, and asking twice would be the
    /// reader's money spent on the same answer.
    var triesASecondVoice: Bool { false }

    func conversation(saying instructions: String) -> any ModelConversation {
        CloudConversation(provider: self, instructions: instructions)
    }

    /// The whole address, which is in the keychain where the reader called it a
    /// secret and on the account where they did not.
    var base: URL? {
        if account.isEndpointSecret { return secret.endpoint }
        guard let origin = account.origin else { return nil }
        guard !account.path.isEmpty else { return origin }
        return URL(string: account.path, relativeTo: origin)?.absoluteURL ?? origin
    }
}
