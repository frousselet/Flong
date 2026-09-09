//
//  ResponseShape.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The shape an answer has to have, said once and rendered wherever it is asked.
///
/// **A value rather than a type, and ``TopicNamer`` is why.** Guided generation
/// through `@Generable` writes the shape into the type at compile time, which
/// serves five of the six answers this application asks for and cannot express
/// the sixth : the subjects a story may be filed under are the reader's own
/// list, read out of the store at the moment the question is put. That call
/// site already builds a `DynamicGenerationSchema` by hand and calls
/// `respond(to:schema:options:)`, which is the same door said in the
/// framework's own terms. This promotes that door and closes the other, so
/// there is one way of asking rather than two, and the one way can be rendered
/// for something that is not the framework.
///
/// **Four cases, because four cover every question asked here.** A headline and
/// a line under it, a list of points, a word chosen from a list, a sentence
/// read into five fields. There is no number, no boolean and no nesting past an
/// object holding a list holding a choice. A fifth case is added when a call
/// site needs one, and not before.
nonisolated indirect enum ResponseShape: Hashable, Sendable {
    /// Free text. What to say about it rides on the field that holds it.
    case words

    /// One of a list, and nothing else.
    ///
    /// The list is carried in the value because it is not known until the
    /// question is asked : `Cybersécurité` cannot come back as `Cyber sécurité`
    /// and a subject nobody has cannot come back at all. The name is carried
    /// too, since a model shown its own schema reads the name as part of the
    /// question.
    case oneOf(named: String, choices: [String])

    /// Several of something, bounded at either end where it matters.
    case list(of: ResponseShape, least: Int?, most: Int?)

    /// Fields with names, which is what an answer of more than one part is.
    case object(named: String, fields: [Field])

    /// One named part of an object.
    ///
    /// The description is what the model is told about this field, and it is
    /// the text that used to sit in a `@Guide`. It moves here word for word :
    /// nothing the model is told changes.
    nonisolated struct Field: Hashable, Sendable {
        let name: String
        let description: String?
        let shape: ResponseShape
        let isOptional: Bool

        init(_ name: String, _ description: String? = nil, _ shape: ResponseShape = .words, isOptional: Bool = false) {
            self.name = name
            self.description = description
            self.shape = shape
            self.isOptional = isOptional
        }
    }

    /// Several of something, with no bound at either end.
    static func list(of shape: ResponseShape) -> ResponseShape { .list(of: shape, least: nil, most: nil) }

    /// Several of something, with a ceiling and no floor.
    static func list(of shape: ResponseShape, most: Int) -> ResponseShape { .list(of: shape, least: nil, most: most) }

    /// What this shape is called, where a wire format wants a name for it.
    var name: String {
        switch self {
        case .object(let name, _): name
        case .oneOf(let name, _): name
        case .list(let item, _, _): item.name + "List"
        case .words: "Words"
        }
    }
}
