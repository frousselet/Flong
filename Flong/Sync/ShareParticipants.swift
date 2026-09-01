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
nonisolated enum ShareParticipants {
    /// The people in one shared collection, by the identifier their filings
    /// carry.
    ///
    /// The zone-wide share sits under a name CloudKit reserves for it, which is
    /// the only way to ask for one : it is not a record the application named.
    static func names(inZone zoneID: CKRecordZone.ID, from database: CKDatabase) async -> [String: String] {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        guard let share = try? await database.record(for: id) as? CKShare else { return [:] }

        return share.participants.reduce(into: [:]) { found, participant in
            guard let record = participant.userIdentity.userRecordID?.recordName,
                let name = name(of: participant)
            else { return }
            found[record] = name
        }
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
        return nil
    }
}
