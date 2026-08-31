//
//  SourceGroup.swift
//  Flong
//
//  Created by François Rousselet on 31/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB

/// The name the reader gave a publisher.
///
/// **A row exists only where the reader wrote one.** The groups themselves are
/// not stored at all : they fall out of the addresses of the feeds, so there is
/// nothing to create, nothing to keep in step when a subscription arrives or
/// goes, and nothing to leave behind empty. What is stored is the one thing
/// that cannot be worked out, which is that `lemonde.fr` is called `Le Monde`.
///
/// That is also what keeps the record budget of section 7 honest : a reader
/// following three hundred feeds writes a handful of these, not one per group.
nonisolated struct SourceName: Identifiable, Hashable, StoredRecord {
    static let databaseTableName = "source_name"

    enum CodingKeys: String, CodingKey {
        case id
        case domain
        case name
        case createdAt = "created_at"
    }

    var id: UUID
    /// The host the group is keyed by, as ``Feed/domain`` computes it.
    var domain: String
    /// What the reader calls it. Never empty : an empty name deletes the row.
    var name: String
    var createdAt: Date

    init(id: UUID = .v7(), domain: String, name: String, createdAt: Date = Date()) {
        self.id = id
        self.domain = domain
        self.name = name
        self.createdAt = createdAt
    }
}

nonisolated extension SourceName {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let domain = Column(CodingKeys.domain)
        static let name = Column(CodingKeys.name)
    }
}

/// The sources of one publisher, as the sources list shows them.
///
/// **The folders are gone and this is what replaced them.** A folder was a
/// tree the reader had to build and then maintain, and nothing in Flong ever
/// let them build one : the only folders that existed came out of somebody
/// else's OPML file, so the feature was a tree the reader inherited and could
/// not tend. Grouping by publisher costs them nothing, is right the moment a
/// subscription lands, and answers the question a list of two hundred feeds
/// actually raises, which is not "where did I file this" but "who is this".
///
/// The group is keyed by the domain and never by the name : a reader who calls
/// `lemonde.fr` something else has renamed a row of their list, not moved their
/// feeds anywhere.
nonisolated struct SourceGroup: Identifiable, Hashable, Sendable {
    /// The host every feed in the group shares.
    let domain: String
    /// The name the reader gave it, when they gave it one.
    let name: String?
    /// The feeds it holds, in the order a list shows them.
    let feeds: [Feed]

    var id: String { domain }

    /// What the list writes at the head of the group : the reader's name for
    /// it, or the address itself, which is a name everybody already knows.
    var title: String { name ?? domain }

    /// Whether the reader has singled out any of its sources.
    var hasFavourite: Bool { feeds.contains(where: \.isFavourite) }

    /// The order a reader expects their publishers in, which is their own
    /// locale's order over the names they are shown, not over the hosts.
    static func before(_ first: SourceGroup, _ second: SourceGroup) -> Bool {
        first.title.localizedStandardCompare(second.title) == .orderedAscending
    }
}
