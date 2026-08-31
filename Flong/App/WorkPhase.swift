//
//  WorkPhase.swift
//  Flong
//
//  Created by François Rousselet on 31/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// What the machinery is doing, in words a reader can read.
///
/// **One vocabulary for the whole application.** The front page and the sources
/// list say the same thing about the same work, and two descriptions of one
/// pass are two descriptions that stop agreeing. It is also the only thing in
/// the model that names a phase at all : there was `isRefreshing`, `isWorking`
/// and a CloudKit status, none of which says which of eight things is
/// happening, so a pass that fetched three hundred feeds, wrote sixty headlines
/// and exchanged with iCloud was, to the interface, a boolean.
///
/// The counts are carried where there is a real one to carry. Four of these are
/// resumable jobs that already work out how much is left after every batch, and
/// threw the number away.
nonisolated enum WorkPhase: Hashable, Sendable {
    /// Feeds asked, of feeds to ask.
    case fetching(done: Int, total: Int)
    /// Turning what arrived into stories, which is one query and rarely seen.
    case grouping
    /// The model writing the headlines.
    case writing(done: Int, total: Int)
    /// The model filing the stories under subjects.
    case filing(done: Int, total: Int)
    /// Computing the vectors of what the reader kept.
    case indexing(done: Int, total: Int)
    case synchronizing
    /// Reading and writing the shared archives.
    case exchanging
    /// The purge and the search index.
    case tidying

    /// The count, where there is one worth showing.
    ///
    /// A total of nought is a job that has not said yet, not a job with nothing
    /// to do : the bar is drawn as indeterminate rather than as full.
    var count: (done: Int, total: Int)? {
        switch self {
        case .fetching(let done, let total), .writing(let done, let total),
            .filing(let done, let total), .indexing(let done, let total):
            total > 0 ? (min(done, total), total) : nil
        case .grouping, .synchronizing, .exchanging, .tidying:
            nil
        }
    }

    /// What the reader is told, which is what is being brought in rather than
    /// which function is running.
    var title: LocalizedStringResource {
        switch self {
        case .fetching: "Fetching the feeds"
        case .grouping: "Grouping what arrived"
        case .writing: "Writing the headlines"
        case .filing: "Filing the subjects"
        case .indexing: "Indexing what you kept"
        case .synchronizing: "Synchronizing with iCloud"
        case .exchanging: "Exchanging with your other devices"
        case .tidying: "Tidying up"
        }
    }

    /// Whether two phases are the same kind of work, whatever their counts.
    ///
    /// What tells a batch moving on from a different phase taking the line.
    func isSameKind(as other: WorkPhase) -> Bool {
        switch (self, other) {
        case (.fetching, .fetching), (.grouping, .grouping), (.writing, .writing),
            (.filing, .filing), (.indexing, .indexing), (.synchronizing, .synchronizing),
            (.exchanging, .exchanging), (.tidying, .tidying):
            true
        default:
            false
        }
    }

    /// The same phase, with its count moved on.
    ///
    /// The total is never allowed to shrink. A resumable job works its total
    /// out afresh after every batch as what it has done plus what is left, so
    /// articles arriving mid-pass raise it : taken at face value the bar runs
    /// backwards, which reads as the application undoing itself.
    func advanced(done: Int, total: Int) -> WorkPhase {
        let total = max(total, count?.total ?? 0)

        switch self {
        case .fetching: return .fetching(done: done, total: total)
        case .writing: return .writing(done: done, total: total)
        case .filing: return .filing(done: done, total: total)
        case .indexing: return .indexing(done: done, total: total)
        case .grouping, .synchronizing, .exchanging, .tidying: return self
        }
    }
}
