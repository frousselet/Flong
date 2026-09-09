//
//  AnthropicMessages.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Anthropic's own format.
///
/// **One tool, forced, and no ladder.** There is no `response_format` here and
/// no dialects to discover : the shape goes over as the input schema of a
/// single tool, and the answer is required to be a call to it. That makes this
/// the simpler of the two wire formats in the one respect that matters, and it
/// is why nothing in here learns anything about the server it is talking to.
nonisolated struct AnthropicMessages: CloudWire {
    /// What the header names, and what the service reads it as.
    ///
    /// A version and not a date : it is the shape of the request that is being
    /// pinned, and pinning it is what stops a change at the other end
    /// rewriting what this file means.
    static let version = "2023-06-01"

    /// What the one tool is called.
    ///
    /// Fixed rather than the shape's own name : the model is told what to fill
    /// in by the schema, and a tool called after the shape would put the shape's
    /// name in two places that then have to agree.
    static let tool = "answer"

    func endpoint(from base: URL) -> URL {
        base.appending(path: "messages")
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
        request.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        // Never `Authorization: Bearer`, which this service does not read.
        if !exchange.secret.key.isEmpty {
            request.setValue(exchange.secret.key, forHTTPHeaderField: "x-api-key")
        }
        for (name, value) in exchange.headers { request.setValue(value, forHTTPHeaderField: name) }
        request.allowsExpensiveNetworkAccess = true

        let body: [(String, JSONValue)] = [
            ("model", .text(exchange.model)),
            // Always this name here. The other one is an OpenAI question.
            ("max_tokens", .whole(exchange.budget)),
            ("system", .text(exchange.instructions)),
            ("messages", .list(Self.messages(of: exchange))),
            ("temperature", .number(0)),
            (
                "tools",
                .list([
                    .object([
                        ("name", .text(Self.tool)),
                        ("description", .text("The answer, in the shape it has to have")),
                        // The plain dialect, since this service takes the whole
                        // vocabulary : the bounds on a list are allowed here
                        // and are worth having.
                        ("input_schema", exchange.shape.jsonSchema(.plain)),
                    ])
                ])
            ),
            (
                "tool_choice",
                .object([
                    ("type", .text("tool")),
                    ("name", .text(Self.tool)),
                    // One tool is offered, so there is nowhere else to go, and
                    // one call is what a headline costs.
                    ("disable_parallel_tool_use", .bool(true)),
                ])
            ),
        ]

        request.httpBody = Data(JSONValue.object(body).written.utf8)
        return request
    }

    /// Everything that has been said, the instructions being a field of their
    /// own here rather than a first message.
    ///
    /// **What the model wrote comes back as text and not as a tool call.** A
    /// `tool_use` block in a transcript has to be answered by a `tool_result`,
    /// which would mean inventing a result for a tool that does nothing. The
    /// tool is forced again on every turn, so what matters is that the model
    /// can read what it wrote, and its own words as text are exactly that.
    static func messages(of exchange: CloudExchange) -> [JSONValue] {
        exchange.turns.map { turn in
            switch turn {
            case .asked(let text):
                .object([("role", .text("user")), ("content", .text(text))])
            case .answered(let text):
                .object([("role", .text("assistant")), ("content", .text(text))])
            }
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
        guard let json else { return .failure(.fault(.unreadable)) }

        switch json.field("stop_reason")?.asText {
        case "refusal":
            return .failure(.fault(.declined))
        case "max_tokens":
            return .failure(.fault(.tooLong))
        default:
            break
        }

        let blocks = json.field("content")?.asList ?? []
        guard
            let used = blocks.first(where: { $0.field("type")?.asText == "tool_use" }),
            let input = used.field("input")
        else {
            // It answered in prose rather than filling in the shape, which is
            // this thing and not the service.
            return .failure(.fault(.declined))
        }

        let usage = json.field("usage")
        return .success(
            CloudAnswer(
                json: input,
                written: input.written,
                promptTokens: usage?.field("input_tokens")?.asWhole,
                answerTokens: usage?.field("output_tokens")?.asWhole,
                model: json.field("model")?.asText
            )
        )
    }

    /// What a status means, in the terms the callers act on.
    ///
    /// The path is fixed here, unlike the OpenAI format where the reader gives
    /// the base : a four hundred and four really is the model, and saying so
    /// sends them to the right field.
    static func trouble(status: Int, body: JSONValue?, retryAfter: TimeInterval?) -> CloudTrouble {
        let kind = body?.field("error")?.field("type")?.asText ?? ""
        let message = (body?.field("error")?.field("message")?.asText ?? "").lowercased()

        switch status {
        case 401, 403:
            return .fault(.unusable(.notEntitled))
        case 404:
            return .fault(.unusable(.misconfigured))
        case 413:
            return .fault(.tooLong)
        case 429, 529:
            return .fault(.busy(retryAfter: retryAfter))
        case 500, 502, 503, 504:
            return .fault(.busy(retryAfter: nil))
        case 400, 422:
            if message.contains("context window") || message.contains("too long") || message.contains("max_tokens") {
                return .fault(.tooLong)
            }
            return .fault(.unusable(.misconfigured))
        default:
            return kind == "overloaded_error" ? .fault(.busy(retryAfter: nil)) : .fault(.unusable(.unreachable))
        }
    }

    // MARK: - Which models it offers

    func modelsRequest(at endpoint: URL, with secret: ProviderSecret, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.setValue(FeedFetcher.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        if !secret.key.isEmpty { request.setValue(secret.key, forHTTPHeaderField: "x-api-key") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    /// The list, whose moment is a date in words here where the other format
    /// answers a number of seconds. Two readers, and worth a line so that
    /// nobody unifies them by mistake.
    func models(from body: Data) -> [ProviderModel] {
        guard let list = JSONValue.read(body)?.field("data")?.asList else { return [] }

        let dates = ISO8601DateFormatter()
        return list.compactMap { entry in
            guard let id = entry.field("id")?.asText else { return nil }
            return ProviderModel(
                id: id,
                name: entry.field("display_name")?.asText,
                addedAt: entry.field("created_at")?.asText.flatMap(dates.date(from:))
            )
        }
    }
}
