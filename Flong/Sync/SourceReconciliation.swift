//
//  SourceReconciliation.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Which of the sources on this device the reader's iCloud no longer holds.
///
/// **The rule, on its own, where a test can reach it.** Reading the zone needs
/// an account, a container and a network, and ``CloudSync`` is the one file of
/// the project none of those can be assumed for. What can be wrong here is not
/// the reading : it is the answer given about a source the server has never
/// heard of, and getting that wrong deletes a subscription the reader made a
/// minute ago along with everything under it.
nonisolated enum SourceReconciliation {
    /// The sources another device stopped following, out of the ones here.
    ///
    /// **Absent is not enough ; it has to have been there.** A source followed
    /// on this device a moment ago is absent from the zone because it is still
    /// on its way up, and one followed while the device was offline may never
    /// have been sent at all. Only a record the server has already confirmed it
    /// held can be said to have gone, and `confirmed` is exactly that ledger.
    ///
    /// - Parameters:
    ///   - feeds: every source this device follows.
    ///   - confirmed: the names of the records the server has acknowledged.
    ///   - held: the names of the records standing in the zone right now.
    static func stranded(feeds: [Feed], confirmed: Set<String>, held: Set<String>) -> [Feed] {
        feeds
            .filter { feed in
                let name = SyncRecords.name(forFeed: feed.url)
                return confirmed.contains(name) && !held.contains(name)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
