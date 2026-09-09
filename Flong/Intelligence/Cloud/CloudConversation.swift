//
//  CloudConversation.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import OSLog

/// An exchange with a model that is not on this device.
///
/// The conversation does the remembering that a session does on the device :
/// the turns are held here and sent again with every question, which is what
/// makes `ask it again, it can see what it wrote` mean the same thing on both
/// sides.
nonisolated final class CloudConversation: ModelConversation {
    /// How many turns one exchange may run to.
    ///
    /// **Four, which is what the writing actually uses** : the brief, one
    /// complaint, the headline alone and the line alone. A cap is here rather
    /// than nowhere because every turn carries every turn before it, so a loop
    /// that asked one more time would cost more each time it did.
    static let mostTurns = 4

    /// What a window is assumed to be where nobody has said.
    ///
    /// Generous, since the failure it guards against is a truncated answer and
    /// the smallest model a reader would point this at holds more than this.
    static let assumedWindow = 8_000

    private let provider: CloudProvider
    private let instructions: String
    /// Which of the four things a model does this exchange is, for the log.
    private let task: ModelTask

    /// What has been said, in order, and the model's own words for its own
    /// turns.
    private var turns: [CloudTurn] = []

    /// What the service said the transcript cost, once it has said.
    ///
    /// **A fact where there is one and an estimate until then.** Every answer
    /// carries the count of what it was shown, so from the second turn on the
    /// cost of everything already said is known and only the question being
    /// added is guessed at.
    private var spent: Int?

    /// Which name this service wants for the cap on an answer, once it is
    /// known.
    private var tokenField: TokenField = .maxTokens

    /// Which dialect this service turned out to understand.
    private var dialect: ProviderDialect

    init(provider: CloudProvider, instructions: String, task: ModelTask) {
        self.provider = provider
        self.instructions = instructions
        self.task = task
        self.dialect = provider.account.dialect
    }

    /// Nothing. A warming request is a paid call that buys nothing, and
    /// `URLSession` keeps the connection to a host it has just spoken to.
    func prewarm() {}

    func hasRoom(for question: String, keeping budget: Int) async -> Bool {
        guard turns.count < Self.mostTurns else { return false }

        let already = spent ?? Self.estimate(instructions) + turns.reduce(0) { $0 + Self.estimate($1.said) }
        return already + Self.estimate(question) + budget < Self.assumedWindow
    }

    /// About how many tokens a piece of text comes to.
    ///
    /// **Three characters to a token and not four.** French is denser in tokens
    /// than English and a headline is mostly proper nouns, which tokenize
    /// badly ; an estimate that errs high costs one refused story, and one that
    /// errs low costs an answer cut off in the middle of a word.
    static func estimate(_ text: String) -> Int { text.count / 3 + 1 }

    func answer(to question: String, shaped: ResponseShape, keeping budget: Int) async throws(ModelFault) -> Answer {
        guard let base = provider.base else { throw .unusable(.misconfigured) }
        guard !provider.account.model.isEmpty else { throw .unusable(.misconfigured) }

        turns.append(.asked(question))

        // Three rungs, each tried at most once, and the one that answered is
        // remembered for the rest of the exchange.
        var attempts = 0
        while true {
            attempts += 1
            guard attempts <= 3 else { throw .unreadable }

            let exchange = CloudExchange(
                instructions: instructions,
                turns: turns,
                shape: shaped,
                budget: budget,
                model: provider.account.model,
                dialect: dialect,
                endpoint: provider.wire.endpoint(from: base),
                secret: provider.secret,
                headers: [:]
            )

            let request = try provider.wire.request(for: exchange, cappingWith: tokenField)

            let started = Date()
            let status: Int
            let body: Data
            let retryAfter: TimeInterval?
            do {
                (status, body, retryAfter) = try await provider.transport.send(request)
            } catch {
                await record(.failed(error), status: nil, from: started)
                throw error
            }

            switch provider.wire.read(status: status, body: body, retryAfter: retryAfter, shaped: shaped) {
            case .success(let answered):
                turns.append(.answered(answered.written))
                spent = answered.promptTokens.map { $0 + (answered.answerTokens ?? 0) }
                await record(
                    .answered,
                    status: status,
                    from: started,
                    prompt: answered.promptTokens,
                    answer: answered.answerTokens
                )
                return Answer(answered.json)

            case .failure(.fault(let fault)):
                await record(.failed(fault), status: status, from: started)
                throw fault

            case .failure(.wrongTokenField):
                await record(.refused, status: status, from: started)
                Log.enrich.notice("A model service wants the answer cap named the other way, so it is")
                tokenField = tokenField.other

            case .failure(.wrongDialect):
                await record(.refused, status: status, from: started)
                guard let next = Self.rung(under: dialect) else { throw ModelFault.unreadable }
                Log.enrich.notice("A model service would not take a schema, so it is asked for one in words")
                dialect = next
            }
        }
    }

    /// The next rung down, or nothing where there is none.
    static func rung(under dialect: ProviderDialect) -> ProviderDialect? {
        switch dialect {
        case .strictSchema: .jsonObject
        case .jsonObject: .plainText
        case .plainText: nil
        }
    }

    /// What this service was found to want, so the account can remember it.
    var learnt: ProviderDialect { dialect }

    /// Writes down that a call left, and nothing about what it carried.
    ///
    /// One row per request and not per question : a question that dropped a
    /// rung of the ladder cost two calls, and a log that hid the first would be
    /// a log the reader could not reconcile with their bill.
    private func record(
        _ outcome: ProviderCallOutcome,
        status: Int?,
        from started: Date,
        prompt: Int? = nil,
        answer: Int? = nil
    ) async {
        guard let log = provider.log else { return }

        let call = ProviderCall(
            startedAt: started,
            providerID: provider.account.id,
            providerName: provider.account.name,
            kind: provider.account.kind,
            host: provider.host ?? "",
            task: task,
            model: provider.account.model,
            outcome: outcome,
            promptTokens: prompt,
            answerTokens: answer,
            duration: Date().timeIntervalSince(started),
            status: status
        )
        try? await log.write(call)
    }
}

nonisolated extension CloudTurn {
    /// The words of one turn, whoever said them.
    var said: String {
        switch self {
        case .asked(let text), .answered(let text): text
        }
    }
}
