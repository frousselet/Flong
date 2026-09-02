//
//  Announcement.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// What a notification says, before anything knows how to deliver it.
///
/// Separated from the delivery on purpose. What can be wrong about a
/// notification is almost never the posting : it is the wording, the plural,
/// the list that reads badly with one item, and where a tap lands. All of that
/// is decided here, by a function that takes names and gives back a sentence,
/// and all of it is testable without a bundle, an authorization or a device.
nonisolated struct Announcement: Hashable, Sendable {
    var title: String
    var body: String
    /// What the notifications of one kind are grouped under in Notification
    /// Centre, so a week of them is one stack and not a week of rows.
    var thread: String
    /// The story a tap opens, when there is exactly one to open.
    var story: UUID?
    /// The article a tap opens, when there is exactly one to open.
    ///
    /// Never set beside ``story`` : a notice is about one thing or about
    /// several, and a tap has one place to land.
    var article: UUID?

    /// Stories that have just been opened.
    ///
    /// Nothing to say about none, which is the ordinary case : most passes have
    /// articles join a story that already exists, and a cluster of one is not a
    /// story at all.
    ///
    /// **One story leads with its own headline.** The headline is the news, and
    /// a notification titled `New story` with the headline underneath buries
    /// the thing the reader is being told. The rooms covering it go in the body,
    /// which is the digest's own signal that something is happening, unless the
    /// model wrote a line saying what happened, which says more.
    ///
    /// **Several are counted in the title and listed in the body**, so the two
    /// always agree.
    static func newStories(_ stories: [DigestStore.Opened]) -> Announcement? {
        guard let first = stories.first else { return nil }

        guard stories.count == 1 else {
            return Announcement(
                title: String(localized: "\(stories.count) new stories"),
                // Not a comma list : a headline may hold commas of its own, and
                // a list of them read as one sentence is unreadable.
                body: stories.map(\.title).joined(separator: " · "),
                thread: Thread.newStories,
                // Several are not a place to go, and a tap that had to pick one
                // of them would pick wrongly most of the time.
                story: nil
            )
        }

        let rooms = ListFormatter.localizedString(byJoining: first.rooms)
        return Announcement(
            title: first.title,
            body: first.summary?.isEmpty == false ? first.summary! : rooms,
            thread: Thread.newStories,
            story: first.id
        )
    }

    /// Somebody has put something in a collection the reader is in.
    ///
    /// **The one notice here that is a person and not a calculation.** Every
    /// other thing Flong may say is something it worked out from feeds nobody
    /// else touched ; this is somebody doing something, so the person leads and
    /// the collection follows. A notice that opened `2 new articles` and left
    /// the reader to work out who and where would be the least useful way to
    /// say the most interesting thing in the application.
    ///
    /// **The people are counted, not the filings**, when there are several :
    /// one person adding four pieces is one thing happening, and four names
    /// would be four. Where one person did it all, they are named.
    ///
    /// A collection with nothing new in it says nothing, which is the ordinary
    /// case for a pass that fetched somebody's unchanged list.
    static func filings(
        _ filings: [(collection: String, by: String?, title: String)]
    ) -> Announcement? {
        guard let first = filings.first else { return nil }

        let collections = Set(filings.map(\.collection))
        let people = Set(filings.compactMap(\.by))

        // One filing, which is the case worth writing well : the headline is
        // the news and everything else is where it came from.
        if filings.count == 1 {
            return Announcement(
                title: first.by.map { String(localized: "\($0) added to \(first.collection)") }
                    ?? String(localized: "Added to \(first.collection)"),
                body: first.title,
                thread: Thread.filings
            )
        }

        let title =
            collections.count == 1
            ? String(localized: "\(filings.count) added to \(first.collection)")
            : String(localized: "\(filings.count) added to your shared collections")

        // Whoever did it, where the answer is short enough to be worth saying.
        // A list of every headline would be a paragraph ; the names are the
        // part a reader acts on.
        let body =
            people.isEmpty
            ? filings.map(\.title).joined(separator: " · ")
            : ListFormatter.localizedString(byJoining: people.sorted())

        return Announcement(title: title, body: body, thread: Thread.filings)
    }

    /// What the sources the reader asked about have just published.
    ///
    /// **Every article, which is what the reader asked for.** The stories are a
    /// calculation : several newsrooms, one subject, and an opening worth
    /// interrupting somebody for. This is the opposite question, asked source
    /// by source : a reader who follows one newsletter, one blog or one
    /// colleague wants to know when *they* publish, and a piece nobody else
    /// covers never becomes a story and would never be announced.
    ///
    /// Nothing to say about none, which is the ordinary case : almost every
    /// pass brings articles from sources the reader asked nothing about.
    ///
    /// **One article leads with its own headline**, for the same reason a lone
    /// story does : the headline is the news, and the source it came from is
    /// what the body is for. A tap opens it.
    ///
    /// **Several from one source are counted under its name**, since the source
    /// is what the reader asked about and naming it once is shorter than
    /// repeating it. **Several sources are counted and then listed**, the
    /// headlines giving way to the names : a reader told `5 new articles` and
    /// left to work out where from would have to open the application to learn
    /// what they were just told.
    static func newArticles(_ arrivals: [ArticleStore.Arrival]) -> Announcement? {
        guard let first = arrivals.first else { return nil }

        guard arrivals.count > 1 else {
            return Announcement(
                title: first.title,
                body: first.source,
                thread: Thread.newArticles,
                article: first.id
            )
        }

        // In the order they arrived, and deduplicated : a source that served
        // four articles in one pass is one name.
        var sources: [String] = []
        for arrival in arrivals where !sources.contains(arrival.source) { sources.append(arrival.source) }

        guard sources.count == 1, let source = sources.first else {
            return Announcement(
                title: String(localized: "\(arrivals.count) new articles"),
                body: ListFormatter.localizedString(byJoining: sources),
                thread: Thread.newArticles
            )
        }

        return Announcement(
            title: String(localized: "\(source) : \(arrivals.count) new articles"),
            // A middle dot rather than commas, as the stories are joined : a
            // headline may hold commas of its own.
            body: arrivals.map(\.title).joined(separator: " · "),
            thread: Thread.newArticles
        )
    }

    enum Thread {
        static let newStories = "new-stories"
        static let newArticles = "new-articles"
        static let filings = "shared-filings"
    }
}
