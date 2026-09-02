//
//  PoolStore.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import OSLog

/// A source enough people follow to be worth offering.
nonisolated struct PopularFeed: Hashable, Sendable, Identifiable {
    var url: URL
    var title: String
    var siteURL: URL?
    /// How many contributors follow it, counted by person and never by record.
    var subscribers: Int
    /// Whether somebody on the roster follows it, which is the other way in.
    var isEndorsed: Bool

    var id: URL { url }

    /// The publisher it belongs to, which is what a row shows under the name.
    var domain: String {
        FeedURL.publisher(site: siteURL, feed: url) ?? url.absoluteString
    }
}

/// The common pool, as this device holds its copy of it.
///
/// **Counted here rather than asked for.** CloudKit answers questions about
/// records and has no notion of an aggregate : there is no query that returns
/// *the addresses at least ten people follow*, and there could not be one
/// without a server keeping a tally, which section 1 says there is not. So the
/// lists are pulled as they change, folded into two tables, and the counting is
/// a `GROUP BY` on a device that already holds a hundred thousand articles and
/// will not notice.
///
/// **A person is counted once.** The count is `COUNT(DISTINCT creator)`, and a
/// creator is an iCloud identity rather than a record : a reader with a phone
/// and an iPad is one reader, and a list long enough to need three records is
/// one offer. It is also why a chunk carries its creator on the row rather than
/// being keyed by it.
nonisolated struct PoolStore: Sendable {
    /// How many people it takes for a source to be worth offering.
    ///
    /// Ten, which is the number the pool was specified with. Low enough that a
    /// small pool says something and high enough that a handful of accounts
    /// made in an afternoon do not : the counting is by iCloud identity, so
    /// ten is ten Apple accounts rather than ten taps.
    static let threshold = 10

    /// How many contributors this device keeps a copy of.
    ///
    /// The pool grows with the number of readers and this database does not
    /// have to grow with it. Past the cap the least recently changed lists are
    /// dropped, which is the right ones to drop : a list nobody has touched in
    /// a year belongs to somebody who has stopped reading.
    static let contributorLimit = 2_000

    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    // MARK: - What goes out

    /// What this reader offers, which is not the same as what they follow.
    ///
    /// Every source is put through ``PooledFeed/offered(_:secret:hasCredential:)``,
    /// which is where the six reasons to hold one back live. The keychain is
    /// read by the caller and handed in : this store has no business opening
    /// it, and a test has no way to fill it.
    func offering(secrets: [UUID: SecretParameters], credentialed: Set<UUID>) async throws -> [PooledFeed] {
        try await database.writer.read { db in
            try Feed.fetchAll(db).compactMap { feed in
                PooledFeed.offered(feed, secret: secrets[feed.id], hasCredential: credentialed.contains(feed.id))
            }
        }
    }

    // MARK: - What arrives

    /// Folds the lists a pass fetched into the two tables.
    ///
    /// A record is replaced whole rather than merged : its writer rewrites it
    /// entire every time they change what they offer, so what arrives is the
    /// current state of one person's offer and the previous one has nothing
    /// left to say.
    func absorb(_ lists: [PoolList.Received]) async throws {
        guard !lists.isEmpty else { return }

        try await database.writer.write { db in
            for list in lists {
                try db.execute(
                    sql: """
                        INSERT INTO pool_list (record_name, creator, modified_at) VALUES (?, ?, ?)
                        ON CONFLICT(record_name) DO UPDATE SET creator = excluded.creator,
                            modified_at = excluded.modified_at
                        """,
                    arguments: [list.recordName, list.creator, list.modifiedAt]
                )
                try db.execute(
                    sql: "DELETE FROM pool_entry WHERE record_name = ?",
                    arguments: [list.recordName]
                )
                for feed in list.feeds {
                    try db.execute(
                        sql: """
                            INSERT OR IGNORE INTO pool_entry (record_name, url, title, site_url)
                            VALUES (?, ?, ?, ?)
                            """,
                        arguments: [list.recordName, feed.url, feed.title, feed.siteURL]
                    )
                }
            }
        }
    }

    /// Takes out the records a pass was told had been deleted.
    func forget(recordNames: [String]) async throws {
        guard !recordNames.isEmpty else { return }
        try await database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM pool_list WHERE record_name IN (\(databaseQuestionMarks(count: recordNames.count)))",
                arguments: StatementArguments(recordNames)
            )
        }
    }

    /// Writes the roster down, replacing whatever it held.
    ///
    /// Whole rather than merged, because a person taken off a roster has to
    /// stop counting on the next pass and a merge would keep them for ever.
    func setTrusted(_ creators: Set<String>) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM pool_trust")
            for creator in creators {
                try db.execute(sql: "INSERT OR IGNORE INTO pool_trust (creator) VALUES (?)", arguments: [creator])
            }
        }
    }

    /// Who the roster names, as this device last read it.
    func trusted() async throws -> Set<String> {
        try await database.writer.read { db in
            Set(try String.fetchAll(db, sql: "SELECT creator FROM pool_trust"))
        }
    }

    /// Drops the oldest lists once the pool held here is larger than the cap.
    func prune(to limit: Int = PoolStore.contributorLimit) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    DELETE FROM pool_list WHERE creator IN (
                        SELECT creator FROM pool_list GROUP BY creator
                        ORDER BY MAX(modified_at) DESC LIMIT -1 OFFSET ?
                    )
                    """,
                arguments: [limit]
            )
        }
    }

    /// Everything this device holds of the pool, for the command that erases.
    func forgetEverything() async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM pool_list")
            try db.execute(sql: "DELETE FROM pool_trust")
        }
    }

    // MARK: - What it adds up to

    /// The sources worth offering, best first, minus what the reader follows.
    ///
    /// **What the reader already follows is not a suggestion**, so it is taken
    /// out in the query rather than after it : filtering afterwards would spend
    /// the limit on rows nobody is going to see, and a reader who follows the
    /// forty most popular sources in the pool would be shown an empty page with
    /// forty things behind it.
    ///
    /// A name is what most of the pool calls the source rather than what the
    /// first contributor called it, which is one line of a second query and is
    /// what stops a single bad actor from titling somebody else's feed.
    func popular(limit: Int = 200, threshold: Int = PoolStore.threshold) async throws -> [PopularFeed] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT e.url AS url,
                           COUNT(DISTINCT l.creator) AS subscribers,
                           MAX(t.creator IS NOT NULL) AS endorsed
                    FROM pool_entry e
                    JOIN pool_list l ON l.record_name = e.record_name
                    LEFT JOIN pool_trust t ON t.creator = l.creator
                    WHERE NOT EXISTS (SELECT 1 FROM feed f WHERE f.url = e.url)
                    GROUP BY e.url
                    HAVING endorsed = 1 OR subscribers >= ?
                    ORDER BY endorsed DESC, subscribers DESC, url ASC
                    LIMIT ?
                    """,
                arguments: [threshold, limit]
            )

            let urls = rows.compactMap { $0["url"] as String? }
            guard !urls.isEmpty else { return [] }

            let names = try Self.names(of: urls, in: db)

            return rows.compactMap { row in
                guard let address: String = row["url"], let url = URL(string: address) else { return nil }
                let named = names[address]
                return PopularFeed(
                    url: url,
                    title: named?.title ?? Subscription.fallbackTitle(for: url),
                    siteURL: named?.siteURL.flatMap(URL.init(string:)),
                    subscribers: row["subscribers"] ?? 0,
                    isEndorsed: row["endorsed"] ?? false
                )
            }
        }
    }

    /// How many people this device has heard from, which is what the page says
    /// when it has nothing to offer yet.
    func contributors() async throws -> Int {
        try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT creator) FROM pool_list") ?? 0
        }
    }

    /// What the pool mostly calls each of these addresses.
    private static func names(of urls: [String], in db: Database) throws -> [String: PooledFeed] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT url, title, site_url, COUNT(*) AS said
                FROM pool_entry
                WHERE url IN (\(databaseQuestionMarks(count: urls.count)))
                GROUP BY url, title, site_url
                ORDER BY said DESC, title ASC
                """,
            arguments: StatementArguments(urls)
        )

        var names: [String: PooledFeed] = [:]
        for row in rows {
            guard let url = row["url"] as String?, names[url] == nil else { continue }
            names[url] = PooledFeed(url: url, title: row["title"] ?? "", siteURL: row["site_url"])
        }
        return names
    }
}
