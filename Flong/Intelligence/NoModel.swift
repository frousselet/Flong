//
//  NoModel.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Nobody, which is a thing a reader may choose.
///
/// **It is not the same as having no model available.** A device with no Apple
/// Intelligence is a device that cannot ; a reader who switched a task off has
/// decided that they would rather have the article's own headline than a
/// written one. The page says so differently, which is the whole reason this
/// exists rather than an absent provider standing in for it.
nonisolated struct NoModel: ModelProvider {
    let name = "None"
    let identity = "none"
    let host: String? = nil
    let isAvailable = false
    let batch = 1
    let triesASecondVoice = false

    var absence: LocalizedStringResource? { "You have switched this off." }

    func writes(_ locale: Locale) -> Bool { false }

    func conversation(saying instructions: String) -> any ModelConversation {
        NoConversation()
    }
}

/// An exchange with nobody, which never happens : every caller asks whether the
/// model is available first, and this one never is.
nonisolated final class NoConversation: ModelConversation {
    func hasRoom(for question: String, keeping budget: Int) async -> Bool { false }

    func answer(to question: String, shaped: ResponseShape, keeping budget: Int) async throws(ModelFault) -> Answer {
        throw .unusable(.absent)
    }
}
