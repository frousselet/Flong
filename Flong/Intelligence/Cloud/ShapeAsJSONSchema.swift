//
//  ShapeAsJSONSchema.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Which of the two JSON Schema dialects a server was found to want.
///
/// **The strict one is a subset and not a superset.** OpenAI's structured
/// outputs honour a schema exactly, and in exchange refuse most of what a
/// schema may say : every property has to be required, nothing may be added,
/// and the bounds on a list are not allowed at all. The plain one is the whole
/// vocabulary, sent to a server that will read it as advice.
nonisolated enum SchemaDialect: Hashable, Sendable {
    case strict
    case plain
}

/// A shape, said as JSON Schema.
///
/// The other rendering of ``ResponseShape``. Every rule about what may be in
/// one is here rather than at the call sites, and the answer is checked against
/// the shape again when it comes back : a schema is a promise about the form of
/// an answer, honoured unevenly, and never a promise about its values.
///
/// **What is deliberately not done here.** `GenerationSchema` is `Codable`, so
/// encoding the framework's own schema would save this whole file. Its encoded
/// form is an undocumented implementation detail with no stability contract,
/// and it has no reason to satisfy the strict dialect's demands. What that buys
/// is a paid call that starts failing after an operating system update, at
/// night, inside a background pass. This is fifty lines and it is ours.
nonisolated extension ResponseShape {
    func jsonSchema(_ dialect: SchemaDialect) -> JSONValue {
        jsonSchema(dialect, saying: nil)
    }

    private func jsonSchema(_ dialect: SchemaDialect, saying description: String?) -> JSONValue {
        var fields: [(String, JSONValue)] = []

        switch self {
        case .words:
            fields.append(("type", .text("string")))
            if let description { fields.append(("description", .text(description))) }

        case .oneOf(_, let choices):
            fields.append(("type", .text("string")))
            if let description { fields.append(("description", .text(description))) }
            fields.append(("enum", .list(choices.map(JSONValue.text))))

        case .list(let item, let least, let most):
            fields.append(("type", .text("array")))
            if let description { fields.append(("description", .text(description))) }
            fields.append(("items", item.jsonSchema(dialect, saying: nil)))
            // **The bounds go where they are allowed and nowhere else.** The
            // strict dialect refuses them outright, and a schema it refuses is
            // a call that fails rather than a list that runs long.
            if dialect == .plain {
                if let least { fields.append(("minItems", .whole(least))) }
                if let most { fields.append(("maxItems", .whole(most))) }
            }

        case .object(_, let properties):
            fields.append(("type", .text("object")))
            if let description { fields.append(("description", .text(description))) }
            fields.append(
                (
                    "properties",
                    .object(properties.map { ($0.name, $0.shape.jsonSchema(dialect, saying: $0.description)) })
                ))
            // **Everything is required under the strict dialect**, optional or
            // not, because that is what it demands. What was optional comes
            // back empty instead, which is what every reader here already
            // treats as an answer.
            let required = dialect == .strict ? properties : properties.filter { !$0.isOptional }
            fields.append(("required", .list(required.map { JSONValue.text($0.name) })))
            fields.append(("additionalProperties", .bool(false)))
        }

        return .object(fields)
    }

    /// The same shape said in words, for a server that takes no schema at all.
    ///
    /// The last rung of the ladder, and it is a real one : several servers a
    /// reader may point Flong at read `response_format` and ignore it. What
    /// they will obey is an instruction, so the shape is put in the
    /// instructions and the answer is checked here as it always was.
    func said() -> String {
        "Answer with this JSON object and nothing else, no code fence and no words around it :\n"
            + jsonSchema(.plain).written
    }
}
