//
//  FullText.swift
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

/// Fetches the page an article lives at, and keeps what it holds.
///
/// Most feeds serve a standfirst and a link. The article is at the end of that
/// link, and this goes and gets it once, for good.
///
/// **Only for an article the reader opened.** Never a whole feed, never ahead of
/// time, never in a batch. A reader who does not open an article costs its
/// publisher nothing, and a page fetched because somebody is reading it is a
/// page fetched for the reason pages exist. Section 20 asks for politeness to
/// publishers, and speculative extraction of five hundred articles a day is the
/// opposite of it.
///
/// **Only when the feed was short.** A feed that serves the whole article has
/// already done the work, and asking its server again would be asking for
/// something already in hand.
///
/// It goes through the same ``FeedFetcher`` as everything else, so it carries
/// the identifying user agent, waits its turn in the token bucket for that host,
/// and is capped in size and in time.
nonisolated struct FullText: Sendable {
    /// Under this many characters, what the feed gave is a summary.
    ///
    /// A standfirst and a first paragraph run to a few hundred ; an article runs
    /// to thousands. The line is drawn well above the first so that a short
    /// piece is not fetched for nothing, and well below the second so that a
    /// truncated one is not mistaken for whole.
    static let summaryLength = 1200

    /// A page is text. One past this is a mistake or a trap.
    static let maximumBytes = 4 * 1024 * 1024

    private let database: AppDatabase
    private let fetcher: FeedFetcher
    private let sessions: SessionStoring

    init(_ database: AppDatabase, fetcher: FeedFetcher? = nil, sessions: SessionStoring = KeychainSessions()) {
        self.database = database
        self.sessions = sessions
        self.fetcher =
            fetcher
            ?? FeedFetcher(limits: FeedFetcher.Limits(maximumBytes: FullText.maximumBytes))
    }

    /// Whether an article is worth going to the page for.
    ///
    /// It has an address, the feed was short, and nobody has been yet. The last
    /// is what makes this cost one request per article for the life of the
    /// article rather than one per reading.
    static func isWorthFetching(url: URL?, feedHTML: String?, extractedHTML: String?) -> Bool {
        guard let url, url.scheme?.hasPrefix("http") == true else { return false }
        guard extractedHTML == nil else { return false }

        return HTMLSanitizer.plainText(feedHTML ?? "").count < summaryLength
    }

    /// The session that covers an address, if the reader has one.
    ///
    /// Matched on the site rather than the exact host : a session signed in on
    /// `lemonde.fr` is the one every feed and article of the site needs,
    /// whichever subdomain they sit on.
    static func session(for url: URL, in sessions: SessionStoring) -> SiteSession? {
        guard let host = FeedURL.room(of: url) else { return nil }

        // The host itself, then every site above it down to two labels : a
        // session signed in on `lemonde.fr` is the one `abonnes.lemonde.fr`
        // wants, however many levels apart they are.
        var candidates = [host]
        var parts = host.split(separator: ".")
        while parts.count > 2 {
            parts.removeFirst()
            candidates.append(parts.joined(separator: "."))
        }

        for candidate in candidates {
            guard let session = try? sessions.session(for: candidate), session.covers(url), session.isUsable()
            else { continue }
            return session
        }
        return nil
    }

    /// Fetches the page, extracts the article and keeps it.
    ///
    /// Returns what it found, or `nil` when the page could not be reached or
    /// held no article. Either way the reader keeps what the feed gave, which
    /// is why nothing here is worth an error on screen.
    @discardableResult
    func extract(_ entryID: UUID) async -> String? {
        let article = try? await database.writer.read { db -> (url: URL, feedHTML: String?, extracted: String?)? in
            guard let entry = try Entry.fetchOne(db, key: entryID), let url = entry.url else { return nil }
            let body = try EntryBody.fetchOne(db, key: entryID)
            return (url: url, feedHTML: body?.sanitizedHTML, extracted: body?.extractedHTML)
        }

        guard let article,
            Self.isWorthFetching(url: article.url, feedHTML: article.feedHTML, extractedHTML: article.extracted)
        else { return nil }

        // A site the reader subscribes to is asked as the reader, with the
        // session they signed in for. A site they do not is asked as anybody.
        let session = Self.session(for: article.url, in: sessions)
        let request = FetchRequest(url: article.url, cookies: session?.valid() ?? [])

        guard case .updated(let document) = await fetcher.fetch(request) else { return nil }

        // A page states its encoding in a header and in a `<meta>`, and either
        // may be wrong or missing : `PageText` is what knows the order to try.
        let html = PageText.text(of: document.data, contentType: document.contentType)
        guard let extracted = ArticleExtractor.extract(html, from: document.url) else {
            // A site the reader signed in to and which answers with no article
            // is a site that has stopped recognizing them. Saying so is the
            // whole mitigation for a session being a thing that breaks.
            if session != nil {
                Log.enrich.notice("A subscribed site answered with no article : the session may have expired")
            } else {
                Log.enrich.notice("A page held no article that could be told apart from the page")
            }
            return nil
        }

        // It worked, which is the only honest proof a session still does.
        if var session, let host = FeedURL.room(of: article.url) {
            session.lastWorkedAt = Date()
            try? sessions.setSession(session, for: host)
        }

        // The plain text goes with it. It is what the search index and
        // Spotlight read, and leaving it as the feed's two-line summary would
        // mean fetching the whole article and then searching the teaser.
        let plainText = HTMLSanitizer.plainText(extracted)

        try? await database.writer.write { db in
            guard var body = try EntryBody.fetchOne(db, key: entryID) else {
                try EntryBody(entryID: entryID, extractedHTML: extracted, plainText: plainText).insert(db)
                return
            }
            body.extractedHTML = extracted
            body.plainText = plainText
            try body.update(db)
        }
        return extracted
    }
}
