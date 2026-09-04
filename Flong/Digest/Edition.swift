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
        case closedAt = "closed_at"
        case points
        case briefLocale = "brief_locale"
        case briefMembers = "brief_members"
        case publishedAt = "published_at"
        case updatedAt = "updated_at"
    }

    var id: UUID
    var slot: EditionSlot
    /// The boundary this edition belongs to, which is also its identity : two
    /// devices working from one schedule mint the same moment and never two
    /// editions for one morning.
    var openedAt: Date
    /// When the next boundary froze it. `nil` is the one being made.
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

    /// The language the model was asked in, exactly as a story records it : a
    /// refusal has no language, and counting one as unanswered asks for ever.
    var briefLocale: String?

    /// Every article of every story on the page, as one value to compare.
    ///
    /// **Every article, and not a sample of them.** A story's own brief is
    /// written from as many of its articles as the window holds ; the edition's
    /// is written from the ten headlines, and what invalidates it is any change
    /// anywhere underneath. An article joining any story on the page is a page
    /// that says something slightly different, so the headline over it is a
    /// question worth putting again.
    var briefMembers: String?

    /// When the edition became something the reader may be shown, which is when
    /// the model had written the whole of it.
    ///
    /// `nil` is an edition still being made. The screen shows the newest
    /// published one, so a page is never half written.
    var publishedAt: Date?

    var updatedAt: Date

    var isPublished: Bool { publishedAt != nil }

    init(
        id: UUID = .v7(),
        slot: EditionSlot,
        openedAt: Date,
        closedAt: Date? = nil,
        points: [String] = [],
        briefLocale: String? = nil,
        briefMembers: String? = nil,
        publishedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.slot = slot
        self.openedAt = openedAt
        self.closedAt = closedAt
        self.points = points
        self.briefLocale = briefLocale
        self.briefMembers = briefMembers
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
    }
}

extension Edition {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let slot = Column(CodingKeys.slot)
        static let openedAt = Column(CodingKeys.openedAt)
        static let closedAt = Column(CodingKeys.closedAt)
        static let publishedAt = Column(CodingKeys.publishedAt)
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
}
