//
//  LibraryStore.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import OSLog

/// What a library operation changed, for the indexer to follow.
nonisolated struct LibraryChange: Hashable, Sendable {
    var kept: [LibraryItem] = []
    /// The items themselves, not merely their identifiers : an item that is
    /// gone still has to be named to Spotlight and to CloudKit.
    var released: [LibraryItem] = []

    var isEmpty: Bool { kept.isEmpty && released.isEmpty }
}

/// The library : what the reader chose to keep.
///
/// An article enters it by being starred, annotated, or by a rule saying so, as
/// section 13 of the specification sets out. At that moment its content is
/// frozen and copied, which is what lets it survive the purge of the stream and
/// the disappearance of its source.
///
/// The copy is the point. A library that pointed at the stream would empty
/// itself thirty days later, and one that pointed at the web would empty itself
/// the day a publisher reorganized their site.
nonisolated struct LibraryStore: Sendable {
    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    // MARK: - Reading

    /// The kept articles, newest first, narrowed by a plain search.
    ///
    /// The stream has its own index and its own language ; the library is a few
    /// thousand items, so a plain match over what was kept is enough here, and
    /// section 11 hands the semantic half of it to Spotlight.
    func summaries(matching text: String = "", limit: Int = 500) async throws -> [ArticleSummary] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return try await database.writer.read { db in
            guard !text.isEmpty else {
                return try ArticleSummary.fetchAll(db, sql: "\(Self.columns) ORDER BY date DESC LIMIT \(limit)")
            }

            let pattern =
                "%"
                + text.replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_") + "%"
            return try ArticleSummary.fetchAll(
                db,
                sql: """
                    \(Self.columns)
                    WHERE title LIKE ? ESCAPE '\\' OR COALESCE(plain_text, '') LIKE ? ESCAPE '\\'
                       OR COALESCE(author, '') LIKE ? ESCAPE '\\'
                    ORDER BY date DESC LIMIT \(limit)
                    """,
                arguments: [pattern, pattern, pattern]
            )
        }
    }

    func count() async throws -> Int {
        try await database.writer.read { db in try LibraryItem.fetchCount(db) }
    }

    /// One kept article, as it read on the day it was kept.
    func article(id: UUID) async throws -> Article? {
        try await database.writer.read { db in
            guard let item = try LibraryItem.fetchOne(db, key: id) else { return nil }
            return Self.article(from: item)
        }
    }

    /// The copy of an article, by the identity the wire uses for it.
    func item(guid: String, feedURL: URL?) async throws -> LibraryItem? {
        try await database.writer.read { db in
            try LibraryItem
                .filter(LibraryItem.Columns.guid == guid && LibraryItem.Columns.feedURL == feedURL)
                .fetchOne(db)
        }
    }

    func item(id: UUID) async throws -> LibraryItem? {
        try await database.writer.read { db in try LibraryItem.fetchOne(db, key: id) }
    }

    /// Every kept article, for the indexer to hand to Spotlight.
    func allItems() async throws -> [LibraryItem] {
        try await database.writer.read { db in try LibraryItem.fetchAll(db) }
    }

    // MARK: - Collections

    /// Every square the collections page shows, in the order it shows them.
    ///
    /// Favourites first, being the one the reader made deliberately, then
    /// notes, then the months newest first. One statement per group rather than
    /// one clever one : three small queries over a few thousand rows read
    /// plainly, and the page asks for them once when it appears.
    ///
    /// Each square wears the picture of the newest article in it that has one,
    /// which is what makes a square look like the things inside it. The
    /// subquery is correlated on the group and skips the articles with no
    /// picture : taking the newest row's image outright would leave a square
    /// blank whenever that one article happened to have none.
    func collections() async throws -> [LibraryCollection] {
        let counted: [Counted] = try await database.writer.read { db in
            var found: [Counted] = []

            let deliberate = [
                ("starred", Self.isStarred, "i.starred_at IS NOT NULL"),
                ("annotated", Self.hasNote, "COALESCE(i.annotation, '') <> ''"),
            ]
            for (group, condition, ofTheCover) in deliberate {
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) AS count,
                               (SELECT i.image_url FROM library_item i
                                WHERE \(ofTheCover) AND i.image_url IS NOT NULL
                                ORDER BY COALESCE(i.published_at, i.promoted_at) DESC LIMIT 1) AS cover
                        FROM library_item WHERE \(condition)
                        """
                )
                if let row, row["count"] as Int > 0 {
                    found.append(Counted(group: group, name: group, count: row["count"], cover: row["cover"]))
                }
            }

            let months = try Row.fetchAll(
                db,
                sql: """
                    SELECT strftime('%Y-%m', l.promoted_at, 'localtime') AS name, COUNT(*) AS count,
                           (SELECT i.image_url FROM library_item i
                            WHERE strftime('%Y-%m', i.promoted_at, 'localtime')
                                  = strftime('%Y-%m', l.promoted_at, 'localtime')
                              AND i.image_url IS NOT NULL
                            ORDER BY COALESCE(i.published_at, i.promoted_at) DESC LIMIT 1) AS cover
                    FROM library_item l
                    GROUP BY name
                    ORDER BY name DESC
                    """
            )
            found += months.compactMap { row in
                (row["name"] as String?).map {
                    Counted(group: "month", name: $0, count: row["count"], cover: row["cover"])
                }
            }
            return found
        }

        return counted.compactMap(Self.collection(from:))
    }

    /// What is in one square, newest first.
    func summaries(in collection: LibraryCollection.Kind, limit: Int = 500) async throws -> [ArticleSummary] {
        let (condition, arguments) = Self.condition(for: collection)

        return try await database.writer.read { db in
            try ArticleSummary.fetchAll(
                db,
                sql: "\(Self.columns) WHERE \(condition) ORDER BY date DESC LIMIT \(limit)",
                arguments: arguments
            )
        }
    }

    /// A row that has crossed out of the database, which a `Row` may not.
    private struct Counted: Sendable {
        var group: String
        var name: String
        var count: Int
        var cover: URL?
    }

    private static let isStarred = "library_item.starred_at IS NOT NULL"
    private static let hasNote = "COALESCE(library_item.annotation, '') <> ''"

    private static func collection(from counted: Counted) -> LibraryCollection? {
        let kind: LibraryCollection.Kind
        switch counted.group {
        case "starred": kind = .starred
        case "annotated": kind = .annotated
        case "month":
            guard let month = monthFormatter.date(from: counted.name) else { return nil }
            kind = .month(month)
        default: return nil
        }
        return LibraryCollection(kind: kind, count: counted.count, cover: counted.cover)
    }

    private static var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }

    private static func condition(for kind: LibraryCollection.Kind) -> (String, StatementArguments) {
        switch kind {
        case .starred: (isStarred, [])
        case .annotated: (hasNote, [])
        case .made(let name):
            (
                """
                library_item.id IN (
                    SELECT b.target_id FROM tag_binding b JOIN tag t ON t.id = b.tag_id
                    WHERE b.target_kind = 'library_item' AND t.path = ?
                )
                """,
                [CollectionStore.path(of: name)]
            )
        case .month(let month):
            ("strftime('%Y-%m', promoted_at, 'localtime') = ?", [monthFormatter.string(from: month)])
        }
    }

    // MARK: - Keeping

    /// Stars articles, and keeps them.
    ///
    /// Starring is the ordinary way into the library, so the two happen in one
    /// transaction : an article that is starred and not kept, or kept and not
    /// starred, is a state nothing in the interface could explain.
    @discardableResult
    func setStarred(_ entryIDs: [UUID], to isStarred: Bool, at date: Date = Date()) async throws -> LibraryChange {
        guard !entryIDs.isEmpty else { return LibraryChange() }

        return try await database.writer.write { db in
            _ = try Entry.filter(keys: entryIDs).updateAll(db, Column("is_starred").set(to: isStarred))

            var change = LibraryChange()
            for entryID in entryIDs {
                if isStarred {
                    guard var item = try Self.promote(entryID, at: date, in: db) else { continue }
                    // On the copy, so that a purge of the article it came from
                    // does not quietly un-star what the reader starred.
                    if item.starredAt == nil {
                        item.starredAt = date
                        try item.update(db)
                    }
                    change.kept.append(item)
                } else if let released = try Self.unstar(entryID, at: date, in: db) {
                    change.released.append(released)
                }
            }
            return change
        }
    }

    /// Keeps articles, whatever their starred state.
    ///
    /// This is the path a rule takes at M5, and the one an annotation takes.
    @discardableResult
    func promote(_ entryIDs: [UUID], at date: Date = Date()) async throws -> LibraryChange {
        try await database.writer.write { db in
            try entryIDs.reduce(into: LibraryChange()) { change, entryID in
                if let item = try Self.promote(entryID, at: date, in: db) { change.kept.append(item) }
            }
        }
    }

    /// Writes what the reader thinks of an article, keeping it in the process.
    @discardableResult
    func annotate(_ entryID: UUID, with note: String?, at date: Date = Date()) async throws -> LibraryChange {
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines)

        return try await database.writer.write { db in
            guard var item = try Self.promote(entryID, at: date, in: db) else { return LibraryChange() }
            item.annotation = (note?.isEmpty ?? true) ? nil : note
            try item.update(db)
            return LibraryChange(kept: [item])
        }
    }

    /// Removes a kept article, on purpose.
    ///
    /// The stream row, if it is still there, loses its star with it : the two
    /// always agree.
    @discardableResult
    func remove(_ itemIDs: [UUID]) async throws -> LibraryChange {
        try await database.writer.write { db in
            let items = try LibraryItem.filter(keys: itemIDs).fetchAll(db)
            let entryIDs = items.compactMap(\.entryID)

            _ = try Entry.filter(keys: entryIDs).updateAll(db, Column("is_starred").set(to: false))
            _ = try LibraryItem.filter(keys: itemIDs).deleteAll(db)
            return LibraryChange(released: items)
        }
    }

    // MARK: - Freezing

    /// Copies an article into the library, or returns the copy already there.
    ///
    /// Promotion is idempotent : keeping an article twice keeps it once. The
    /// copy is never refreshed afterwards, since the whole point is that it says
    /// what the article said on the day it was kept.
    @discardableResult
    private static func promote(_ entryID: UUID, at date: Date, in db: Database) throws -> LibraryItem? {
        if let existing = try LibraryItem.filter(LibraryItem.Columns.entryID == entryID).fetchOne(db) {
            return existing
        }
        guard let entry = try Entry.fetchOne(db, key: entryID) else { return nil }

        let feed = try Feed.fetchOne(db, key: entry.feedID)
        let body = try EntryBody.fetchOne(db, key: entryID)

        // An article kept twice from two spellings of one feed is still one
        // article, so the identity of the copy is the identity of the article.
        if let twin = try LibraryItem.filter(
            LibraryItem.Columns.guid == entry.guid && LibraryItem.Columns.feedURL == feed?.url
        ).fetchOne(db) {
            return twin
        }

        // The fullest version there is. Freezing the feed's two sentences when
        // the article's own page has already been fetched would keep the
        // summary of something the reader read whole, and the library exists
        // precisely so that what was kept survives its source.
        //
        // The plain text is taken from whichever was frozen rather than from
        // the row, or the library would be searched by words the kept copy
        // does not contain.
        let content = body?.extractedHTML ?? body?.sanitizedHTML

        let item = LibraryItem(
            entryID: entry.id,
            feedURL: feed?.url,
            feedTitle: feed?.title,
            guid: entry.guid,
            url: entry.url,
            title: entry.title,
            author: entry.author,
            language: entry.language,
            publishedAt: entry.publishedAt,
            promotedAt: date,
            contentHTML: content,
            plainText: content.map(HTMLSanitizer.plainText) ?? body?.plainText,
            imageURL: entry.imageURL
        )
        try item.insert(db)
        return item
    }

    /// Lets go of an article, unless something else is still keeping it.
    ///
    /// An annotation outlives a star : unstarring an article somebody wrote
    /// about must not throw away what they wrote.
    /// Takes the star off, and the copy with it when nothing else keeps it.
    ///
    /// An annotated article stays : the note is a reason of its own. What it
    /// loses is its place in the favourites, which is the star and nothing
    /// more.
    private static func unstar(_ entryID: UUID, at date: Date, in db: Database) throws -> LibraryItem? {
        guard var item = try LibraryItem.filter(LibraryItem.Columns.entryID == entryID).fetchOne(db) else {
            return nil
        }
        guard item.annotation?.isEmpty ?? true else {
            item.starredAt = nil
            try item.update(db)
            return nil
        }

        _ = try item.delete(db)
        return item
    }

    // MARK: - Shapes

    /// The list columns, spelled from the library's own table.
    static let columns = """
        SELECT id, 'library' AS origin, NULL AS feed_id,
               COALESCE(feed_title, '') AS feed_title,
               title, author, url,
               1 AS is_read, 1 AS is_starred, 0 AS has_media, image_url,
               NULL AS icon_url, feed_url AS site_url, feed_url,
               SUBSTR(COALESCE(plain_text, ''), 1, 300) AS excerpt,
               COALESCE(published_at, promoted_at) AS date
        FROM library_item
        """

    static func article(from item: LibraryItem) -> Article {
        Article(
            id: item.id,
            origin: .library,
            title: item.title,
            feedTitle: item.feedTitle ?? "",
            author: item.author,
            url: item.url,
            publishedAt: item.publishedAt,
            language: item.language,
            isRead: true,
            isStarred: true,
            bodyHTML: item.contentHTML,
            annotation: item.annotation
        )
    }
}
