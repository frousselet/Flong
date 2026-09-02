//
//  ShareMember.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CloudKit
import Foundation
import GRDB

/// One person in a shared collection.
///
/// **Two sources, and each answers what only it can.** The share says who is a
/// participant, who owns the collection, who may write in it and who has
/// actually accepted : CloudKit sets all of that and no client can forge it,
/// which is what makes it worth believing. What it does not reliably give is
/// anything a reader would recognize : a name only where the system is willing
/// to give one, and never a face, because a `CKUserIdentity` has none.
///
/// So the face and the name come from the person themselves. Each participant
/// writes one card into the collection's zone, carrying what they typed into
/// their own profile, exactly as they write what they file : one record per
/// person, written by nobody else, so a name and a face cannot be put against
/// somebody who did not choose them.
///
/// **The two never overwrite each other.** A roster that arrives without a card
/// leaves the face standing, and a card that arrives before the roster does not
/// invent a role. Where both are missing, the person is shown by their initials
/// or by nothing at all : an opaque identifier is worse than silence, because
/// it looks like information.
nonisolated struct ShareMember: Identifiable, Hashable, Sendable {
    /// Where somebody has got to with the invitation.
    ///
    /// `invited` is worth drawing rather than hiding : an owner who invited
    /// somebody a week ago and sees nothing has no way of telling a refusal
    /// from a message that never arrived.
    enum Standing: String, Hashable, Sendable {
        case accepted
        case invited
        case removed
        case unknown
    }

    var zoneName: String
    /// What both sources name this person by : see
    /// ``SyncRecords/name(forSharedMemberBy:)``.
    var key: String
    /// Their record in the container, where CloudKit has resolved one.
    var userRecord: String?
    /// What they call themselves in Flong, off their own card.
    var name: String?
    /// What CloudKit is willing to call them, off the share.
    var shareName: String?
    /// Their face, off their own card, already at the size a face is drawn at.
    var picture: Data?
    var isOwner = false
    /// Whether this is the reader, which is the one member they may not remove
    /// and the one whose name needs no explaining.
    var isMe = false
    var mayWrite = true
    var standing: Standing = .unknown

    var id: String { key }

    /// What to call them, or nothing when there is nothing to call them.
    ///
    /// Their own card first, since that is the name they chose in this
    /// application. Failing that whatever the share gives, which is their
    /// iCloud name or the address the invitation went to. Failing both,
    /// nothing.
    var displayName: String? { name ?? shareName }

    /// What stands in for a face when there is none.
    var initials: String? { displayName.flatMap(ProfilePicture.initials(of:)) }

    /// Where they go in the list : the owner first, then the people who have
    /// joined, then the ones still to answer, and alphabetically inside each.
    static func before(_ one: ShareMember, _ other: ShareMember) -> Bool {
        if one.isOwner != other.isOwner { return one.isOwner }
        if (one.standing == .invited) != (other.standing == .invited) { return other.standing == .invited }
        return (one.displayName ?? "\u{10FFFF}").localizedCaseInsensitiveCompare(other.displayName ?? "\u{10FFFF}")
            == .orderedAscending
    }
}

// MARK: - The card that travels

nonisolated extension ShareMember {
    /// The longest name a card may carry.
    ///
    /// It came off somebody else's device, so it is bounded here rather than
    /// trusted for having been written by a copy of this application.
    static let nameLimit = 100

    /// This reader's own card, for one shared collection's zone.
    ///
    /// Named after them, so a reader who changes their face on their iPad
    /// rewrites the card they wrote from their iPhone rather than appearing
    /// twice in the same collection.
    static func card(
        name: String?,
        picture: Data?,
        by participant: CKRecord.ID,
        in zone: CKRecordZone.ID
    ) -> CKRecord {
        let record = CKRecord(
            recordType: SyncRecords.RecordType.sharedMember,
            recordID: CKRecord.ID(recordName: SyncRecords.name(forSharedMemberBy: participant), zoneID: zone)
        )
        record["name"] = bounded(name)
        // The small version, which is the only one there is : a profile picture
        // is scaled and re-encoded on the way into the preferences, so what
        // travels is already a few tens of kilobytes and needs no asset.
        record["picture"] = picture
        return record
    }

    /// What one card says, with everything it does not say left empty.
    ///
    /// **Nothing here is trusted.** It was written by another person's device,
    /// which may be running anything at all : the name is bounded and stripped
    /// of the characters that reorder the text around them, and the face is put
    /// back through the same scaling a picture of the reader's own goes
    /// through, so a megabyte of something that is not an image is refused
    /// rather than stored and drawn.
    static func card(from record: CKRecord) -> ShareMember? {
        guard record.recordType == SyncRecords.RecordType.sharedMember else { return nil }

        return ShareMember(
            zoneName: record.recordID.zoneID.zoneName,
            key: record.recordID.recordName,
            userRecord: record.creatorUserRecordID?.recordName,
            name: bounded(record["name"] as? String),
            picture: (record["picture"] as? Data).flatMap(ProfilePicture.scaled)
        )
    }

    private static func bounded(_ name: String?) -> String? {
        SharedEntry.bounded(name, to: nameLimit)
    }
}

// MARK: - The store

/// Who is in each of the collections this device knows about.
nonisolated struct ShareMemberStore: Sendable {
    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    /// Everybody in every shared collection, by the zone they are in.
    ///
    /// One query for the whole grid : a page showing twenty collections should
    /// not ask twenty questions to draw twenty face piles.
    func all() async throws -> [String: [ShareMember]] {
        let members = try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM share_member").map(Self.member(from:))
        }
        return Dictionary(grouping: members, by: \.zoneName)
            .mapValues { $0.sorted(by: ShareMember.before) }
    }

    func members(inZone zoneName: String) async throws -> [ShareMember] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM share_member WHERE zone_name = ?", arguments: [zoneName])
                .map(Self.member(from:))
        }
        .sorted(by: ShareMember.before)
    }

    /// Writes what a card carries, and only that.
    ///
    /// The roster's own columns are left exactly as they are : a card says who
    /// somebody is, never what they are allowed to do, and a card arriving
    /// before the share has been read must not turn a participant into
    /// somebody of unknown standing.
    func remember(card: ShareMember) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO share_member
                        (zone_name, member_key, user_record, name, picture, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT (zone_name, member_key) DO UPDATE SET
                        user_record = COALESCE(excluded.user_record, user_record),
                        name = excluded.name,
                        picture = excluded.picture,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    card.zoneName, card.key, card.userRecord, card.name, card.picture, Date(),
                ]
            )
        }
    }

    /// Writes what the share says about one collection, whole.
    ///
    /// **Only ever called with a roster that actually arrived.** What it does
    /// beyond writing rows is drop the people the share no longer lists, which
    /// is how somebody removed stops being drawn ; running it on a fetch that
    /// failed would empty a collection because iCloud was unreachable.
    ///
    /// The card's own columns survive it. Somebody's face does not change
    /// because their standing did.
    func reconcile(_ roster: [ShareMember], inZone zoneName: String) async throws {
        // A share always lists at least its owner, so nothing arriving is a
        // share that is not there any more rather than a share with nobody in
        // it. `NOT IN ()` is not SQL either.
        guard !roster.isEmpty else { return try await forget(zoneName: zoneName) }

        try await database.writer.write { db in
            for member in roster {
                try db.execute(
                    sql: """
                        INSERT INTO share_member
                            (zone_name, member_key, user_record, share_name, is_owner, is_me,
                             may_write, status, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT (zone_name, member_key) DO UPDATE SET
                            user_record = COALESCE(excluded.user_record, user_record),
                            share_name = excluded.share_name,
                            is_owner = excluded.is_owner,
                            is_me = excluded.is_me,
                            may_write = excluded.may_write,
                            status = excluded.status,
                            updated_at = excluded.updated_at
                        """,
                    arguments: [
                        zoneName, member.key, member.userRecord, member.shareName, member.isOwner,
                        member.isMe, member.mayWrite, member.standing.rawValue, Date(),
                    ]
                )
            }

            let kept = roster.map(\.key)
            try db.execute(
                sql: """
                    DELETE FROM share_member
                    WHERE zone_name = ? AND member_key NOT IN (\(databaseQuestionMarks(count: kept.count)))
                    """,
                arguments: StatementArguments([zoneName] + kept)
            )
        }
    }

    /// Drops one person, for a removal that has just been carried out.
    ///
    /// The next roster would say it too. This is so the page says it now : a
    /// reader who takes somebody out and watches them stay for a round trip has
    /// been told the removal did not work.
    func forget(memberKey: String, inZone zoneName: String) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM share_member WHERE zone_name = ? AND member_key = ?",
                arguments: [zoneName, memberKey]
            )
        }
    }

    /// Everybody in a collection that has gone.
    func forget(zoneName: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM share_member WHERE zone_name = ?", arguments: [zoneName])
        }
    }

    private static func member(from row: Row) -> ShareMember {
        ShareMember(
            zoneName: row["zone_name"],
            key: row["member_key"],
            userRecord: row["user_record"],
            name: row["name"],
            shareName: row["share_name"],
            picture: row["picture"],
            isOwner: row["is_owner"],
            isMe: row["is_me"],
            mayWrite: row["may_write"],
            standing: ShareMember.Standing(rawValue: row["status"]) ?? .unknown
        )
    }
}
