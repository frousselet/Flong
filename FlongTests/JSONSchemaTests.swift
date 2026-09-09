//
//  JSONSchemaTests.swift
//  FlongTests
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

/// A shape, said as JSON Schema.
///
/// The other half of ``ResponseShapeTests`` : the same four cases, rendered for
/// something that is not the framework. What is worth holding is the rules the
/// strict dialect imposes, since breaking one of them is a call refused rather
/// than an answer of the wrong shape.
@Suite("A shape, said as JSON Schema")
struct JSONSchemaTests {
    private let shape = ResponseShape.object(
        named: "Brief",
        fields: [
            .init("title", "The headline"),
            .init("kind", "Which sort", .oneOf(named: "Kind", choices: ["news", "opinion"])),
            .init("points", "The points", .list(of: .words, least: 2, most: 3)),
            .init("note", "Anything else", .words, isOptional: true),
        ]
    )

    @Test("An object says what it holds and forbids anything else")
    func anObjectIsClosed() {
        let schema = shape.jsonSchema(.strict)

        #expect(schema.field("type")?.asText == "object")
        #expect(schema.field("additionalProperties") == .bool(false))
        #expect(schema.field("properties")?.field("title")?.field("type")?.asText == "string")
        #expect(schema.field("properties")?.field("title")?.field("description")?.asText == "The headline")
    }

    /// The strict dialect demands every property in `required`, optional or
    /// not. What was optional comes back empty instead, which every reader here
    /// already treats as an answer.
    @Test("Under the strict dialect everything is required")
    func strictRequiresEverything() {
        let required = shape.jsonSchema(.strict).field("required")?.asList?.compactMap(\.asText)
        #expect(required == ["title", "kind", "points", "note"])

        let plain = shape.jsonSchema(.plain).field("required")?.asList?.compactMap(\.asText)
        #expect(plain == ["title", "kind", "points"])
    }

    /// A schema the strict dialect refuses is a call that fails rather than a
    /// list that runs long.
    @Test("The bounds on a list go where they are allowed and nowhere else")
    func boundsOnlyWhereAllowed() {
        let strict = shape.jsonSchema(.strict).field("properties")?.field("points")
        #expect(strict?.field("minItems") == nil)
        #expect(strict?.field("maxItems") == nil)

        let plain = shape.jsonSchema(.plain).field("properties")?.field("points")
        #expect(plain?.field("minItems") == .whole(2))
        #expect(plain?.field("maxItems") == .whole(3))
    }

    @Test("A choice is a string out of a list, and nothing else")
    func aChoiceIsAnEnumeration() {
        let kind = shape.jsonSchema(.strict).field("properties")?.field("kind")

        #expect(kind?.field("type")?.asText == "string")
        #expect(kind?.field("enum")?.asList?.compactMap(\.asText) == ["news", "opinion"])
    }

    /// A schema whose properties came out in a different order every launch
    /// would be a different prompt every launch.
    @Test("The order of the fields is the order they were declared in")
    func theOrderIsKept() {
        let written = shape.jsonSchema(.strict).written
        let title = try! #require(written.range(of: "\"title\""))
        let points = try! #require(written.range(of: "\"points\""))

        #expect(title.lowerBound < points.lowerBound)
    }

    @Test("What is written is JSON a service can read")
    func whatIsWrittenParses() throws {
        let written = shape.jsonSchema(.strict).written
        let read = try #require(JSONValue.read(Data(written.utf8)))

        #expect(read.field("type")?.asText == "object")
        #expect(read.field("properties")?.field("note")?.field("type")?.asText == "string")
    }

    /// A headline arrives with whatever the publisher's template put in it, and
    /// a raw newline inside a string is a body no server will parse.
    @Test("A string is escaped as JSON wants it")
    func stringsAreEscaped() throws {
        let written = JSONValue.object([("t", .text("Il a dit \"non\"\nà la réforme\\"))]).written
        let read = try #require(JSONValue.read(Data(written.utf8)))

        #expect(read.field("t")?.asText == "Il a dit \"non\"\nà la réforme\\")
    }

    @Test("An answer from the wire is the tree every caller reads")
    func theWireAnswerIsRenamed() throws {
        let json = try #require(JSONValue.read(Data(#"{"title":"Un titre","points":["un","deux"]}"#.utf8)))

        #expect(Answer(json) == .fields(["title": .word("Un titre"), "points": .list([.word("un"), .word("deux")])]))
    }

    /// The last rung : several servers read `response_format` and ignore it,
    /// and what they will obey is an instruction.
    @Test("The shape can be said in words for a server that takes no schema")
    func theShapeCanBeSaidInWords() {
        let said = ResponseShape.object(named: "Line", fields: [.init("summary", "The line")]).said()

        #expect(said.contains("\"summary\""))
        #expect(said.contains("nothing else"))
    }
}
