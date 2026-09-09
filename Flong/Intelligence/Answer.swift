//
//  Answer.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// What came back, in a shape that does not know which model wrote it.
///
/// The system model answers in `GeneratedContent` and a service answers in
/// JSON, and the two are the same tree with different names. Reading them into
/// one here is what lets a call site be written once : everything above this
/// line asks a question and reads fields out of an answer, and nothing above it
/// knows whose answer it was.
nonisolated indirect enum Answer: Hashable, Sendable {
    case nothing
    case word(String)
    case number(Double)
    case flag(Bool)
    case list([Answer])
    case fields([String: Answer])
}

/// Why an answer could not be read.
///
/// **No string from the wire ever reaches this.** A provider is free to echo
/// the prompt, and several do, into the body of their own errors ; an error
/// type that carried one would carry an article, and eventually a key, into a
/// log line. What it carries is the name of the field that was missing, which
/// is ours and not theirs.
nonisolated enum AnswerFault: Error, Hashable, Sendable {
    case missing(String)
    case wrongKind(String)
    case notReadable
}

nonisolated extension Answer {
    /// One field, read as text.
    func string(_ name: String) throws(AnswerFault) -> String {
        guard case .fields(let fields) = self else { throw .wrongKind(name) }
        guard let found = fields[name] else { throw .missing(name) }
        guard case .word(let text) = found else { throw .wrongKind(name) }
        return text
    }

    /// One field, read as text, where the model leaving it out is an answer.
    func optionalString(_ name: String) -> String? {
        guard case .fields(let fields) = self, case .word(let text)? = fields[name] else { return nil }
        return text
    }

    /// One field, read as a list of text.
    ///
    /// A list of one comes back as the thing itself from more than one service,
    /// so a lone word is read as a list holding it rather than refused.
    func strings(_ name: String) throws(AnswerFault) -> [String] {
        guard case .fields(let fields) = self else { throw .wrongKind(name) }
        guard let found = fields[name] else { throw .missing(name) }

        switch found {
        case .list(let items):
            return items.compactMap { if case .word(let text) = $0 { text } else { nil } }
        case .word(let text):
            return [text]
        default:
            throw .wrongKind(name)
        }
    }
}

/// Something the model can be asked for, and the shape of asking for it.
///
/// **Two halves of one declaration, and the drift between them is the risk.**
/// A `@Generable` type said the shape and the reading at once ; splitting them
/// means a renamed field can be right on one side and wrong on the other. The
/// names are therefore constants declared once per type and used by both
/// halves, and every conforming type carries a round trip test that builds a
/// specimen from its own shape and reads it back.
nonisolated protocol ModelAnswer: Sendable {
    /// What the model is asked to fill in.
    ///
    /// **The name of a shape is part of the prompt, and it was measured.** The
    /// framework puts the schema in front of the model along with the question,
    /// so what a shape is called is text the model reads. Renaming
    /// `GeneratedBrief` to `Brief` while moving these off the macro looked like
    /// tidying and changed the answers : against the live suite, headlines came
    /// back too long often enough to lose one story of three on a page of two.
    /// Every shape here is named what its type was named, and a shape is
    /// renamed only on purpose and only against that suite.
    static var shape: ResponseShape { get }
    init(_ answer: Answer) throws(AnswerFault)
}
