//
//  ProviderClientTests.swift
//  FlongTests
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Synchronization
import Testing

@testable import Flong

/// Talking to a model that is not on this device, without a network.
///
/// Every address is `models.example.com` and every key is obviously not one.
/// What is worth testing is the request that goes out and the reading of what
/// comes back : those are where the bugs are, and a fake conforming to the
/// abstraction would test the abstraction instead.
@Suite("A model that is not on this device", .serialized)
struct ProviderClientTests {
    private static let host = "models.example.com"

    private func account(model: String = "a-model", dialect: ProviderDialect = .strictSchema) -> ProviderAccount {
        ProviderAccount(
            kind: .openAICompatible,
            name: "Mine",
            origin: URL(string: "https://\(Self.host)/v1"),
            model: model,
            dialect: dialect
        )
    }

    private func provider(
        _ stub: StubServer,
        model: String = "a-model",
        dialect: ProviderDialect = .strictSchema,
        key: String = "not-a-real-key"
    ) -> CloudProvider {
        CloudProvider(
            account: account(model: model, dialect: dialect),
            secret: ProviderSecret(key: key),
            wire: OpenAICompatible(),
            transport: CloudTransport(session: stub.makeSession())
        )
    }

    /// What a service answers when it has done what it was asked.
    private static func completion(_ content: String, prompt: Int = 300, answer: Int = 40) -> StubResponse {
        .json(
            """
            {"model":"a-model","choices":[{"message":{"content":\(JSONValue.text(content).written)},\
            "finish_reason":"stop"}],"usage":{"prompt_tokens":\(prompt),"completion_tokens":\(answer)}}
            """
        )
    }

    // MARK: - The question that goes out

    @Test("The key travels as a bearer, and the shape as a schema")
    func theQuestionCarriesTheKeyAndTheShape() async throws {
        let stub = StubServer(host: Self.host)
        defer { stub.reset() }
        stub.install { _ in Self.completion(#"{"title":"Un titre","summary":"Une ligne."}"#) }

        let conversation = provider(stub).conversation(saying: "You write headlines.")
        _ = try await conversation.answer(to: "Some articles", as: GeneratedBrief.self, keeping: 400)

        let request = try #require(stub.requests.first)
        #expect(request.url.path() == "/v1/chat/completions")
        #expect(request.method == "POST")
        #expect(request.headers["Authorization"] == "Bearer not-a-real-key")

        let body = try #require(JSONValue.read(Data(request.body.utf8)))
        #expect(body.field("model")?.asText == "a-model")
        #expect(body.field("temperature")?.asWhole == 0)
        #expect(body.field("max_tokens")?.asWhole == 400)
        #expect(body.field("response_format")?.field("type")?.asText == "json_schema")
        #expect(body.field("response_format")?.field("json_schema")?.field("strict") == .bool(true))
        #expect(body.field("response_format")?.field("json_schema")?.field("name")?.asText == "GeneratedBrief")

        // The instructions first, then what was asked.
        let messages = try #require(body.field("messages")?.asList)
        #expect(messages.first?.field("role")?.asText == "system")
        #expect(messages.first?.field("content")?.asText == "You write headlines.")
        #expect(messages.last?.field("role")?.asText == "user")
    }

    /// A model server on the reader's own network authenticates nobody, and an
    /// empty bearer is a header some of them refuse outright.
    @Test("No key means no header at all")
    func noKeyMeansNoHeader() async throws {
        let stub = StubServer(host: Self.host)
        defer { stub.reset() }
        stub.install { _ in Self.completion(#"{"summary":"Une ligne."}"#) }

        let conversation = provider(stub, key: "").conversation(saying: "You write.")
        _ = try await conversation.answer(to: "Ask", as: GeneratedLine.self, keeping: 200)

        #expect(try #require(stub.requests.first).headers["Authorization"] == nil)
    }

    /// A conversation is what makes `ask it again, it can see what it wrote`
    /// mean the same thing here as it does on the device.
    @Test("What the model wrote comes back to it word for word")
    func theTurnsAreReplayedVerbatim() async throws {
        let stub = StubServer(host: Self.host)
        defer { stub.reset() }
        let written = #"{"title":"Un titre trop long","summary":"Une ligne."}"#
        stub.install { _ in Self.completion(written) }

        let conversation = provider(stub).conversation(saying: "You write headlines.")
        _ = try await conversation.answer(to: "Some articles", as: GeneratedBrief.self, keeping: 400)
        _ = try await conversation.answer(to: "That is too long", as: GeneratedBrief.self, keeping: 400)

        let sentBack = try #require(stub.requests.last?.body)
        let second = try #require(JSONValue.read(Data(sentBack.utf8)))
        let messages = try #require(second.field("messages")?.asList)

        #expect(messages.count == 4)
        #expect(messages[2].field("role")?.asText == "assistant")
        // Word for word, and not a re-serialisation with its keys reordered.
        #expect(messages[2].field("content")?.asText == written)
        #expect(messages[3].field("content")?.asText == "That is too long")
    }

    // MARK: - The ladder of dialects

    /// Several services take the field and four hundred on it. The next rung
    /// down is worth exactly one try, and the rung that answered is kept.
    @Test("A service that will not take a schema is asked for one in words")
    func aRefusedSchemaDropsARung() async throws {
        let stub = StubServer(host: Self.host)
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
            return Self.completion("Voici : ```json\n{\"summary\":\"Une ligne.\"}\n```")
        }

        let conversation = provider(stub).conversation(saying: "You write.")
        let line = try await conversation.answer(to: "Ask", as: GeneratedLine.self, keeping: 200)

        #expect(line.summary == "Une ligne.")
        #expect(stub.requests.count == 2)

        // The second asks for an object rather than a schema, and says the
        // shape in the instructions instead.
        let sentBack = try #require(stub.requests.last?.body)
        let second = try #require(JSONValue.read(Data(sentBack.utf8)))
        #expect(second.field("response_format")?.field("type")?.asText == "json_object")
        #expect(second.field("messages")?.asList?.first?.field("content")?.asText?.contains("\"summary\"") == true)
    }

    /// OpenAI's reasoning models refuse `max_tokens` by name, and most of the
    /// services that copied the format have never heard of the other one.
    @Test("A service that names the cap the other way gets it the other way")
    func theTokenFieldIsLearnt() async throws {
        let stub = StubServer(host: Self.host)
        defer { stub.reset() }

        let asked = Mutex(0)
        stub.install { _ in
            let count = asked.withLock { count -> Int in
                count += 1
                return count
            }
            guard count > 1 else {
                return .json(#"{"error":{"message":"Unsupported parameter: max_tokens"}}"#, status: 400)
            }
            return Self.completion(#"{"summary":"Une ligne."}"#)
        }

        let conversation = provider(stub).conversation(saying: "You write.")
        _ = try await conversation.answer(to: "Ask", as: GeneratedLine.self, keeping: 200)

        let sentBack = try #require(stub.requests.last?.body)
        let second = try #require(JSONValue.read(Data(sentBack.utf8)))
        #expect(second.field("max_completion_tokens")?.asWhole == 200)
        #expect(second.field("max_tokens") == nil)
    }

    // MARK: - What a failure means

    @Test("A refused key is the model itself and a refused story is not")
    func failuresAreToldApart() async throws {
        let table: [(Int, String, ModelFault)] = [
            (401, "{}", .unusable(.notEntitled)),
            (403, "{}", .unusable(.notEntitled)),
            (404, "{}", .unusable(.misconfigured)),
            (429, "{}", .busy(retryAfter: nil)),
            (500, "{}", .busy(retryAfter: nil)),
            (413, "{}", .tooLong),
        ]

        for (status, body, expected) in table {
            let stub = StubServer(host: Self.host)
            defer { stub.reset() }
            stub.install { _ in .json(body, status: status) }

            let conversation = provider(stub).conversation(saying: "You write.")
            await #expect(throws: expected) {
                try await conversation.answer(to: "Ask", as: GeneratedLine.self, keeping: 200)
            }
        }
    }

    @Test("A content filter is about this story and never about the model")
    func aContentFilterIsAboutTheStory() async throws {
        let stub = StubServer(host: Self.host)
        defer { stub.reset() }
        stub.install { _ in
            .json(#"{"choices":[{"message":{"content":""},"finish_reason":"content_filter"}]}"#)
        }

        let conversation = provider(stub).conversation(saying: "You write.")
        await #expect(throws: ModelFault.declined) {
            try await conversation.answer(to: "Ask", as: GeneratedLine.self, keeping: 200)
        }
    }

    @Test("An answer cut off is the same class as one cut off on the device")
    func anAnswerCutOffIsTooLong() async throws {
        let stub = StubServer(host: Self.host)
        defer { stub.reset() }
        stub.install { _ in .json(#"{"choices":[{"message":{"content":"{"},"finish_reason":"length"}]}"#) }

        let conversation = provider(stub).conversation(saying: "You write.")
        await #expect(throws: ModelFault.tooLong) {
            try await conversation.answer(to: "Ask", as: GeneratedLine.self, keeping: 200)
        }
    }

    @Test("Something that is not JSON at all is unreadable and nothing worse")
    func rubbishIsUnreadable() async throws {
        let stub = StubServer(host: Self.host)
        defer { stub.reset() }
        stub.install { _ in .json(#"{"choices":[{"message":{"content":"je ne sais pas"}}]}"#) }

        let conversation = provider(stub).conversation(saying: "You write.")
        await #expect(throws: ModelFault.unreadable) {
            try await conversation.answer(to: "Ask", as: GeneratedLine.self, keeping: 200)
        }
    }

    // MARK: - What must never go out

    /// The security property of this whole feature, tested rather than
    /// reviewed : what leaves is headlines and standfirsts, and never a body,
    /// a feed address, a credential or anything of the reader's own.
    @Test("An article's body never leaves the device")
    func theBodyNeverLeaves() async throws {
        let stub = StubServer(host: Self.host)
        defer { stub.reset() }
        stub.install { _ in Self.completion(#"{"title":"Un titre","summary":"Une ligne."}"#) }

        let summarizer = StorySummarizer(
            locale: Locale(identifier: "fr_FR"),
            hand: ModelHand(
                task: .headlines,
                provider: provider(stub),
                patience: ModelPatience(with: "test")
            )
        )

        _ = await summarizer.brief(forArticles: [
            (title: "Un titre publié", excerpt: "Le chapeau publié."),
            (title: "Un autre titre", excerpt: nil),
        ])

        let sent = try #require(stub.requests.first?.body)

        #expect(sent.contains("Un titre publié"))
        // Nothing of the article beyond its headline and its published line,
        // and nothing about where it came from.
        #expect(!sent.contains("https://"))
        #expect(!sent.lowercased().contains("feed"))
    }

    @Test("A key never reaches a log line or an error a reader could see")
    func theKeyStaysInTheRequest() async throws {
        let stub = StubServer(host: Self.host)
        defer { stub.reset() }
        stub.install { _ in .json(#"{"error":{"message":"Incorrect API key provided: not-a-real-key"}}"#, status: 401) }

        let conversation = provider(stub).conversation(saying: "You write.")
        do {
            _ = try await conversation.answer(to: "Ask", as: GeneratedLine.self, keeping: 200)
            Issue.record("A refused key is a failure")
        } catch {
            // Nothing from the wire is carried, which is what makes this
            // provable rather than hoped for.
            #expect(!String(describing: error).contains("not-a-real-key"))
        }
    }
}
