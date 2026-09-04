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

    /// Whether this one arrives without a sound.
    ///
    /// **What one notice per article costs, and what pays for it.** A reader
    /// who asks to hear about every source they follow may get eight banners
    /// from one pass, and eight sounds in a row is not eight pieces of news, it
    /// is a device somebody puts face down. The first of a burst sounds and the
    /// rest arrive quietly, which is what the system's own `passive` level is
    /// for : they are all there, in the stack, and the reader was interrupted
    /// once.
    ///
    /// It is decided where the burst is known, which is the pass, and not here.
    var isQuiet = false

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

    /// A new edition of the digest has been made.
    ///
    /// **The one notice that already has its words written.** Everything else
    /// here is a sentence assembled from names ; an edition arrives carrying a
    /// headline and a line the model wrote over the whole page, in the reader's
    /// own language, and the notice is those two with the edition named between
    /// them. Writing anything of our own on top would be a third opinion about
    /// a page that already has one.
    ///
    /// A tap opens the digest, which is where the edition is. There is no
    /// deeper place to go : the edition *is* the front page.
    static func newEdition(_ edition: Edition) -> Announcement? {
        guard let title = edition.title, !title.isEmpty, let summary = edition.summary, !summary.isEmpty
        else { return nil }

        return Announcement(
            title: title,
            subtitle: String(localized: edition.slot.title),
            body: summary,
            thread: Thread.newEdition
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

    /// One article a source, a writer or a person the reader asked about has
    /// just published.
    ///
    /// **One article, one notice, and never a condensed one.** It counted them
    /// and named three of the headlines : `5 new articles`, and the reader had
    /// to open Flong to learn what four of the five were. A reader who singles
    /// out a newsletter, a colleague or somebody in the news is asking about
    /// each piece, not about how many there were, and a count is the one thing
    /// they can work out for themselves from a stack of banners.
    ///
    /// What made the condensing necessary is gone with it. The watermark is a
    /// column on the article now, so a burst that runs past the bound is said
    /// by the next pass rather than lost, and nothing needs a sentence that
    /// stands for what did not fit.
    ///
    /// **One notice per article, however many ways it was asked for.** A writer
    /// the reader follows very often writes for a source they follow as well ;
    /// the store answers the three questions at once, so an article that
    /// answers two of them is one row and therefore one notice. The guarantee
    /// is a property of the query and not of the wording.
    ///
    /// **What it came from leads, and the headline is the message.** A banner
    /// gives the title one bold line and cuts it at about forty characters,
    /// where the body has two lines and four when it is opened. The headline is
    /// routinely eighty, so it goes in the body with room to be read, and the
    /// name of whoever the reader asked about goes first with the paper they
    /// wrote it for on the line between. That is the answer to *why am I being
    /// told this*.
    ///
    /// The person leads where both apply, since asking about somebody is the
    /// more particular of the requests :
    /// ``ArticleStore/Arrival/subject`` is the one place that decides which.
    static func newArticle(_ arrival: ArticleStore.Arrival) -> Announcement {
        Announcement(
            title: arrival.subject,
            subtitle: arrival.subject == arrival.source ? nil : arrival.source,
            body: arrival.title,
            // **Threaded by what the reader asked about, and not by kind.** One
            // thread for every article notice there is would stack a morning's
            // five publishers into one pile the reader has to open to sort. The
            // subject is what they asked about, so it is what the pile should
            // be named after : five from one paper is one stack, and five
            // papers are five.
            thread: Thread.newArticle(about: arrival.subject),
            picture: arrival.picture,
            article: arrival.id
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
        static let newEdition = "new-edition"

        /// One stack per source, writer or person the reader asked about.
        ///
        /// It was one thread for every article notice there was, which stacked
        /// a morning's five publishers into one pile. Said one article at a
        /// time that matters far more : the stack is what a reader reads
        /// instead of the individual banners, and a stack of unrelated things
        /// says nothing.
        static func newArticle(about subject: String) -> String {
            "new-articles-\(subject)"
        }
        static let filings = "shared-filings"
    }
}
