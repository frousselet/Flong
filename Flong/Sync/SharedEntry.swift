//
//  SharedEntry.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB

/// One article, as it crosses between two people.
///
/// **There is nowhere in here to put a body, and that is the point.** What
/// travels is the excerpt the feed published and never the article : the
/// article is not the reader's to hand anybody, and what a publisher puts in a
/// feed for syndication is the part they chose to make public.
/// ``StreamBlock/Header`` says the same thing about an article going between
/// the reader's own devices and it carries a body, which is right for that
/// journey and wrong for this one. Reusing it would leave the rule resting on
/// every future caller remembering not to fill a field in ; a shape with no
/// such field cannot carry one by mistake.
///
/// **The excerpt is already plain text.** ``HTMLSanitizer/excerpt(_:limit:)``
/// runs the markup through `plainText` and cuts it at three hundred characters,
/// so no markup crosses between accounts at all and there is nothing for a
/// renderer to interpret. That is what makes this cheap to receive safely.
///
/// **Every address here has been through ``PublicURL``** before it was written,
/// against the keychain of whichever device wrote it, since nobody else can
/// know which of a feed's parameters were that reader's.
nonisolated struct SharedEntry: Hashable, Sendable, Codable {
    /// The article's identity as the sender's device knows it.
    ///
    /// Kept so that a recipient who follows the same source can recognize their
    /// own copy of the piece and show that instead : `ArticleKey` already
    /// answers what makes two articles the same article.
    var guid: String
    var title: String
    /// The article's own page, truncated of what said who the sender was.
    var url: String?
    /// The excerpt the feed published. Plain text, never markup.
    var excerpt: String?
    var author: String?
    var publishedAt: Date?
    var imageURL: String?
    /// The feed it came from, when that address is a public one.
    ///
    /// A feed whose address is itself the subscription is masked in the store
    /// already, and a masked address is no use to anybody : it says nothing a
    /// recipient could subscribe to. Nothing is sent for those.
    var feedURL: String?
    /// What the publisher is called, which travels whether the address does.
    var sourceTitle: String?

    // MARK: - What arrives

    /// The same entry, bounded, for something another person's device wrote.
    ///
    /// **A participant runs their own copy of a client on their own machine**
    /// and can put whatever they like in a record. The excerpt rule has already
    /// closed the large hole, since plain text handed to a renderer as text is
    /// not an injection ; what is left is worth doing anyway. A megabyte of
    /// text where three hundred characters were expected is the difference
    /// between a shrug and a page that will not scroll, and a run of direction
    /// overrides is a headline that rewrites the ones around it.
    ///
    /// So : every string is cut to what its field is for, control characters
    /// and direction overrides go, and an address that is not plain `http` or
    /// `https` is dropped rather than stored and handed to a web view later.
    var received: SharedEntry {
        SharedEntry(
            guid: Self.bounded(guid, to: 500) ?? "",
            title: Self.bounded(title, to: 500) ?? "",
            url: Self.address(url),
            excerpt: Self.bounded(excerpt, to: 1000),
            author: Self.bounded(author, to: 200),
            publishedAt: publishedAt,
            imageURL: Self.address(imageURL),
            feedURL: Self.address(feedURL),
            sourceTitle: Self.bounded(sourceTitle, to: 200)
        )
    }

    /// Whether there is enough of it left to be worth keeping.
    var isUsable: Bool { !guid.isEmpty && !title.isEmpty }

    /// A string cut to length, with what is not text taken out of it.
    static func bounded(_ text: String?, to limit: Int) -> String? {
        guard let text else { return nil }

        let kept = text.unicodeScalars.filter { scalar in
            // Control characters, and the overrides that let a run of text
            // reorder the text around it.
            !CharacterSet.controlCharacters.contains(scalar) && !directionOverrides.contains(scalar)
        }

        let cleaned = String(String.UnicodeScalarView(kept))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return cleaned.count <= limit ? cleaned : String(cleaned.prefix(limit))
    }

    /// An address, if it is one this application is willing to hold.
    ///
    /// Anything that is not `http` or `https` is dropped : a `javascript:` or a
    /// `data:` address is a thing to run, not a thing to read, and one arriving
    /// from another person is one nobody here asked for.
    static func address(_ text: String?) -> String? {
        guard let text, text.count <= 2000,
            let url = URL(string: text),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host() != nil
        else { return nil }
        return url.absoluteString
    }

    private static let directionOverrides: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "\u{200E}\u{200F}")
        set.insert(charactersIn: Unicode.Scalar(0x202A)!...Unicode.Scalar(0x202E)!)
        set.insert(charactersIn: Unicode.Scalar(0x2066)!...Unicode.Scalar(0x2069)!)
        return set
    }()

    /// Roughly what one of these is worth in a record, for the chunking.
    ///
    /// An excerpt is three hundred characters and the rest is short, so this is
    /// under a kilobyte in practice and a collection of a thousand still fits
    /// in one record. The margin is deliberate : a save refused for being a few
    /// bytes over costs a great deal more than a chunk cut early.
    var weight: Int {
        guid.utf8.count + title.utf8.count + (url?.utf8.count ?? 0) + (excerpt?.utf8.count ?? 0)
            + (author?.utf8.count ?? 0) + (imageURL?.utf8.count ?? 0) + (feedURL?.utf8.count ?? 0)
            + (sourceTitle?.utf8.count ?? 0) + 128
    }
}

// MARK: - Reading what the reader filed

nonisolated extension SharedEntry {
    /// Everything in one of the reader's made collections, ready to travel.
    ///
    /// **The truncation happens here, on the device that writes.** Each feed's
    /// designated parameters come off its articles' addresses against this
    /// device's own keychain, because nobody else can know which of them were
    /// this reader's. A collection holding articles from twenty feeds asks the
    /// keychain once rather than twenty times.
    static func entries(
        in database: AppDatabase,
        collectionNamed name: String,
        credentials: CredentialStoring
    ) async throws -> [SharedEntry] {
        try await entries(
            in: database,
            where: """
                e.id IN (
                    SELECT b.target_id FROM tag_binding b JOIN tag t ON t.id = b.tag_id
                    WHERE b.target_kind = 'entry' AND t.path = ?
                )
                """,
            arguments: [CollectionStore.path(of: name)],
            credentials: credentials
        )
    }

    /// One article, ready to travel, for a reader filing it by hand.
    static func entry(
        in database: AppDatabase,
        articleID: UUID,
        credentials: CredentialStoring
    ) async throws -> SharedEntry? {
        try await entries(in: database, where: "e.id = ?", arguments: [articleID], credentials: credentials).first
    }

    /// The one query, so that what leaves is assembled in one place.
    ///
    /// **The truncation happens here, on the device that writes.** Each feed's
    /// designated parameters come off its articles' addresses against this
    /// device's own keychain, because nobody else can know which of them were
    /// this reader's. A collection holding articles from twenty feeds asks the
    /// keychain once rather than twenty times.
    private static func entries(
        in database: AppDatabase,
        where condition: String,
        arguments: StatementArguments,
        credentials: CredentialStoring
    ) async throws -> [SharedEntry] {
        let designations = (try? credentials.everySecretParameter()) ?? [:]

        return try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT e.guid AS guid, e.title AS title, e.url AS url, e.excerpt AS excerpt,
                           e.author AS author, e.published_at AS published_at, e.image_url AS image_url,
                           f.id AS feed_id, f.url AS feed_url, f.title AS feed_title
                    FROM entry e
                    JOIN feed f ON f.id = e.feed_id
                    WHERE \(condition) AND e.is_hidden = 0
                    ORDER BY COALESCE(e.published_at, e.received_at) DESC
                    """,
                arguments: arguments
            )

            return rows.map { row in
                let feedID: UUID = row["feed_id"]
                let secret = designations[feedID]
                let feedURL = (row["feed_url"] as String?).flatMap(URL.init(string:))

                return SharedEntry(
                    guid: row["guid"],
                    title: row["title"],
                    url: Self.outgoing(row["url"], without: secret),
                    excerpt: row["excerpt"],
                    author: row["author"],
                    publishedAt: row["published_at"],
                    imageURL: Self.outgoing(row["image_url"], without: secret),
                    // A masked address says nothing a recipient could follow,
                    // so it is not sent at all rather than sent uselessly.
                    feedURL: feedURL.flatMap { MaskedURL.isMasked($0) ? nil : $0.absoluteString },
                    sourceTitle: row["feed_title"]
                )
            }
        }
    }

    private static func outgoing(_ text: String?, without secret: SecretParameters?) -> String? {
        guard let text, let url = URL(string: text) else { return nil }
        return PublicURL.of(url, without: secret).absoluteString
    }
}
