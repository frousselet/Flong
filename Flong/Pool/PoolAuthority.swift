//
//  PoolAuthority.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CloudKit
import CryptoKit
import Foundation

/// Who may put anything into the common pool, and who decides.
///
/// **The pool is closed, and it is opened one person at a time.** Anybody may
/// read it ; only somebody who was let in may add to it. Being let in is a
/// sponsorship : the author of the application is in by construction, and
/// everybody already in may bring somebody else. That is the whole rule, and
/// what it buys is that nothing reaches the page from a stranger.
///
/// **The graph is walked on the device, from a root written into the
/// application.** Each contributor publishes a record naming who they sponsor,
/// and CloudKit stamps that record with its writer, so a sponsorship cannot be
/// claimed on somebody else's behalf. Every device fetches those records, walks
/// out from ``PoolTrust/root`` and keeps whoever it reaches.
///
/// **Banning takes the branch with it.** A ban that left the banned person's
/// own invitations standing would be no ban at all : anybody about to be cut
/// out would sponsor ten accounts first. Reaching somebody means reaching them
/// through people who are all still in, so cutting one person cuts everybody
/// who came in through them and nobody else. It is what makes a sponsorship an
/// undertaking rather than a favour.
///
/// **Nothing here can stop a write.** A public database takes a record from any
/// iCloud account, and no CloudKit role can be denied to one person, so what
/// the author holds is not the power to silence somebody's device but the power
/// to make what it says count for nothing, everywhere, from the next pass. The
/// application declines to publish at all until it has seen itself reached, so
/// an unsponsored reader writes nothing in the ordinary case ; a client written
/// to misbehave could still write, and would still be counted by nobody.
nonisolated enum PoolTrust {
    /// The identity the walk starts from.
    ///
    /// The author's own user record in the container : opaque, stable for them,
    /// and the same value CloudKit stamps on anything they write. It is not a
    /// secret and there is nothing to protect in it ; it is an anchor, and it
    /// is written here rather than fetched because a fetched anchor is no
    /// anchor at all.
    ///
    /// **`nil` until it is filled in, and then nobody is in.** A closed pool
    /// with no root is a pool with no members : the page shows nothing rather
    /// than showing something nobody vouched for. That is the safe way round,
    /// and it makes filling this in the one thing standing between the feature
    /// and working at all. The value is the author's own contributor code,
    /// which their panel shows them.
    static let root: String? = nil

    /// How many people one contributor may bring in.
    ///
    /// Twenty. A sponsorship is a personal undertaking and this is the number
    /// that keeps it one : it bounds how fast the pool can grow, so a single
    /// careless member cannot open it to a crowd, and cutting them out stays a
    /// proportionate repair. The cap is applied when a record is read, against
    /// a sorted list, so every device agrees on which twenty.
    static let sponsorLimit = 20

    /// How many people the author may believe on their own, cut out, and how
    /// many addresses may be withheld.
    static let trustedLimit = 50
    static let bannedLimit = 500
    static let blockedLimit = 1_000

    /// Whether this device is the one that may write the authority record.
    static func isRoot(_ identity: String?) -> Bool {
        guard let root, let identity, !root.isEmpty else { return false }
        return identity == root
    }

    /// Everybody the sponsorship graph reaches from the root.
    ///
    /// A plain walk, and it needs to be nothing more. Cycles look after
    /// themselves, since a person already reached is not queued twice ; a
    /// banned person is neither reached nor walked through, which is what makes
    /// a ban take the branch with it.
    ///
    /// Empty when there is no root, which is the honest answer for a closed
    /// pool whose anchor has not been set : nobody was let in by anybody.
    static func authorised(from root: String?, vouches: [String: Set<String>], banned: Set<String>) -> Set<String> {
        guard let root, !root.isEmpty, !banned.contains(root) else { return [] }

        var reached: Set<String> = [root]
        var queue = [root]

        while let sponsor = queue.popLast() {
            for person in (vouches[sponsor] ?? []).sorted() where !banned.contains(person) {
                if reached.insert(person).inserted { queue.append(person) }
            }
        }

        return reached
    }
}

/// What the author decided, as one record.
///
/// Three lists rather than three records, because they are one decision made in
/// one place and read in one fetch : who counts on their own, who is cut out,
/// and which addresses are never suggested. A device that read two of the three
/// would be acting on half an instruction.
///
/// **Believed only from the author.** The record type is creatable by anybody,
/// as everything in a public database is, so an authority record is worth
/// nothing for existing : what makes one authentic is that CloudKit says the
/// author wrote it. Every other one is ignored, which is also what makes
/// squatting the record name pointless, since the record is found by type and
/// filtered by creator rather than fetched by name.
nonisolated struct PoolAuthority: Hashable, Sendable {
    /// Whose offers count at once rather than counting for one.
    var trusted: Set<String> = []
    /// Who is cut out, along with everybody they brought in.
    var banned: Set<String> = []
    /// The addresses never suggested, as digests.
    var blocked: Set<String> = []

    static let empty = PoolAuthority()

    /// The record, for the one person who may write one.
    static func record(_ authority: PoolAuthority, by contributor: UUID) -> CKRecord {
        let record = CKRecord(
            recordType: PoolRecords.RecordType.authority,
            recordID: CKRecord.ID(recordName: PoolRecords.name(forAuthorityBy: contributor))
        )
        record[PoolRecords.Field.trusted] = Array(authority.trusted.sorted().prefix(PoolTrust.trustedLimit))
        record[PoolRecords.Field.banned] = Array(authority.banned.sorted().prefix(PoolTrust.bannedLimit))
        record[PoolRecords.Field.blocked] = Array(authority.blocked.sorted().prefix(PoolTrust.blockedLimit))
        return record
    }

    /// What a record says, or nothing where it is not the author's.
    static func read(_ record: CKRecord, root: String? = PoolTrust.root) -> PoolAuthority? {
        guard record.recordType == PoolRecords.RecordType.authority else { return nil }
        guard let root, PoolList.creator(of: record) == root else { return nil }

        func names(_ field: String, _ limit: Int) -> Set<String> {
            Set((record[field] as? [String] ?? []).prefix(limit))
        }

        return PoolAuthority(
            trusted: names(PoolRecords.Field.trusted, PoolTrust.trustedLimit),
            banned: names(PoolRecords.Field.banned, PoolTrust.bannedLimit),
            blocked: names(PoolRecords.Field.blocked, PoolTrust.blockedLimit)
        )
    }

    /// What an address is withheld as.
    ///
    /// **A digest, never the address.** One reason to withhold an address is
    /// that it should never have been public, and a list of forbidden addresses
    /// published in the open would broadcast the very thing it exists to hold
    /// back. Half a SHA-256 is far more than enough to tell addresses apart and
    /// says nothing about any of them.
    static func digest(of address: String) -> String {
        SHA256.hash(data: Data(address.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Who one contributor brought into the pool.
///
/// One record per person, rewritten whole when they add or remove somebody.
/// **The sponsor is the record's creator and never a field**, so nobody can
/// write themselves into somebody else's invitations, which is the same reason
/// the counting is done on ``CKRecord/creatorUserRecordID``.
nonisolated enum PoolVouch {
    static func record(sponsoring codes: some Sequence<String>, by contributor: UUID) -> CKRecord {
        let record = CKRecord(
            recordType: PoolRecords.RecordType.vouch,
            recordID: CKRecord.ID(recordName: PoolRecords.name(forVouchBy: contributor))
        )
        record[PoolRecords.Field.sponsored] = Array(Set(codes).sorted().prefix(PoolTrust.sponsorLimit))
        return record
    }

    /// One record, read back into something the store can hold.
    static func received(_ record: CKRecord) -> Received? {
        guard record.recordType == PoolRecords.RecordType.vouch else { return nil }

        let names = record[PoolRecords.Field.sponsored] as? [String] ?? []
        return Received(
            creator: PoolList.creator(of: record),
            sponsored: Set(names.sorted().prefix(PoolTrust.sponsorLimit)),
            modifiedAt: record.modificationDate ?? Date()
        )
    }

    nonisolated struct Received: Hashable, Sendable {
        var creator: String
        var sponsored: Set<String>
        var modifiedAt: Date
    }
}
