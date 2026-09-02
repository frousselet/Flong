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

/// One address the author withholds.
///
/// The digest is what travels and what every device matches against ; the
/// address is present only on the device that decided it, which is the only
/// one that has anything to show its reader.
nonisolated struct PoolBlock: Hashable, Sendable, Identifiable {
    var digest: String
    var url: String?

    var id: String { digest }
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

    /// Where the sponsorship graph is walked from.
    ///
    /// Handed in rather than read off ``PoolTrust/root`` at the point of use,
    /// for the reason ``CloudSync`` takes its container the same way : the one
    /// value that decides everything here is the one a test has to be able to
    /// state. It defaults to the anchor, so nothing outside a test says it.
    private let root: String?

    init(_ database: AppDatabase, root: String? = PoolTrust.root) {
        self.database = database
        self.root = root
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
            let authorised = try Set(String.fetchAll(db, sql: "SELECT creator FROM pool_authorised"))

            for list in lists {
                // A stranger's list is not stored and not counted. The pool is
                // closed : see ``PoolTrust``.
                guard authorised.contains(list.creator) else { continue }

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
                            INSERT OR IGNORE INTO pool_entry (record_name, url, title, site_url, digest)
                            VALUES (?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            list.recordName, feed.url, feed.title, feed.siteURL,
                            PoolAuthority.digest(of: feed.url),
                        ]
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

    /// Writes down what the author decided, and works the graph out again.
    ///
    /// Whole rather than merged, because a decision taken back has to stop
    /// applying on the next pass and a merge would keep it for ever.
    ///
    /// **The address a block names is not stored here.** What arrives is a
    /// digest, which is all that travels : see ``PoolAuthority/digest(of:)``.
    /// The plain address is written only on the device that decided it, by
    /// ``block(_:)``, so the author can read back their own list.
    ///
    /// Returns whether anybody new became authorised, which is the one change
    /// that means this device has to go and fetch lists it declined before.
    @discardableResult
    func setAuthority(_ authority: PoolAuthority) async throws -> Bool {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM pool_trust")
            for creator in authority.trusted {
                try db.execute(sql: "INSERT OR IGNORE INTO pool_trust (creator) VALUES (?)", arguments: [creator])
            }

            try db.execute(sql: "DELETE FROM pool_ban")
            for creator in authority.banned {
                try db.execute(sql: "INSERT OR IGNORE INTO pool_ban (creator) VALUES (?)", arguments: [creator])
            }

            // A digest that is already here keeps the address beside it, which
            // only the author's own device ever wrote.
            try db.execute(
                sql:
                    "DELETE FROM pool_block WHERE digest NOT IN (\(databaseQuestionMarks(count: max(authority.blocked.count, 1))))",
                arguments: StatementArguments(authority.blocked.isEmpty ? [""] : Array(authority.blocked))
            )
            for digest in authority.blocked {
                try db.execute(sql: "INSERT OR IGNORE INTO pool_block (digest) VALUES (?)", arguments: [digest])
            }

            return try Self.resolve(in: db, root: self.root)
        }
    }

    /// Folds in who each contributor brought into the pool.
    ///
    /// Returns whether the walk reaches anybody it did not reach before.
    @discardableResult
    func absorb(_ vouches: [PoolVouch.Received]) async throws -> Bool {
        try await database.writer.write { db in
            for vouch in vouches {
                let payload = try JSONEncoder().encode(vouch.sponsored.sorted())
                try db.execute(
                    sql: """
                        INSERT INTO pool_vouch (creator, sponsored, modified_at) VALUES (?, ?, ?)
                        ON CONFLICT(creator) DO UPDATE SET sponsored = excluded.sponsored,
                            modified_at = excluded.modified_at
                        """,
                    arguments: [vouch.creator, String(decoding: payload, as: UTF8.self), vouch.modifiedAt]
                )
            }
            return try Self.resolve(in: db, root: self.root)
        }
    }

    /// Walks the graph out from the root and writes down who it reaches.
    ///
    /// **A list whose writer is no longer reached goes with them**, in the same
    /// breath : a ban that left the rows behind would leave the counting
    /// unchanged until something else happened to remove them.
    @discardableResult
    private static func resolve(in db: Database, root: String?) throws -> Bool {
        var vouches: [String: Set<String>] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT creator, sponsored FROM pool_vouch") {
            guard let creator = row["creator"] as String?, let payload = row["sponsored"] as String?,
                let names = try? JSONDecoder().decode([String].self, from: Data(payload.utf8))
            else { continue }
            vouches[creator] = Set(names)
        }

        let banned = try Set(String.fetchAll(db, sql: "SELECT creator FROM pool_ban"))
        let reached = PoolTrust.authorised(from: root, vouches: vouches, banned: banned)
        let before = try Set(String.fetchAll(db, sql: "SELECT creator FROM pool_authorised"))

        guard reached != before else { return false }

        try db.execute(sql: "DELETE FROM pool_authorised")
        for creator in reached {
            try db.execute(sql: "INSERT OR IGNORE INTO pool_authorised (creator) VALUES (?)", arguments: [creator])
        }
        try db.execute(sql: "DELETE FROM pool_list WHERE creator NOT IN (SELECT creator FROM pool_authorised)")

        return !reached.subtracting(before).isEmpty
    }

    /// Who the author believes on their own, as this device last read it.
    func trusted() async throws -> Set<String> {
        try await database.writer.read { db in
            Set(try String.fetchAll(db, sql: "SELECT creator FROM pool_trust"))
        }
    }

    /// Everybody the sponsorship graph reaches, as this device last walked it.
    func authorised() async throws -> Set<String> {
        try await database.writer.read { db in
            Set(try String.fetchAll(db, sql: "SELECT creator FROM pool_authorised"))
        }
    }

    /// Whether one identity may put anything into the pool.
    func isAuthorised(_ identity: String?) async throws -> Bool {
        guard let identity else { return false }
        return try await database.writer.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS (SELECT 1 FROM pool_authorised WHERE creator = ?)",
                arguments: [identity]
            ) ?? false
        }
    }

    /// Who this reader brought in, as the graph last said.
    func sponsored(by creator: String?) async throws -> Set<String> {
        guard let creator else { return [] }
        return try await database.writer.read { db in
            guard
                let payload = try String.fetchOne(
                    db, sql: "SELECT sponsored FROM pool_vouch WHERE creator = ?", arguments: [creator])
            else { return [] }
            return Set((try? JSONDecoder().decode([String].self, from: Data(payload.utf8))) ?? [])
        }
    }

    /// Who is cut out, and which addresses are withheld, for the one reader who
    /// may say. The addresses come back in the plain where this device is the
    /// one that decided them, and as a digest where it is not.
    func banned() async throws -> Set<String> {
        try await database.writer.read { db in
            Set(try String.fetchAll(db, sql: "SELECT creator FROM pool_ban"))
        }
    }

    func blocked() async throws -> [PoolBlock] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT digest, url FROM pool_block ORDER BY url IS NULL, url")
                .compactMap { row in
                    guard let digest = row["digest"] as String? else { return nil }
                    return PoolBlock(digest: digest, url: row["url"])
                }
        }
    }

    /// Remembers the address behind a digest, on the device that blocked it.
    func remember(_ address: String) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql:
                    "INSERT INTO pool_block (digest, url) VALUES (?, ?) ON CONFLICT(digest) DO UPDATE SET url = excluded.url",
                arguments: [PoolAuthority.digest(of: address), address]
            )
        }
    }

    /// Who offered one address, so that a ban can be aimed at somebody.
    func offerers(of url: URL, limit: Int = 50) async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT l.creator FROM pool_entry e
                    JOIN pool_list l ON l.record_name = e.record_name
                    WHERE e.url = ? ORDER BY l.creator LIMIT ?
                    """,
                arguments: [url.absoluteString, limit]
            )
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
            try db.execute(sql: "DELETE FROM pool_vouch")
            try db.execute(sql: "DELETE FROM pool_authorised")
            try db.execute(sql: "DELETE FROM pool_ban")
            try db.execute(sql: "DELETE FROM pool_block")
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
                    JOIN pool_authorised a ON a.creator = l.creator
                    LEFT JOIN pool_trust t ON t.creator = l.creator
                    WHERE NOT EXISTS (SELECT 1 FROM feed f WHERE f.url = e.url)
                      AND NOT EXISTS (SELECT 1 FROM pool_block b WHERE b.digest = e.digest)
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
