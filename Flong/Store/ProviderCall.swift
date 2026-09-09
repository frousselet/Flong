//
//  ProviderCall.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB

/// How one call to a model of the reader's own ended.
nonisolated enum ProviderCallOutcome: String, Codable, Hashable, Sendable, CaseIterable {
    case answered
    /// This thing, and not the model : it read what it was shown and would not
    /// write about it.
    case declined
    case busy
    /// The key, the model name, the address.
    case refused
    case failed
    case cancelled

    /// What one failure is filed as.
    ///
    /// The same three the callers already draw, said in the words a reader
    /// reads : a service that declined this story is a different row from one
    /// that refused the key.
    static func failed(_ fault: ModelFault) -> ProviderCallOutcome {
        switch fault {
        case .declined, .tooLong: .declined
        case .unreadable: .failed
        case .busy: .busy
        case .unusable(.cancelled): .cancelled
        case .unusable(.notEntitled), .unusable(.misconfigured): .refused
        case .unusable: .failed
        }
    }
}

/// One call that left this device for a model that is not the system's own.
///
/// Section 14 asks for this in one clause, and what the clause implies is a
/// table with almost nothing in it : the moment, whose model, which task, which
/// host, which model, what it cost and how it ended.
///
/// **The envelope and never the letter.** There is no column for the prompt,
/// the answer, the articles, the key or the body of an error, and the absence
/// of the column is what enforces it. A log that recorded the prompt would be a
/// second copy of everything the consent was careful about, kept on the
/// reader's own disk where nothing would ever purge it. A log that recorded an
/// error body would be worse : several services echo the prompt there, and one
/// of them echoes the key.
///
/// **The provider is named twice on purpose.** `providerID` points at an
/// account the reader may delete tomorrow ; the name, the host and the model
/// are copied onto the row. It is the rule an edition already follows against a
/// story : a record of what happened must not change when the thing it happened
/// to is edited or removed, or the log would rewrite the reader's own history
/// behind them.
nonisolated struct ProviderCall: Identifiable, Hashable, StoredRecord {
    static let databaseTableName = "provider_call"

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "started_at"
        case providerID = "provider_id"
        case providerName = "provider_name"
        case kind
        case host
        case task
        case model
        case outcome
        case promptTokens = "prompt_tokens"
        case answerTokens = "answer_tokens"
        case duration
        case status
    }

    var id: UUID
    var startedAt: Date
    var providerID: UUID
    /// Copied, so a deleted account does not rewrite what already happened.
    var providerName: String
    var kind: ProviderKind
    /// The host and never the whole address : a private endpoint keeps its
    /// path, and the host is what the consent already named out loud.
    var host: String
    var task: ModelTask
    var model: String
    var outcome: ProviderCallOutcome
    /// Nothing where the service did not say, which is a different fact from
    /// nought and reads differently in a month's total.
    var promptTokens: Int?
    var answerTokens: Int?
    var duration: TimeInterval
    /// The status a server answered with, and never a message body.
    var status: Int?

    init(
        id: UUID = .v7(),
        startedAt: Date,
        providerID: UUID,
        providerName: String,
        kind: ProviderKind,
        host: String,
        task: ModelTask,
        model: String,
        outcome: ProviderCallOutcome,
        promptTokens: Int? = nil,
        answerTokens: Int? = nil,
        duration: TimeInterval,
        status: Int? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.providerID = providerID
        self.providerName = providerName
        self.kind = kind
        self.host = host
        self.task = task
        self.model = model
        self.outcome = outcome
        self.promptTokens = promptTokens
        self.answerTokens = answerTokens
        self.duration = duration
        self.status = status
    }
}

/// What has been asked of a model that is not on this device.
///
/// **Not synchronized, and that costs no work** : a table is only carried into
/// CloudKit when the sync layer is told about it, and it will not be. What one
/// device sent is a fact about that device.
nonisolated struct ProviderCallLog: Sendable {
    /// How many rows are kept.
    ///
    /// Two thousand, which is a month of heavy use and about a quarter of a
    /// megabyte. A log that grew without bound would be the one thing on the
    /// device that nothing ever purges.
    static let mostRows = 2_000

    /// And how long, whichever comes first.
    static let keptFor: TimeInterval = 90 * 24 * 60 * 60

    /// How often the trimming is actually done.
    ///
    /// **Not on every insert.** A delete that scanned the table would run two
    /// hundred times during one filing pass for a bound nothing crosses in a
    /// night, so it is done once in a hundred and at the head of every pass.
    static let trimEvery = 100

    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    func write(_ call: ProviderCall) async throws {
        let count = try await database.writer.write { db -> Int in
            try call.insert(db)
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM provider_call") ?? 0
        }
        guard count % Self.trimEvery == 0 else { return }
        try await trim(now: call.startedAt)
    }

    /// Drops what is past either bound.
    func trim(now: Date = Date()) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM provider_call WHERE started_at < ?",
                arguments: [now.addingTimeInterval(-Self.keptFor)]
            )
            try db.execute(
                sql: """
                    DELETE FROM provider_call WHERE id NOT IN (
                        SELECT id FROM provider_call ORDER BY started_at DESC LIMIT ?
                    )
                    """,
                arguments: [Self.mostRows]
            )
        }
    }

    /// The calls, newest first.
    func recent(limit: Int = 200) async throws -> [ProviderCall] {
        try await database.writer.read { db in
            try ProviderCall
                .order(Column("started_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func count() async throws -> Int {
        try await database.writer.read { db in
            try ProviderCall.fetchCount(db)
        }
    }

    /// What has gone out since a moment, gathered the way the page shows it.
    func spending(since moment: Date) async throws -> (calls: Int, prompt: Int, answer: Int) {
        try await database.writer.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) AS calls,
                           COALESCE(SUM(prompt_tokens), 0) AS prompt,
                           COALESCE(SUM(answer_tokens), 0) AS answer
                    FROM provider_call WHERE started_at >= ?
                    """,
                arguments: [moment]
            )
            guard let row else { return (0, 0, 0) }
            return (row["calls"] as Int, row["prompt"] as Int, row["answer"] as Int)
        }
    }

    func removeEverything() async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM provider_call")
        }
    }
}
