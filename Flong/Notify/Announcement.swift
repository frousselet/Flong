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
    /// The subject a tap opens, when there is exactly one to open.
    var subject: String?

    /// The model has found subjects it had never used before.
    ///
    /// Nothing to say about none, which is the ordinary case : most passes file
    /// every story under a subject the reader already has.
    ///
    /// **The body lists every name and the title counts them**, so the two
    /// always agree. A body showing the first few of a longer list is a small
    /// lie, and the system truncates a long one anyway, which is the system's
    /// business rather than a reason to say less than the truth.
    static func newSubjects(_ names: [String]) -> Announcement? {
        guard !names.isEmpty else { return nil }

        return Announcement(
            title: names.count == 1
                ? String(localized: "New subject")
                : String(localized: "\(names.count) new subjects"),
            body: ListFormatter.localizedString(byJoining: names),
            thread: Thread.newSubjects,
            // One subject is a place to go ; several are not, and a tap that
            // had to pick one of them would pick wrongly most of the time.
            subject: names.count == 1 ? names[0] : nil
        )
    }

    enum Thread {
        static let newSubjects = "new-subjects"
    }
}
