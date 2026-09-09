//
//  GeneratedAnswer.swift
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

nonisolated extension Answer {
    /// What the framework answered, read into the tree every caller reads.
    ///
    /// The two trees are the same tree with different names, so this is a
    /// rename and nothing more. It is written out rather than bridged through
    /// `GeneratedContent(json:)` so that a malformed answer fails as an
    /// ``AnswerFault`` here rather than as a framework error that would then
    /// have to be told apart from a model that is genuinely unusable.
    init(_ content: GeneratedContent) {
        switch content.kind {
        case .null:
            self = .nothing
        case .bool(let flag):
            self = .flag(flag)
        case .number(let value):
            self = .number(value)
        case .string(let text):
            self = .word(text)
        case .array(let items):
            self = .list(items.map(Answer.init))
        case .structure(let properties, _):
            self = .fields(properties.mapValues(Answer.init))
        @unknown default:
            self = .nothing
        }
    }
}
