//
//  ResponseShapeTests.swift
//  FlongTests
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import FoundationModels
import Testing

@testable import Flong

/// The shape of an answer, and the reading of one.
///
/// **A `@Generable` type said the shape and the reading at once, and this says
/// them separately.** That is the whole risk of the change : a field renamed on
/// one side and not the other compiles, ships, and comes back as an answer that
/// decodes to nothing. So every shape is built into a specimen answer and read
/// back through its own type, which is the one test that catches it.
@Suite("The shape an answer has to have")
struct ResponseShapeTests {
    /// An answer of the right shape, with nothing in it worth reading.
    ///
    /// Built from the shape itself rather than written out by hand : a specimen
    /// written by hand is a third place to spell a field name, and the point is
    /// to have two.
    static func specimen(of shape: ResponseShape) -> Answer {
        switch shape {
        case .words:
            .word("something")
        case .oneOf(_, let choices):
            .word(choices.first ?? "")
        case .list(let item, let least, _):
            .list(Array(repeating: specimen(of: item), count: max(least ?? 1, 1)))
        case .object(_, let fields):
            .fields(fields.reduce(into: [:]) { $0[$1.name] = specimen(of: $1.shape) })
        }
    }

    @Test("Every answer reads back out of its own shape")
    func everyAnswerReadsItsOwnShape() throws {
        // Named one by one rather than gathered behind an existential : what is
        // being checked is that these six types agree with themselves, and a
        // list of them is what a seventh has to be added to.
        #expect(throws: Never.self) { try GeneratedBrief(Self.specimen(of: GeneratedBrief.shape)) }
        #expect(throws: Never.self) { try CarriedAcross(Self.specimen(of: CarriedAcross.shape)) }
        #expect(throws: Never.self) { try GeneratedHeadline(Self.specimen(of: GeneratedHeadline.shape)) }
        #expect(throws: Never.self) { try GeneratedLine(Self.specimen(of: GeneratedLine.shape)) }
        #expect(throws: Never.self) { try GeneratedEditionPoints(Self.specimen(of: GeneratedEditionPoints.shape)) }
        #expect(throws: Never.self) { try ReadQuestion(Self.specimen(of: ReadQuestion.shape)) }
    }

    @Test("A brief keeps the two fields it was given")
    func aBriefKeepsWhatItWasGiven() throws {
        let brief = try GeneratedBrief(
            .fields([
                "title": .word("L'Argentine restitue un tableau volé"),
                "summary": .word("Le tableau retourne à la famille de son propriétaire."),
            ])
        )

        #expect(brief.title == "L'Argentine restitue un tableau volé")
        #expect(brief.summary == "Le tableau retourne à la famille de son propriétaire.")
    }

    @Test("A missing field is named rather than guessed at")
    func aMissingFieldIsNamed() {
        #expect(throws: AnswerFault.missing("summary")) {
            try GeneratedBrief(.fields(["title": .word("Un titre")]))
        }
    }

    /// A list of one comes back as the thing itself from more than one service,
    /// and reading that as nothing would throw away the only point an edition
    /// had.
    @Test("A lone word where a list was asked for is a list of one")
    func aLoneWordIsAListOfOne() throws {
        let points = try GeneratedEditionPoints(.fields(["points": .word("Une seule chose")]))
        #expect(points.points == ["Une seule chose"])
    }

    /// The reader's own subjects are the answer's choices, so a subject nobody
    /// has cannot come back at all.
    @Test("The subjects a story may be filed under are the reader's own")
    func filingIsBoundedByTheVocabulary() throws {
        let shape = TopicNamer.shape(for: ["Politique", "Économie"])

        guard case .object(let name, let fields) = shape, let subjects = fields.first else {
            Issue.record("The filing shape is an object with one field")
            return
        }
        #expect(name == "Filing")
        #expect(subjects.name == "subjects")

        guard case .list(let item, let least, let most) = subjects.shape else {
            Issue.record("The subjects are a list")
            return
        }
        #expect(least == 1)
        #expect(most == TopicNamer.subjectsPerStory)
        #expect(item == .oneOf(named: "Subject", choices: ["Politique", "Économie"]))

        // And it builds, which is what the model is actually handed.
        #expect(throws: Never.self) { try shape.schema() }
    }

    @Test("Every shape builds into a schema the framework accepts")
    func everyShapeBuilds() throws {
        for shape in [
            GeneratedBrief.shape, CarriedAcross.shape, GeneratedHeadline.shape,
            GeneratedLine.shape, GeneratedEditionPoints.shape, ReadQuestion.shape,
        ] {
            #expect(throws: Never.self) { try shape.schema() }
        }
    }

    /// The framework answers in one tree and a service in another, and this is
    /// the rename between them.
    @Test("What the framework answered is read into the tree every caller reads")
    func theFrameworkAnswerIsRenamed() {
        let content = GeneratedContent(
            kind: .structure(
                properties: [
                    "title": GeneratedContent(kind: .string("Un titre")),
                    "points": GeneratedContent(kind: .array([GeneratedContent(kind: .string("Un point"))])),
                ],
                orderedKeys: ["title", "points"]
            )
        )

        #expect(Answer(content) == .fields(["title": .word("Un titre"), "points": .list([.word("Un point")])]))
    }
}

/// What the framework's own failures are taken to mean.
///
/// The line between a model that will not write about one story and a model
/// that cannot be used is what stops three awkward headlines silencing the
/// model for a whole run. It was three copies of one switch ; it is one now,
/// and this is what holds it.
@Suite("Reading what the model said went wrong")
struct ModelFaultTests {
    @Test("A story the model will not write about is about the story")
    func aRefusalIsAboutTheStory() {
        for error: LanguageModelSession.GenerationError in [
            .guardrailViolation(.init(debugDescription: "")),
            .unsupportedGuide(.init(debugDescription: "")),
            .decodingFailure(.init(debugDescription: "")),
            .exceededContextWindowSize(.init(debugDescription: "")),
        ] {
            #expect(!LocalProvider.fault(of: error).isTheModelItself)
        }
    }

    @Test("A model that is busy is the model, and is never given up on")
    func busyIsTheModelAndIsForgiven() {
        for error: LanguageModelSession.GenerationError in [
            .rateLimited(.init(debugDescription: "")),
            .concurrentRequests(.init(debugDescription: "")),
        ] {
            let fault = LocalProvider.fault(of: error)
            #expect(fault.isTheModelItself)
            #expect(fault.isBusy)
        }
    }

    @Test("Assets that are not there are the model itself")
    func missingAssetsAreTheModel() {
        let fault = LocalProvider.fault(
            of: LanguageModelSession.GenerationError.assetsUnavailable(
                .init(debugDescription: "")))

        #expect(fault == .unusable(.absent))
        #expect(fault.isTheModelItself)
        #expect(!fault.isBusy)
    }

    /// The reader leaving is not a failure of anything and must never count
    /// against a model.
    @Test("A cancelled ask counts against nothing")
    func cancellationCountsAgainstNothing() {
        #expect(LocalProvider.fault(of: CancellationError()).isBusy)
    }

    @Test("The three answers are drawn from the fault in one place")
    func theThreeAnswersAreDrawnOnce() {
        #expect(Answered<String>(failing: .declined).written == nil)
        #expect(Answered<String>(failing: .unreadable).written == nil)

        if case .unusable = Answered<String>(failing: .busy(retryAfter: nil)) {
        } else {
            Issue.record("A busy model is the model and not the story")
        }
        if case .declined = Answered<String>(failing: .tooLong) {
        } else {
            Issue.record("Something too long is the thing and not the model")
        }
    }
}
