//
//  ModelTask.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The four things a model is ever asked to do here.
///
/// **A case rather than four settings written out.** Each of them is a name, an
/// identifier and a place in a picker, and facts about one thing written at
/// four call sites are four places to forget one.
///
/// They are separate because a reader may reasonably want them answered by
/// different models : the sentence they type in the search field wants an
/// answer while their finger is still on the key, and the headlines over a
/// night's stories do not.
nonisolated enum ModelTask: String, Hashable, Sendable, CaseIterable {
    /// What a story is called and what it says in one line.
    ///
    /// The heaviest of the four : up to four turns, and one conversation per
    /// story.
    case headlines

    /// Which of the reader's own subjects a story falls under.
    case subjects

    /// The two or three points over one edition. One turn for a whole page.
    case editions

    /// What a sentence typed into the search field is asking for.
    case search

    var title: LocalizedStringResource {
        switch self {
        case .headlines: "Headlines"
        case .subjects: "Subjects"
        case .editions: "Editions"
        case .search: "Search"
        }
    }

    /// Whether somebody is waiting for it with their finger still on the key.
    ///
    /// Only the search field. What it decides is how long an answer is worth
    /// waiting for : a night's work can wait a minute for a service, and a
    /// reader looking at a cursor cannot.
    var isAwaited: Bool { self == .search }
}
