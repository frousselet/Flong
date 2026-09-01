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

    enum Thread {
        static let newStories = "new-stories"
        static let filings = "shared-filings"
    }
}
