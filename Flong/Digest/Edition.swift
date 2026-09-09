//
//  Edition.swift
//  Flong
//
//  Created by François Rousselet on 04/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB

/// One of the four moments a day the digest is made.
///
/// **A paper comes out at an hour, and that is the whole idea.** The front page
/// used to be rebuilt on every fetch, so it was never twice the same page and
/// there was no such thing as having read it : a reader who looked at nine and
/// again at ten saw a page that had shifted under them for reasons they could
/// not see. An edition is a page made at a moment, with a name of its own, that
/// stops being the current one when the next is made.
nonisolated enum EditionSlot: String, Codable, Hashable, Sendable, CaseIterable {
    case morning
    case noon
    case evening
    case night

    /// What the reader sees under the date and in the archive.
    var title: LocalizedStringResource {
        switch self {
        case .morning: "Morning edition"
        case .noon: "Midday edition"
        case .evening: "Evening edition"
        case .night: "Night edition"
        }
    }

    /// The hour it comes out at, before the reader moves it.
    ///
    /// Seven, noon, six and eleven : the hours somebody actually picks a paper
    /// up, rather than four points evenly spaced round a clock. The night one
    /// is late rather than at three in the morning, since what it is for is the
    /// reader who looks once more before putting the phone down.
    var defaultHour: Int {
        switch self {
        case .morning: 7
        case .noon: 12
        case .evening: 18
        case .night: 23
        }
    }
}

/// When each of the four comes out, as the reader has it.
///
/// **A choice, so it travels.** Everything the reader decides about themselves
/// goes through the iCloud key-value store, and the hour they want their
/// morning paper at is exactly that : a reader who moves the morning edition to
/// six on the phone did not mean only on the phone.
nonisolated struct EditionSchedule: Codable, Hashable, Sendable {
    /// One entry per slot the reader has switched on, holding the minute of the
    /// day it comes out at.
    var hours: [EditionSlot: Int]

    /// All four, at the hours above. What a reader has before they have said
    /// anything.
    static let standard = EditionSchedule(
        hours: Dictionary(uniqueKeysWithValues: EditionSlot.allCases.map { ($0, $0.defaultHour * 60) })
    )

    var slots: [EditionSlot] { EditionSlot.allCases.filter { hours[$0] != nil } }

    /// The moment of the boundary a given slot falls on, on a given day.
    private func moment(of slot: EditionSlot, on day: Date, in calendar: Calendar) -> Date? {
        guard let minutes = hours[slot] else { return nil }
        return calendar.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day, matchingPolicy: .nextTime)
    }

    /// The edition that is current at this moment, and when it opened.
    ///
    /// **The most recent boundary at or before now**, which is the one thing
    /// every device has to agree on without speaking. Two devices in one time
    /// zone work out the same pair from the same schedule, so they build the
    /// same edition rather than two, and the identity of an edition is the
    /// moment it opened rather than a key one of them minted.
    ///
    /// Yesterday's last edition is looked at too, or a reader opening Flong at
    /// six in the morning, before the first boundary of the day, would be told
    /// there is no edition rather than being handed last night's.
    func current(at now: Date = Date(), in calendar: Calendar = .current) -> (slot: EditionSlot, opened: Date)? {
        let days = [now, calendar.date(byAdding: .day, value: -1, to: now) ?? now]

        return
            days
            .flatMap { day in slots.compactMap { slot in moment(of: slot, on: day, in: calendar).map { (slot, $0) } } }
            .filter { $0.1 <= now }
            .max { $0.1 < $1.1 }
            .map { (slot: $0.0, opened: $0.1) }
    }

    /// The next boundary after this moment, which is what the background task
    /// asks the system to wake it for.
    func next(after now: Date = Date(), in calendar: Calendar = .current) -> Date? {
        let days = [now, calendar.date(byAdding: .day, value: 1, to: now) ?? now]

        return
            days
            .flatMap { day in slots.compactMap { moment(of: $0, on: day, in: calendar) } }
            .filter { $0 > now }
            .min()
    }
}

/// A page made at a moment, and the ten stories on it.
///
/// It carries its own headline and its own line, written by the model over
/// everything on the page. That is not the same question as the one asked about
/// a story : a story is one event said in a few words, and an edition is what
/// is happening this morning said in a few more.
nonisolated struct Edition: Identifiable, Hashable, StoredRecord {
    static let databaseTableName = "edition"

    enum CodingKeys: String, CodingKey {
        case id
        case slot
        case openedAt = "opened_at"
        case coversFrom = "covers_from"
        case closedAt = "closed_at"
        case points
        case pointTopics = "point_topics"
        case briefLocale = "brief_locale"
        case askedAt = "asked_at"
        case publishedAt = "published_at"
        case updatedAt = "updated_at"
    }

    var id: UUID
    var slot: EditionSlot

    /// The boundary this edition closes and comes out at.
    ///
    /// **Three things at once, and it was already two of them.** It is the
    /// dateline, so a page that arrives at ten past eleven still reads
    /// `Édition de la nuit · 23:00` ; it is the identity two devices working
    /// from one schedule agree on without speaking, which is what the unique
    /// index on it says ; and it is now the end of the period, the hour the
    /// page is *about* rather than the hour it starts being filled at.
    ///
    /// **Eleven o'clock means eleven o'clock.** An earlier version closed the
    /// period twenty minutes before the hour, so that the page was finished in
    /// time for its notice to be lodged with the system and delivered
    /// punctually. It cost the reader the last twenty minutes of every period,
    /// always the most recent twenty, and that is not a trade a paper should
    /// make : what the edition of eleven says is what had happened by eleven.
    /// What it costs instead is written under ``isOut(at:)``.
    ///
    /// The name is left as it was on purpose. The unique index keys on it, the
    /// order of the archive keys on it, and so does the watermark that says
    /// which edition was announced : a truer word would cost a migration and
    /// buy a doc comment, which is what this one is for.
    var openedAt: Date

    /// Where the period this page condenses begins, open at the bottom.
    ///
    /// An article landing exactly on it belonged to the edition before. It is
    /// written once, when the row is made, and never worked out again : the
    /// schedule travels through the key-value store, so the reader may move an
    /// hour or switch a slot off while a page is being made, and a period
    /// recomputed against a schedule that has since changed would claim a
    /// stretch of time nobody lived through.
    ///
    /// `nil` is a page made before the periods existed.
    var coversFrom: Date?

    /// What the row is once it is no longer the one being made.
    ///
    /// With ``publishedAt`` set it means what it always meant : a back number.
    /// With ``publishedAt`` null it means **abandoned** : a later boundary went
    /// to press while this page had still not come out, so its hour has gone
    /// and it will never be written. What is lost there is the page and never
    /// the news, the period folding into the one that follows.
    var closedAt: Date?

    /// What is on the page, as a few points rather than a paragraph.
    ///
    /// **A list, and it was a sentence.** Asked for two or three sentences over
    /// ten stories the model wrote one clause per story and joined them with
    /// commas, so the line under the headline ran to seven items and eight
    /// lines of type : a paragraph of nothing but subjects, which is the shape
    /// a reader's eye slides off. It is also what a front page has always
    /// done : a headline, and under it the few other things worth knowing, one
    /// per line.
    ///
    /// Five at most, which is what a person takes in at a glance and half of
    /// what the page below holds. Empty until the model has written them, and
    /// an edition with none is not shown : section 14's rule that a page is
    /// entire without a model is answered by saying there is no edition rather
    /// than by putting somebody else's words at the top of one.
    ///
    /// **And there is nothing over them.** An edition carried a name of its own
    /// and every real page showed the same thing : the name was this list said
    /// again in fewer words. A front page has never had a name. The dateline
    /// says which edition, and what is on the page is what is on the page.
    var points: [String]

    /// The subject each point is about, one entry per point, in that order.
    ///
    /// **Worked out once, where the page is written.** It was worked out on
    /// every read instead, from a live join, so the marks beside a back
    /// number's points drifted as the filing caught up behind it and every
    /// archive page changed its marks at once when a reader edited a subject.
    /// A page is what it was, and what it was includes what each of its lines
    /// was about.
    ///
    /// The name and not the glyph : the glyph belongs to the subject, so a
    /// reader who changes it sees it change everywhere, which is right. An
    /// empty string is a point that matched nothing, and an empty list is a
    /// page written before this, for which the match is still worked out where
    /// it is read.
    var pointTopics: [String]

    /// The language the model was asked in, exactly as a story records it : a
    /// refusal has no language, and counting one as unanswered asks for ever.
    ///
    /// Set with ``publishedAt`` still null, it is the durable answer that the
    /// model has read this page and will not write about it. The ten cannot
    /// move any more, so asking again would get the same refusal.
    var briefLocale: String?

    /// When the model was really put the question about this page.
    ///
    /// A fact about the edition exactly as `story.topics_asked_at` is a fact
    /// about a story, and written only where a call actually left. It is the
    /// one brake on the retry that remains : a model that was unusable is worth
    /// asking again inside the page's own window, and not on every pass.
    var askedAt: Date?

    /// When the page was written, which is at its hour or after it.
    ///
    /// A page cannot be written before the hour its period ends at, so the
    /// model is asked once that hour has passed and the page comes out when it
    /// answers. On a device the system did not wake it is later than the hour,
    /// and the dateline still says the hour : a paper that arrives at ten past
    /// eleven is still the eleven o'clock edition.
    ///
    /// `nil` is an edition still being made. Set once and never cleared, and
    /// there is nothing left that could clear it : a published page is not
    /// composed again, not written again and not asked about again, whatever
    /// arrives underneath it.
    var publishedAt: Date?

    var updatedAt: Date

    /// Whether the model has written it. A question about a page being made.
    var isPublished: Bool { publishedAt != nil }

    /// Whether it has come out.
    ///
    /// **Written and out are the same thing, and that is a decision.** A page
    /// finished before its hour could have its notice lodged with the system
    /// and delivered on the hour with nothing of ours running, which is what
    /// `UNCalendarNotificationTrigger` is for and what
    /// `BGTaskRequest.earliestBeginDate` explicitly does not promise. It would
    /// cost the period its last minutes, and the period is what the reader
    /// asked for : the edition of eleven says what had happened by eleven. So
    /// the notice arrives when the page comes into being, which on a device the
    /// system chose not to wake is after the hour.
    func isOut(at now: Date = Date()) -> Bool { isPublished }

    init(
        id: UUID = .v7(),
        slot: EditionSlot,
        openedAt: Date,
        coversFrom: Date? = nil,
        closedAt: Date? = nil,
        points: [String] = [],
        pointTopics: [String] = [],
        briefLocale: String? = nil,
        askedAt: Date? = nil,
        publishedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.slot = slot
        self.openedAt = openedAt
        self.coversFrom = coversFrom
        self.closedAt = closedAt
        self.points = points
        self.pointTopics = pointTopics
        self.briefLocale = briefLocale
        self.askedAt = askedAt
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
    }

    /// The moment the period of this page begins, however old the row is.
    ///
    /// A page written before the periods existed claims none, so it covers
    /// nothing before its own dateline.
    var periodStart: Date { coversFrom ?? openedAt }

    /// The moment the period of this page ends, which is its own hour.
    var periodEnd: Date { openedAt }
}

nonisolated extension Edition {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let slot = Column(CodingKeys.slot)
        static let openedAt = Column(CodingKeys.openedAt)
        static let coversFrom = Column(CodingKeys.coversFrom)
        static let closedAt = Column(CodingKeys.closedAt)
        static let askedAt = Column(CodingKeys.askedAt)
        static let publishedAt = Column(CodingKeys.publishedAt)
    }

    /// The editions that have come out, newest first.
    ///
    /// **One place, and every reader goes through it.** There are two of them,
    /// the front page and the archive, and a page shown by one and not the
    /// other would be a back number the reader cannot reach or a front page
    /// with no history.
    static func out(by now: Date = Date()) -> QueryInterfaceRequest<Edition> {
        Edition
            .filter(Columns.publishedAt != nil)
            .order(Columns.openedAt.desc)
    }

    /// What the notice for a boundary is known by.
    ///
    /// **Derived from the boundary and from nothing else.** The name has to be
    /// worked out by a path that may no longer have the row : a notice lodged
    /// for eleven and then unwanted, because the reader moved the schedule at
    /// half past ten, is taken back by name, and the name is all that is left
    /// of it. The boundary is the edition's identity on every device, so it is
    /// the right thing to spell. Seconds since the epoch rather than the row's
    /// own key, a key being this device's and an integer being legible in a
    /// log line.
    static func notice(for boundary: Date) -> String {
        "edition-\(Int(boundary.timeIntervalSince1970))"
    }
}

/// An edition and the ten stories on it, as one thing to hand to a screen.
///
/// A pair rather than a join : the stories are frozen rows of the edition's own
/// and not a read of the story table, which is what lets a page from last
/// Tuesday still read correctly after a purge took its articles.
nonisolated struct PublishedEdition: Hashable, Identifiable, Sendable {
    var edition: Edition
    var stories: [EditionStory]

    /// The mark each point wears, one per point and in the same order.
    ///
    /// **Worked out where the page is read, not written down.** A point is a
    /// sentence the model wrote over the whole page ; nothing links it to a
    /// story, and nothing should, since the model is free to say one thing
    /// about two of them. What can be said is which story a point is *about*,
    /// by the words they share, and a story carries the subjects it was filed
    /// under. See ``EditionStore/marks(for:over:filedAs:wearing:)``.
    var marks: [String] = []

    var id: UUID { edition.id }
}

/// One story on one edition, as that edition showed it.
///
/// **The head is copied rather than joined to.** A story is derived data and
/// the grouping tidies away the ones that lose their members ; an edition from
/// last Tuesday that lost a row when a purge took an article would be a page
/// that shrank behind the reader's back. This is the same rule the library
/// keeps against the stream : what was kept is frozen, and what it was made
/// from may go.
///
/// The identifier is kept beside it with no foreign key, so a row whose story
/// is still there opens it and one whose story has gone is simply a headline.
nonisolated struct EditionStory: Hashable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "edition_story"

    enum CodingKeys: String, CodingKey {
        case editionID = "edition_id"
        case position
        case storyID = "story_id"
        case title
        case summary
        case isGenerated = "is_generated"
        case isTranslated = "is_translated"
        case imageURL = "image_url"
        case imageCredit = "image_credit"
    }

    var editionID: UUID
    /// Where it stands on the page, nought first.
    var position: Int
    var storyID: UUID
    var title: String
    var summary: String?
    var isGenerated: Bool
    var isTranslated: Bool
    var imageURL: String?

    /// The room the picture came with.
    ///
    /// **Frozen beside the picture, and it has to be.** A story is several
    /// rooms and the photograph is one room's, so the two are taken from one
    /// and the same article on purpose. A frozen address beside a credit read
    /// live is a caption naming the wrong paper, and nothing about it would
    /// look wrong.
    var imageCredit: String?

    /// This row as the page printed it, over whatever the world has since done.
    ///
    /// **The words are the page's and the figures are the world's.** The front
    /// page joined its frozen rows against the live stories and then threw the
    /// frozen half away, so a headline the model rewrote in the afternoon
    /// changed on a page printed that morning, and a story that fell out of the
    /// sixty newest vanished from it altogether. But a page frozen whole is a
    /// page whose article count is wrong within the hour, and the count is not
    /// a claim about the page : it is a claim about the story, which is still
    /// moving and which the reader can still open.
    ///
    /// So the split is by what a thing is about. What the page said - the
    /// headline, the line under it, who wrote them, the picture and the room it
    /// came from, and the order - is what it said and does not move again.
    /// What the story is - how many articles, how many rooms, when the last one
    /// came, its shape over time, and the subjects it is filed under - goes on
    /// being read live. The subjects are deliberately on that side : a rubric is
    /// a fact about the story, the reader may re-file it, and the marks beside
    /// the points are read from the same filing, so freezing one and not the
    /// other would put two answers on one page.
    ///
    /// - Parameter live: the story as it is now, or `nil` where a purge has
    ///   taken it. A row whose story has gone is kept and drawn from its frozen
    ///   half alone, with ``DigestStory/hasFigures`` false : a back number that
    ///   lost a row would be an archive nobody could trust.
    /// - Parameter dateline: the edition's own hour, which stands in for the
    ///   dates of a story that is no longer there.
    func printed(over live: DigestStory?, on dateline: Date) -> DigestStory {
        DigestStory(
            id: storyID,
            title: title,
            summary: summary,
            isGenerated: isGenerated,
            isTranslated: isTranslated,
            generatedBy: live?.generatedBy,
            articleCount: live?.articleCount ?? 0,
            feedMarks: live?.feedMarks ?? [],
            feedCount: live?.feedCount ?? 0,
            firstAt: live?.firstAt ?? dateline,
            lastAt: live?.lastAt ?? dateline,
            arrivals: live?.arrivals ?? [],
            isLive: live?.isLive ?? false,
            imageURL: imageURL.flatMap(URL.init(string:)),
            imageCredit: imageCredit,
            topics: live?.topics ?? [],
            hasFigures: live != nil
        )
    }
}
