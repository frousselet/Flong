//
//  ProviderCallLogTests.swift
//  FlongTests
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import Synchronization
import Testing

@testable import Flong

/// What is written down about a call that left this device.
///
/// Section 14 asks for the log in one clause. What the clause implies is the
/// envelope and never the letter, and the strongest thing that can be said
/// about that is said here : no column of a row ever holds the prompt, the
/// articles, the key or the body of an error.
@Suite("What was sent away")
struct ProviderCallLogTests {
    private func log() async throws -> (ProviderCallLog, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (ProviderCallLog(database), database)
    }

    private func call(
        at moment: Date = Date(),
        outcome: ProviderCallOutcome = .answered,
        host: String = "models.example.com"
    ) -> ProviderCall {
        ProviderCall(
            startedAt: moment,
            providerID: .v7(),
            providerName: "Mine",
            kind: .openAICompatible,
            host: host,
            task: .headlines,
            model: "a-model",
            outcome: outcome,
            promptTokens: 300,
            answerTokens: 40,
            duration: 1.2,
            status: 200
        )
    }

    @Test("A row goes in and comes back whole")
    func roundTrip() async throws {
        let (log, _) = try await self.log()
        try await log.write(call())

        let written = try #require(try await log.recent().first)

        #expect(written.providerName == "Mine")
        #expect(written.task == .headlines)
        #expect(written.host == "models.example.com")
        #expect(written.promptTokens == 300)
        #expect(written.status == 200)
        #expect(written.outcome == .answered)
    }

    @Test("The newest is first, whatever order they arrived in")
    func newestFirst() async throws {
        let (log, _) = try await self.log()
        let now = Date()
        try await log.write(call(at: now.addingTimeInterval(-60), host: "old.example.com"))
        try await log.write(call(at: now, host: "new.example.com"))

        #expect(try await log.recent().map(\.host) == ["new.example.com", "old.example.com"])
    }

    /// The security property of the whole log, tested rather than reviewed.
    /// There is no column for any of these, and the absence of the column is
    /// what enforces it : this is what would notice one being added.
    @Test("No row ever holds a prompt, an article, a key or an error's words")
    func theLogHoldsNoneOfIt() async throws {
        let (log, database) = try await self.log()
        try await log.write(call())

        let columns = try await database.writer.read { db in
            try db.columns(in: "provider_call").map(\.name)
        }

        #expect(!columns.contains("prompt"))
        #expect(!columns.contains("question"))
        #expect(!columns.contains("answer"))
        #expect(!columns.contains("content"))
        #expect(!columns.contains("key"))
        #expect(!columns.contains("message"))
        #expect(!columns.contains("body"))
        #expect(!columns.contains("url"))

        // And what a row does say, in full, so that a column added later has to
        // be added here too.
        #expect(
            Set(columns) == [
                "id", "started_at", "provider_id", "provider_name", "kind", "host",
                "task", "model", "outcome", "prompt_tokens", "answer_tokens", "duration", "status",
            ]
        )
    }

    /// A log that grew without bound would be the one thing on the device that
    /// nothing ever purges.
    @Test("What is past either bound is dropped")
    func bothBoundsHold() async throws {
        let (log, _) = try await self.log()
        let now = Date()

        try await log.write(
            call(at: now.addingTimeInterval(-ProviderCallLog.keptFor - 60), host: "ancient.example.com"))
        try await log.write(call(at: now, host: "today.example.com"))
        try await log.trim(now: now)

        #expect(try await log.recent().map(\.host) == ["today.example.com"])
    }

    @Test("What a month cost is asked of the store rather than counted here")
    func spendingIsSummed() async throws {
        let (log, _) = try await self.log()
        let now = Date()
        try await log.write(call(at: now))
        try await log.write(call(at: now))
        try await log.write(call(at: now.addingTimeInterval(-3600)))

        let spent = try await log.spending(since: now.addingTimeInterval(-60))

        #expect(spent.calls == 2)
        #expect(spent.prompt == 600)
        #expect(spent.answer == 80)
    }

    /// A question that dropped a rung of the ladder cost two calls, and a log
    /// that hid the first would be one the reader could not reconcile with
    /// their bill.
    @Test("Every request that left is a row, ladder and all")
    func everyRequestIsARow() async throws {
        let database = try AppDatabase.inMemory()
        let log = ProviderCallLog(database)
        let stub = StubServer(host: "logged.example.com")
        defer { stub.reset() }

        let asked = Mutex(0)
        stub.install { _ in
            let count = asked.withLock { count -> Int in
                count += 1
                return count
            }
            guard count > 1 else {
                return .json(#"{"error":{"message":"response_format is not supported"}}"#, status: 400)
            }
            return .json(
                #"{"choices":[{"message":{"content":"{\"summary\":\"Une ligne.\"}"},"finish_reason":"stop"}],"#
                    + #""usage":{"prompt_tokens":120,"completion_tokens":8}}"#
            )
        }

        let provider = CloudProvider(
            account: ProviderAccount(
                kind: .openAICompatible,
                name: "Mine",
                origin: URL(string: "https://logged.example.com/v1"),
                model: "a-model"
            ),
            task: .editions,
            secret: ProviderSecret(key: "not-a-real-key"),
            wire: OpenAICompatible(),
            transport: CloudTransport(session: stub.makeSession()),
            log: log
        )

        _ = try await provider.conversation(saying: "You write.")
            .answer(to: "Ask", as: GeneratedLine.self, keeping: 200)

        let rows = try await log.recent()
        #expect(rows.count == 2)
        #expect(rows.map(\.outcome) == [.answered, .refused])
        #expect(rows.allSatisfy { $0.task == .editions })
        #expect(rows.first?.promptTokens == 120)
        // The host and never the whole address.
        #expect(rows.allSatisfy { $0.host == "logged.example.com" })
    }
}
