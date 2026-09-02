//
//  ShareParticipants.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CloudKit
import Foundation

/// Who is in a shared collection, under a name a reader would recognize.
///
/// **What is stored against a filing is not a name.** `CKRecord`'s creator is a
/// user record identifier, which is opaque, per container, and says nothing to
/// anybody. It is the right thing to store, because the server sets it and no
/// client can write it : a participant who typed somebody else's name into a
/// field of their own would be believed. Turning it into a name is a separate
/// question, and it is answered by the share, which is where the people are.
///
/// **A name may not be there at all**, and that is not a failure. CloudKit
/// gives the components of a name for a participant the system is willing to
/// name, and nothing for one it is not. A filing whose author cannot be named
/// is shown without a name rather than with an identifier nobody can read.
/// What a reader does recognize is a face, and CloudKit has none to give : that
/// is ``ShareMember``'s half of the answer, written by each participant
/// themselves.
nonisolated enum ShareParticipants {
    /// The zone-wide share of a zone, or `nil` where the zone is not shared.
    ///
    /// The share sits under a name CloudKit reserves for it, which is the only
    /// way to ask for one : it is not a record the application named and it is
    /// not reachable through the zone itself.
    static func share(inZone zoneID: CKRecordZone.ID, from database: CKDatabase) async -> CKShare? {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        return try? await database.record(for: id) as? CKShare
    }

    /// Everybody the share lists, as the roster half of a member.
    ///
    /// **Only the columns the share is the authority on.** A name and a face
    /// are what each participant wrote about themselves, and this must not
    /// touch them : see ``ShareMemberStore/reconcile(_:inZone:)``.
    ///
    /// `me` is the reader's own record in the container, which is what marks
    /// the one member they may not remove. `isOwnShare` says the share was read
    /// out of their private database, which is the third way of recognizing
    /// them : see ``isTheReader(record:isOwner:isOwnShare:me:)``.
    static func roster(of share: CKShare, in zoneName: String, me: String?, isOwnShare: Bool) -> [ShareMember] {
        share.participants.compactMap { participant in
            let stated = participant.userIdentity.userRecordID?.recordName
            let isOwner = participant.role == .owner
            let isMe = isTheReader(record: stated, isOwner: isOwner, isOwnShare: isOwnShare, me: me)

            // **The reader is filed under the name they file themselves
            // under.** CloudKit hands them `__defaultOwner__` in a share of
            // their own, and their card is written under their real record in
            // the container : left as it comes, the two halves of their own row
            // are two rows, so the roster deletes their card and they appear
            // with no name and no face in their own collection.
            let record = isMe ? (me ?? stated) : stated
            guard let key = key(of: participant, record: record) else { return nil }

            return ShareMember(
                zoneName: zoneName,
                key: key,
                userRecord: record,
                shareName: name(of: participant),
                isOwner: isOwner,
                isMe: isMe,
                // Read-only is a participation the owner chose in the system's
                // own sheet, and a device holding one offers no way to file.
                mayWrite: participant.permission != .readOnly,
                standing: standing(of: participant)
            )
        }
    }

    /// Whether one participant is the reader themselves.
    ///
    /// **CloudKit does not name you to yourself, and does not always call you
    /// by your own record either.** Three ways of telling, and any of them is
    /// enough :
    ///
    /// - the record matches the reader's own in the container ;
    /// - it is `__defaultOwner__`, which is the name CloudKit uses for whoever
    ///   is asking rather than for anybody in particular ;
    /// - the share was read out of the reader's own private database and this
    ///   is its owner, which is the reader by construction and is true whether
    ///   or not the container answered who they are.
    ///
    /// Getting this wrong is not cosmetic : it is what decides whether their
    /// own row carries the name and the face they wrote for themselves, or
    /// whether they turn up in their own collection as `Someone`.
    static func isTheReader(record: String?, isOwner: Bool, isOwnShare: Bool, me: String?) -> Bool {
        if let record, let me, record == me { return true }
        if record == CKCurrentUserDefaultName { return true }
        return isOwnShare && isOwner
    }

    /// The people in one shared collection, by the identifier their filings
    /// carry.
    static func names(inZone zoneID: CKRecordZone.ID, from database: CKDatabase) async -> [String: String] {
        guard let share = await share(inZone: zoneID, from: database) else { return [:] }

        return share.participants.reduce(into: [:]) { found, participant in
            guard let record = participant.userIdentity.userRecordID?.recordName,
                let name = name(of: participant)
            else { return }
            found[record] = name
        }
    }

    /// Takes one person out of a share, and hands back what it now lists.
    ///
    /// **Only the owner may.** Everybody else's save is refused by the server,
    /// which is the right place for that rule to live : a device deciding it
    /// for itself would be a device that could be persuaded otherwise.
    ///
    /// What they filed is not touched. They wrote it into the collection, one
    /// record of their own, and taking somebody out of a share is about what
    /// they may see from now on rather than about unsaying what they said.
    static func remove(
        _ key: String,
        fromShareIn zoneID: CKRecordZone.ID,
        from database: CKDatabase,
        me: String?,
        isOwnShare: Bool
    ) async throws -> [ShareMember] {
        guard let share = await share(inZone: zoneID, from: database) else {
            throw CKError(.unknownItem)
        }
        // Never the reader themselves, so the record is the one the share
        // states and there is nothing to resolve : the owner is refused just
        // below, and taking anybody else out is about them and not about who
        // is asking.
        guard
            let participant = share.participants.first(where: {
                self.key(of: $0, record: $0.userIdentity.userRecordID?.recordName) == key
            }),
            participant.role != .owner
        else {
            // Already gone, or the owner, whom the share cannot be without.
            return roster(of: share, in: zoneID.zoneName, me: me, isOwnShare: isOwnShare)
        }

        share.removeParticipant(participant)
        let saved = try await database.modifyRecords(saving: [share], deleting: [])

        // What the server now holds rather than what was sent : the removal is
        // only true once it has been saved, and the saved share is the thing
        // that says so.
        let confirmed = try saved.saveResults.values.compactMap { try $0.get() as? CKShare }.first
        return roster(of: confirmed ?? share, in: zoneID.zoneName, me: me, isOwnShare: isOwnShare)
    }

    /// The addresses of the people this share will not name, by the key their
    /// row is under.
    ///
    /// **Only the ones with no name at all.** Somebody who has accepted is
    /// named by CloudKit, which is their own name for themselves and is not
    /// this reader's to overrule ; somebody who has not is a bare address, and
    /// that is what the address book is asked about. So a lookup never stands
    /// in front of a name : see ``AddressBook``.
    static func unnamed(in share: CKShare, me: String?, isOwnShare: Bool) -> [String: String] {
        share.participants.reduce(into: [:]) { found, participant in
            guard participant.userIdentity.nameComponents == nil else { return }

            let stated = participant.userIdentity.userRecordID?.recordName
            let isMe = isTheReader(
                record: stated,
                isOwner: participant.role == .owner,
                isOwnShare: isOwnShare,
                me: me
            )
            // The reader is drawn from their own profile and never looked up :
            // asking the address book who this device belongs to would be
            // asking the wrong question of the wrong book.
            guard !isMe else { return }

            let record = stated
            guard let key = key(of: participant, record: record),
                let address = participant.userIdentity.lookupInfo?.emailAddress
                    ?? participant.userIdentity.lookupInfo?.phoneNumber,
                !address.isEmpty
            else { return }

            found[key] = address
        }
    }

    // MARK: - Naming one person

    /// What both halves of a member name this person by.
    ///
    /// The record in the container where CloudKit has resolved one, so that the
    /// roster and the card the person wrote themselves land on one row. Failing
    /// that the address the invitation went to, which is all there is to go on
    /// for somebody who has not accepted yet.
    private static func key(of participant: CKShare.Participant, record: String?) -> String? {
        if let record {
            return SyncRecords.memberKey(forParticipantNamed: record)
        }
        if let address = participant.userIdentity.lookupInfo?.emailAddress
            ?? participant.userIdentity.lookupInfo?.phoneNumber, !address.isEmpty
        {
            return SyncRecords.memberKey(forInvitationTo: address)
        }
        return nil
    }

    /// What to call one participant, or nothing when there is nothing to call
    /// them.
    ///
    /// The components first, since that is a person's own name. Failing that
    /// the address the invitation went to, which is at least something the
    /// reader chose and typed. Failing both, nothing : an opaque identifier is
    /// worse than silence, because it looks like information.
    private static func name(of participant: CKShare.Participant) -> String? {
        if let components = participant.userIdentity.nameComponents {
            let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !formatted.trimmingCharacters(in: .whitespaces).isEmpty { return formatted }
        }
        if let email = participant.userIdentity.lookupInfo?.emailAddress, !email.isEmpty { return email }
        if let phone = participant.userIdentity.lookupInfo?.phoneNumber, !phone.isEmpty { return phone }
        return nil
    }

    private static func standing(of participant: CKShare.Participant) -> ShareMember.Standing {
        switch participant.acceptanceStatus {
        case .accepted: .accepted
        case .pending: .invited
        case .removed: .removed
        default: .unknown
        }
    }
}
