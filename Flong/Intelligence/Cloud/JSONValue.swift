//
//  JSONValue.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// A piece of JSON of a shape nothing knows in advance.
///
/// Written out rather than reached for : there is no dependency to reach for,
/// and what is needed is small. It carries a schema on the way out and an
/// answer on the way back, and both are trees whose shape somebody else
/// decides.
///
/// **The order of an object's keys is kept.** A schema whose properties came
/// out in a different order every launch would be a different prompt every
/// launch, and a model reads a schema as part of the question.
nonisolated indirect enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case whole(Int)
    case text(String)
    case list([JSONValue])
    case object([Field])

    /// One named field, since a dictionary would lose the order.
    nonisolated struct Field: Hashable, Sendable {
        let name: String
        let value: JSONValue

        init(_ name: String, _ value: JSONValue) {
            self.name = name
            self.value = value
        }
    }

    static func object(_ fields: [(String, JSONValue)]) -> JSONValue {
        .object(fields.map(Field.init))
    }
}

// MARK: - Writing it out

nonisolated extension JSONValue {
    /// What goes on the wire.
    ///
    /// Written by hand rather than through `JSONSerialization`, which leaves an
    /// object's key order to a dictionary, and the order is part of the
    /// question.
    var written: String {
        switch self {
        case .null: "null"
        case .bool(let value): value ? "true" : "false"
        case .whole(let value): String(value)
        case .number(let value): value == value.rounded() ? String(Int(value)) : String(value)
        case .text(let value): Self.quoted(value)
        case .list(let values): "[" + values.map(\.written).joined(separator: ",") + "]"
        case .object(let fields):
            "{" + fields.map { "\(Self.quoted($0.name)):\($0.value.written)" }.joined(separator: ",") + "}"
        }
    }

    /// A string, escaped as JSON wants it.
    ///
    /// The control characters are the ones that matter : a headline arrives
    /// with whatever the publisher's template put in it, and a raw newline
    /// inside a string is a body no server will parse.
    static func quoted(_ text: String) -> String {
        var written = "\""
        for character in text.unicodeScalars {
            switch character {
            case "\"": written += "\\\""
            case "\\": written += "\\\\"
            case "\n": written += "\\n"
            case "\r": written += "\\r"
            case "\t": written += "\\t"
            default:
                if character.value < 0x20 {
                    written += String(format: "\\u%04x", character.value)
                } else {
                    written.unicodeScalars.append(character)
                }
            }
        }
        return written + "\""
    }
}

// MARK: - Reading it back

nonisolated extension JSONValue {
    /// What a service answered.
    ///
    /// Through `JSONSerialization`, since reading is the half where nothing
    /// depends on the order and everything depends on being forgiving of what
    /// somebody else wrote.
    static func read(_ data: Data) -> JSONValue? {
        guard let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return JSONValue(any)
    }

    init?(_ any: Any) {
        switch any {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            // `NSNumber` does not tell a boolean from a one, and the two mean
            // different things in an answer.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let text as String:
            self = .text(text)
        case let list as [Any]:
            self = .list(list.compactMap(JSONValue.init))
        case let object as [String: Any]:
            self = .object(
                object.keys.sorted().compactMap { name in
                    JSONValue(object[name] as Any).map { Field(name, $0) }
                }
            )
        default:
            return nil
        }
    }

    /// One field of an object, by name.
    func field(_ name: String) -> JSONValue? {
        guard case .object(let fields) = self else { return nil }
        return fields.first { $0.name == name }?.value
    }

    var asText: String? {
        guard case .text(let value) = self else { return nil }
        return value
    }

    var asWhole: Int? {
        switch self {
        case .whole(let value): value
        case .number(let value): Int(value)
        default: nil
        }
    }

    var asList: [JSONValue]? {
        guard case .list(let values) = self else { return nil }
        return values
    }
}

// MARK: - The answer, from the wire

nonisolated extension Answer {
    /// What a service answered, read into the tree every caller reads.
    init(_ json: JSONValue) {
        switch json {
        case .null: self = .nothing
        case .bool(let value): self = .flag(value)
        case .number(let value): self = .number(value)
        case .whole(let value): self = .number(Double(value))
        case .text(let value): self = .word(value)
        case .list(let values): self = .list(values.map(Answer.init))
        case .object(let fields):
            self = .fields(fields.reduce(into: [:]) { $0[$1.name] = Answer($1.value) })
        }
    }
}
