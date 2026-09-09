//
//  OpenAICompatible.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The format almost every service speaks, and its imitators' unevenness.
///
/// **One dialect and three rungs.** OpenAI honours a schema exactly. Several of
/// the services and servers that copied the format take the field and ignore
/// it, take only `json_object`, or four hundred on the whole parameter. There
/// is no telling which without asking, so the question is asked in the best way
/// first and drops a rung on a refusal that names the parameter, and the rung
/// that answered is written down on the account.
///
/// **The reader gives the base and the path is ours.** `https://api.openai.com/v1`,
/// `http://192.168.1.20:11434/v1`, `https://openrouter.ai/api/v1` and a private
/// gateway all work with the same code, and whatever `/v1` a service wants is
/// part of what the reader typed.
nonisolated struct OpenAICompatible: CloudWire {
    func endpoint(from base: URL) -> URL {
        base.appending(path: "chat/completions")
    }

    func modelsEndpoint(from base: URL) -> URL {
        base.appending(path: "models")
    }

    // MARK: - The question

    func request(for exchange: CloudExchange, cappingWith field: TokenField) throws(ModelFault) -> URLRequest {
        guard LocalNetwork.allowsPlainHTTP(exchange.endpoint) else { throw .unusable(.misconfigured) }

        var request = URLRequest(url: exchange.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(FeedFetcher.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        // **Omitted rather than sent empty** : a model server on the reader's
        // own network authenticates nobody, and an empty bearer is a header
        // some of them refuse outright.
        if !exchange.secret.key.isEmpty {
            request.setValue("Bearer \(exchange.secret.key)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in exchange.headers { request.setValue(value, forHTTPHeaderField: name) }
        // A night's work is not the reader's data plan to spend, and the one
        // task somebody waits on is short. Left to the system either way : a
        // request it will not send comes back as never attempted.
        request.allowsExpensiveNetworkAccess = true

        var body: [(String, JSONValue)] = [
            ("model", .text(exchange.model)),
            ("messages", .list(Self.messages(of: exchange))),
            // Nought, for the reason the model on the device samples greedily :
            // the same story asked twice should come back the same. It is a
            // hope rather than a guarantee at a distance, and what actually
            // stops a page being rewritten is that a story already written
            // about is never asked again.
            ("temperature", .number(0)),
            (field.rawValue, .whole(exchange.budget)),
            ("stream", .bool(false)),
        ]

        if let format = Self.responseFormat(of: exchange) { body.append(("response_format", format)) }

        request.httpBody = Data(JSONValue.object(body).written.utf8)
        return request
    }

    /// The instructions, then everything that has been said.
    static func messages(of exchange: CloudExchange) -> [JSONValue] {
        var instructions = exchange.instructions
        // Where the service will not be held to a schema, the shape is said in
        // words instead. It is the only thing those rungs will obey.
        if exchange.dialect != .strictSchema {
            instructions += "\n\n" + exchange.shape.said()
        }

        var messages: [JSONValue] = [.object([("role", .text("system")), ("content", .text(instructions))])]
        for turn in exchange.turns {
            switch turn {
            case .asked(let text):
                messages.append(.object([("role", .text("user")), ("content", .text(text))]))
            case .answered(let text):
                messages.append(.object([("role", .text("assistant")), ("content", .text(text))]))
            }
        }
        return messages
    }

    static func responseFormat(of exchange: CloudExchange) -> JSONValue? {
        switch exchange.dialect {
        case .strictSchema:
            .object([
                ("type", .text("json_schema")),
                (
                    "json_schema",
                    .object([
                        // Some servers demand a bare identifier here, so it is
                        // the shape's own name and never a sentence.
                        ("name", .text(exchange.shape.name)),
                        ("strict", .bool(true)),
                        ("schema", exchange.shape.jsonSchema(.strict)),
                    ])
                ),
            ])
        case .jsonObject:
            .object([("type", .text("json_object"))])
        case .plainText:
            nil
        }
    }

    // MARK: - The answer

    func read(
        status: Int,
        body: Data,
        retryAfter: TimeInterval?,
        shaped: ResponseShape
    ) -> Result<CloudAnswer, CloudTrouble> {
        let json = JSONValue.read(body)

        guard (200..<300).contains(status) else {
            return .failure(Self.trouble(status: status, body: json, retryAfter: retryAfter))
        }
        guard let json, let choice = json.field("choices")?.asList?.first else {
            return .failure(.fault(.unreadable))
        }

        let message = choice.field("message")

        // Some services put a refusal in a field of its own rather than in the
        // content, and it is this content and not the model.
        if let refusal = message?.field("refusal")?.asText, !refusal.isEmpty {
            return .failure(.fault(.declined))
        }

        switch choice.field("finish_reason")?.asText {
        case "content_filter":
            return .failure(.fault(.declined))
        case "length":
            // The same class as an answer cut off on the device : this thing
            // and not the model.
            return .failure(.fault(.tooLong))
        default:
            break
        }

        guard let written = message?.field("content")?.asText, !written.isEmpty else {
            return .failure(.fault(.declined))
        }
        guard let answered = Self.object(in: written) else {
            return .failure(.fault(.unreadable))
        }

        let usage = json.field("usage")
        return .success(
            CloudAnswer(
                json: answered,
                written: written,
                promptTokens: usage?.field("prompt_tokens")?.asWhole,
                answerTokens: usage?.field("completion_tokens")?.asWhole,
                model: json.field("model")?.asText
            )
        )
    }

    /// What a status means, in the terms the callers act on.
    static func trouble(status: Int, body: JSONValue?, retryAfter: TimeInterval?) -> CloudTrouble {
        let message = (body?.field("error")?.field("message")?.asText ?? "").lowercased()

        switch status {
        case 401, 403:
            return .fault(.unusable(.notEntitled))
        case 404:
            // A wrong base address is the commonest configuration mistake there
            // is, and reporting it as a missing model would send the reader
            // looking in the wrong field.
            return .fault(.unusable(.misconfigured))
        case 413:
            return .fault(.tooLong)
        case 429, 503, 529:
            return .fault(.busy(retryAfter: retryAfter))
        case 500, 502, 504:
            // A gateway is a gateway, and coming back later is the answer.
            return .fault(.busy(retryAfter: nil))
        case 400, 422:
            if Self.namesTheTokenField(message) { return .wrongTokenField }
            if Self.namesTheSchema(message) { return .wrongDialect }
            if message.contains("content_filter") || message.contains("content_policy") {
                return .fault(.declined)
            }
            if message.contains("context length") || message.contains("too long") {
                return .fault(.tooLong)
            }
            return .fault(.unusable(.misconfigured))
        default:
            return .fault(.unusable(.unreachable))
        }
    }

    static func namesTheSchema(_ message: String) -> Bool {
        ["response_format", "json_schema", "json schema", "structured output", "strict"]
            .contains { message.contains($0) }
    }

    static func namesTheTokenField(_ message: String) -> Bool {
        message.contains("max_tokens") || message.contains("max_completion_tokens")
    }

    /// The object inside whatever came back.
    ///
    /// **The lower rungs answer wrapped, as often as not** : a fenced code
    /// block, a sentence in front of it, or both. What is wanted is the
    /// outermost balanced object, and where the answer is already one this
    /// costs a single scan.
    static func object(in written: String) -> JSONValue? {
        if let json = JSONValue.read(Data(written.utf8)), case .object = json { return json }

        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false

        for index in written.indices {
            let character = written[index]

            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"":
                inString = true
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, let start {
                    let text = String(written[start...index])
                    if let json = JSONValue.read(Data(text.utf8)) { return json }
                }
            default:
                break
            }
        }
        return nil
    }

    // MARK: - Which models it offers

    func modelsRequest(at endpoint: URL, with secret: ProviderSecret, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.setValue(FeedFetcher.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        if !secret.key.isEmpty {
            request.setValue("Bearer \(secret.key)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    func models(from body: Data) -> [ProviderModel] {
        guard let list = JSONValue.read(body)?.field("data")?.asList else { return [] }

        return list.compactMap { entry in
            guard let id = entry.field("id")?.asText else { return nil }
            // A Unix integer here, where Anthropic answers a date in words.
            let added = entry.field("created")?.asWhole.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            return ProviderModel(id: id, name: nil, addedAt: added)
        }
    }
}
