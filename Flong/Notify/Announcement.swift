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
    /// The name of the thing being announced, and never the news itself.
    ///
    /// **The shortest of the three, because it has the least room.** A banner
    /// gives the title one bold line and cuts it at about forty characters,
    /// while the body gets two lines collapsed and four expanded. A headline put
    /// here is a headline the reader has to open the notification to finish
    /// reading, under a body holding a source name eight characters long.
    var title: String
    /// Where the news came from, when that is not already the title.
    ///
    /// One line between the two, which is exactly what an attribution wants :
    /// the writer the reader follows leads, and the paper they wrote it for
    /// goes here.
    var subtitle: String?
    /// The news itself.
    var body: String
    /// What the notifications of one kind are grouped under in Notification
    /// Centre, so a week of them is one stack and not a week of rows.
    var thread: String
    /// The picture standing beside what is said, when the thing said carries
    /// one.
    ///
    /// **Only where the notice is about one thing**, exactly as ``story`` and
    /// ``article`` are : a picture is a picture of something, and the cover of
    /// the first of five articles is a claim about the other four.
    ///
    /// An address and not a file. What is decided here is which picture belongs
    /// to which sentence ; fetching it is the delivery's problem, and a
    /// notification that had to be built by something holding bytes could not
    /// be written by a function a test calls.
    var picture: URL?
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
    /// **One story leads with its own headline.** A story is several newsrooms
    /// on one subject, so unlike an article it has no single name to lead with :
    /// the headline is both the news and the only thing that identifies it. The
    /// newsrooms covering it are an attribution and go on the line between,
    /// which is what a subtitle is ; the line the model wrote saying what
    /// happened is the body.
    ///
    /// Where the model wrote nothing, the newsrooms are the whole message and
    /// take the body rather than being named twice.
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
                body: joined(stories.map(\.title)),
                thread: Thread.newStories,
                // Several are not a place to go, and a tap that had to pick one
                // of them would pick wrongly most of the time.
                story: nil
            )
        }

        let rooms = ListFormatter.localizedString(byJoining: first.rooms)
        let summary = first.summary?.isEmpty == false ? first.summary : nil
        return Announcement(
            title: first.title,
            subtitle: summary == nil ? nil : rooms,
            body: summary ?? rooms,
            thread: Thread.newStories,
            // The picture of the latest article in it to carry one, which is
            // the picture the front page puts the story under.
            picture: first.picture,
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
    /// **The filings are counted and the people are named**, when there are
    /// several : four pieces is four things filed, and saying who put them there
    /// is what a reader acts on. Where one person did it all, they are named
    /// once.
    ///
    /// A collection with nothing new in it says nothing, which is the ordinary
    /// case for a pass that fetched somebody's unchanged list.
    static func filings(
        _ filings: [(collection: String, by: String?, title: String, picture: URL?)]
    ) -> Announcement? {
        guard let first = filings.first else { return nil }

        let collections = Set(filings.map(\.collection))
        let people = Set(filings.compactMap(\.by))

        // One filing, which is the case worth writing well : the collection is
        // where it landed, the person is who put it there, and the headline is
        // the news. Three lines, in the order a notification gives them room.
        //
        // The two names are said in their own right rather than woven into a
        // sentence about them. `X added to Y` needs a verb, and a verb needs a
        // preposition, and a preposition is where a translated sentence about
        // two proper nouns goes wrong : it read `X a ajouté dans Y` in French,
        // which is not a sentence anybody writes.
        if filings.count == 1 {
            return Announcement(
                title: first.collection,
                subtitle: first.by.map { String(localized: "Added by \($0)") },
                body: first.title,
                thread: Thread.filings,
                picture: first.picture
            )
        }

        // Whoever did it, where the answer is short enough to be worth saying.
        // A list of every headline would be a paragraph ; the names are the
        // part a reader acts on.
        let body =
            people.isEmpty
            ? joined(filings.map(\.title))
            : named(people.sorted())

        guard collections.count == 1 else {
            return Announcement(
                title: String(localized: "\(filings.count) additions to your shared collections"),
                body: body,
                thread: Thread.filings
            )
        }

        return Announcement(
            title: first.collection,
            subtitle: String(localized: "\(filings.count) additions"),
            body: body,
            thread: Thread.filings
        )
    }

    /// What the sources and the writers the reader asked about have just
    /// published.
    ///
    /// **Every article, which is what the reader asked for.** The stories are a
    /// calculation : several newsrooms, one subject, and an opening worth
    /// interrupting somebody for. This is the opposite question, asked source
    /// by source and writer by writer : a reader who follows one newsletter,
    /// one blog or one colleague wants to know when *they* publish, and a piece
    /// nobody else covers never becomes a story and would never be announced.
    ///
    /// **One notice per article, however many ways it was asked for.** A writer
    /// the reader follows very often writes for a source they follow as well ;
    /// the store answers the two questions at once, so an article that answers
    /// both is here once, and it is here once in this sentence too.
    ///
    /// Nothing to say about none, which is the ordinary case : almost every
    /// pass brings articles nobody asked anything about.
    ///
    /// **What it came from leads, and the headline is the message.** It was the
    /// other way round, and the other way round is the wrong way : a banner
    /// gives the title one bold line and cuts it at about forty characters,
    /// where the body has two lines and four when it is opened. So the headline,
    /// which is routinely eighty characters, was the truncated part, and under
    /// it sat a source name of eight. The name of whoever the reader asked about
    /// goes first, the paper they wrote it for on the line between, and the
    /// headline underneath with room to be read. A tap opens it.
    ///
    /// Whoever the reader asked about, be that the writer who signed it or the
    /// person it is about : ``ArticleStore/Arrival/subject`` is the one place
    /// that decides which, so the single notice and the several agree.
    ///
    /// **Several are counted under what was asked about**, the person where
    /// there was one and the source otherwise, since naming it once is shorter
    /// than repeating it. **Several of those are counted and then listed**, the
    /// headlines giving way to the names : a reader told `5 new articles` and
    /// left to work out where from would have to open the application to learn
    /// what they were just told.
    static func newArticles(_ arrivals: [ArticleStore.Arrival]) -> Announcement? {
        guard let first = arrivals.first else { return nil }

        guard arrivals.count > 1 else {
            return Announcement(
                title: first.subject,
                subtitle: first.subject == first.source ? nil : first.source,
                body: first.title,
                thread: Thread.newArticles,
                picture: first.picture,
                article: first.id
            )
        }

        // In the order they arrived, and deduplicated : a source that served
        // four articles in one pass is one name, and so is a writer who signed
        // three of them.
        var subjects: [String] = []
        for arrival in arrivals where !subjects.contains(arrival.subject) { subjects.append(arrival.subject) }

        guard subjects.count == 1, let subject = subjects.first else {
            return Announcement(
                title: String(localized: "\(arrivals.count) new articles"),
                body: named(subjects),
                thread: Thread.newArticles
            )
        }

        return Announcement(
            title: subject,
            subtitle: String(localized: "\(arrivals.count) new articles"),
            // A middle dot rather than commas, as the stories are joined : a
            // headline may hold commas of its own.
            body: joined(arrivals.map(\.title)),
            thread: Thread.newArticles
        )
    }

    /// How many headlines a body ever names.
    ///
    /// A notification body is two lines collapsed and about four when it is
    /// opened. Twenty headlines joined by a middle dot is a paragraph, and a
    /// paragraph in a banner is a wall the reader's eye slides off : what they
    /// take from it is the count in the title, which the title already gave
    /// them. Three fit, and the count above says how many there are in all.
    private static let mostNamed = 3

    /// The headlines a body names, joined the way the interface joins them.
    ///
    /// A middle dot rather than commas : a headline may hold commas of its own,
    /// and a comma list of them reads as one long broken sentence. What does
    /// not fit is dropped rather than summarized, the count in the title being
    /// where the reader learns there was more.
    ///
    /// **The newest, and not the first three.** Every query behind these
    /// builders answers oldest first, so taking the front of the list named the
    /// stalest three and dropped everything the reader had not seen.
    private static func joined(_ titles: [String]) -> String {
        titles.suffix(mostNamed).joined(separator: " · ")
    }

    /// The names a body lists, joined the way a language joins a list.
    ///
    /// Names and not headlines, so the language's own list formatter is right
    /// here where the middle dot is right there. Bounded for the same reason :
    /// a pass that brought articles from forty sources would otherwise put
    /// forty names in a banner.
    ///
    /// **A list that was cut says so.** `A, B and C` is a sentence claiming
    /// there were three ; the conjunction is what makes the claim, and it is
    /// exactly wrong about the other thirty-seven. So the ones that fit are
    /// named and the rest are counted.
    private static func named(_ names: [String]) -> String {
        let kept = Array(names.suffix(mostNamed))
        let joined = ListFormatter.localizedString(byJoining: kept)
        guard names.count > kept.count else { return joined }
        return String(localized: "\(joined) and \(names.count - kept.count) others")
    }

    enum Thread {
        static let newStories = "new-stories"
        static let newArticles = "new-articles"
        static let filings = "shared-filings"
    }
}
