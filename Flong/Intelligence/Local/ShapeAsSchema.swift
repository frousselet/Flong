//
//  ShapeAsSchema.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import FoundationModels

/// A shape, said in the framework's own terms.
///
/// One of the two renderings of ``ResponseShape``, and the one that was already
/// written : ``TopicNamer`` built exactly this by hand for the only answer whose
/// shape is not known until the question is asked. What changes is that every
/// answer goes through it now, so there is one path into the model rather than
/// a guided one and a dynamic one.
nonisolated extension ResponseShape {
    /// The schema the session is handed.
    ///
    /// Every named piece is declared at the root's side as a dependency rather
    /// than nested, which is what the framework wants of anything with a name
    /// of its own.
    func schema() throws -> GenerationSchema {
        try GenerationSchema(root: dynamic(), dependencies: [])
    }

    /// The same shape as the framework's own tree.
    func dynamic() -> DynamicGenerationSchema {
        switch self {
        case .words:
            DynamicGenerationSchema(type: String.self)

        case .oneOf(let name, let choices):
            DynamicGenerationSchema(name: name, anyOf: choices)

        case .list(let item, let least, let most):
            DynamicGenerationSchema(arrayOf: item.dynamic(), minimumElements: least, maximumElements: most)

        case .object(let name, let fields):
            DynamicGenerationSchema(
                name: name,
                properties: fields.map {
                    DynamicGenerationSchema.Property(
                        name: $0.name,
                        description: $0.description,
                        schema: $0.shape.dynamic(),
                        isOptional: $0.isOptional
                    )
                }
            )
        }
    }
}
