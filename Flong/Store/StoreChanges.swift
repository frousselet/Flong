//
//  StoreChanges.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import OSLog

/// A tick whenever anything the interface shows has been written to.
///
/// **The window used to be told by whoever wrote.** Every list was loaded by an
/// explicit call after an action the window itself had taken, which works
/// perfectly for the actions the window takes and not at all for the ones it
/// does not : a background refresh, a change arriving from another device
/// through `CKSyncEngine`, an archive read in, a job finishing. All of those
/// wrote to the store and nothing told the reader, so a window left open showed
/// this morning's page until it was pulled down or left and come back to.
///
/// This is the reason GRDB is here at all. `CLAUDE.md` says the package earns
/// its place by replacing the connection pool, the migrator, the typed row
/// decoding **and the change observation the store would otherwise have to
/// own**, and the observation was the one of the four never used.
///
/// **A region rather than a value.** `ValueObservation` would fetch and compare
/// on every write ; what is wanted here is only the news that something moved,
/// after which the window reloads what it happens to be showing.
nonisolated enum StoreChanges {
    /// The tables the interface is drawn from.
    ///
    /// Not every table. `sync_state` and `archive_ingest` are the machinery
    /// writing down where it got to, and a window that reloaded itself every
    /// time a change token moved would reload itself constantly and show
    /// exactly the same thing.
    static let watched = [
        "entry", "entry_body", "feed",
        "story", "story_member", "story_topic",
        "edition", "edition_story",
        "topic", "topic_preference",
        "tag", "tag_binding", "saved_query",
    ]

    /// How long a burst is allowed to settle before the window is reloaded.
    ///
    /// A refresh of three hundred feeds is three hundred transactions and the
    /// window needs one reload, not three hundred. The stream keeps only the
    /// most recent tick, so everything that arrives during the wait and during
    /// the reload collapses into the single tick that follows.
    static let settling = Duration.milliseconds(400)

    /// Ticks while anything the interface is drawn from is written to.
    static func ticks(in database: AppDatabase) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observation = DatabaseRegionObservation(tracking: watched.map { Table($0) })
            let cancellable = observation.start(in: database.writer) { error in
                Log.store.error("The store could not be followed : \(error, privacy: .public)")
                continuation.finish()
            } onChange: { _ in
                continuation.yield()
            }

            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
