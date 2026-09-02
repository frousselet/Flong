//
//  ShareMemberTests.swift
//  FlongTests
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
import Testing

@testable import Flong

/// Who is in a shared collection : the half the share says, the half each
/// person says about themselves, and the rule that neither overwrites the
/// other.
@Suite("Share members")
struct ShareMemberTests {
    private let database: AppDatabase
    private let store: ShareMemberStore

    private let zone = "shared-0199b0d0-0000-7000-8000-000000000001"

    init() throws {
        database = try AppDatabase.inMemory()
        store = ShareMemberStore(database)
    }

    private func zoneID() -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zone, ownerName: CKCurrentUserDefaultName)
    }

    private func participant(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name)
    }

    // MARK: - Naming one person

    /// Two devices of one reader have to work out the same name for their card,
    /// or filing from an iPad would put a second face in the collection.
    @Test("A card is named after the person, the same way every time")
    func namesACardAfterThePerson() {
        let one = SyncRecords.name(forSharedMemberBy: participant("_abc"))
        let again = SyncRecords.memberKey(forParticipantNamed: "_abc")

        #expect(one == again)
        #expect(one != SyncRecords.memberKey(forParticipantNamed: "_def"))
        #expect(one.hasPrefix("member-"))
    }

    /// A deletion arrives as an identifier and nothing else, so the name is
    /// what says a card apart from a list.
    @Test("A card is told from a list by its name alone")
    func tellsACardFromAList() {
        let card = SyncRecords.name(forSharedMemberBy: participant("_abc"))
        let list = SyncRecords.name(forSharedListBy: participant("_abc"))

        #expect(SyncRecords.memberKey(ofRecordNamed: card) == card)
        #expect(SyncRecords.memberKey(ofRecordNamed: list) == nil)
        #expect(SyncRecords.listKey(ofRecordNamed: card) == nil)
    }

    // MARK: - What arrives on a card

    @Test("A name far longer than a name is cut down")
    func boundsALongName() {
        let sent = ShareMember.card(
            name: String(repeating: "x", count: 5000),
            picture: nil,
            by: participant("_abc"),
            in: zoneID()
        )

        #expect(ShareMember.card(from: sent)?.name?.count == ShareMember.nameLimit)
    }

    /// A run of these rewrites the text around it, so a name in a list of
    /// people could reorder the names above and below it.
    @Test("Direction overrides and control characters are taken out of a name")
    func removesOverridesFromAName() {
        let sent = ShareMember.card(
            name: "Ada\u{202E}ecalevoL\u{202C}\u{0007}",
            picture: nil,
            by: participant("_abc"),
            in: zoneID()
        )

        #expect(ShareMember.card(from: sent)?.name == "AdaecalevoL")
    }

    /// It came off another person's device, which may be running anything at
    /// all : bytes that are not an image must not become a face that never
    /// draws.
    @Test("Something that is not a picture is refused rather than stored")
    func refusesAPictureThatIsNotOne() {
        let sent = ShareMember.card(
            name: "Ada",
            picture: Data(repeating: 0xAB, count: 4096),
            by: participant("_abc"),
            in: zoneID()
        )

        #expect(ShareMember.card(from: sent)?.picture == nil)
    }

    @Test("A record of another kind is not read as a card")
    func refusesAnotherKindOfRecord() {
        let other = CKRecord(
            recordType: SyncRecords.RecordType.sharedList,
            recordID: CKRecord.ID(recordName: "list-abc-0", zoneID: zoneID())
        )

        #expect(ShareMember.card(from: other) == nil)
    }

    // MARK: - The two halves of a row

    @Test("A roster that arrives after a card leaves the face standing")
    func aRosterKeepsTheFace() async throws {
        let key = SyncRecords.memberKey(forParticipantNamed: "_abc")
        try await store.remember(
            card: ShareMember(zoneName: zone, key: key, userRecord: "_abc", name: "Ada", picture: Data([1, 2, 3]))
        )
        try await store.reconcile(
            [ShareMember(zoneName: zone, key: key, userRecord: "_abc", shareName: "A. Lovelace", standing: .accepted)],
            inZone: zone
        )

        let members = try await store.members(inZone: zone)
        #expect(members.count == 1)
        #expect(members.first?.name == "Ada")
        #expect(members.first?.picture == Data([1, 2, 3]))
        #expect(members.first?.shareName == "A. Lovelace")
        #expect(members.first?.standing == .accepted)
    }

    @Test("A card that arrives after a roster leaves the standing alone")
    func aCardKeepsTheStanding() async throws {
        let key = SyncRecords.memberKey(forParticipantNamed: "_abc")
        try await store.reconcile(
            [
                ShareMember(
                    zoneName: zone,
                    key: key,
                    userRecord: "_abc",
                    shareName: "A. Lovelace",
                    mayWrite: false,
                    standing: .accepted
                )
            ],
            inZone: zone
        )
        try await store.remember(
            card: ShareMember(zoneName: zone, key: key, userRecord: "_abc", name: "Ada")
        )

        let members = try await store.members(inZone: zone)
        #expect(members.first?.name == "Ada")
        #expect(members.first?.shareName == "A. Lovelace")
        #expect(members.first?.mayWrite == false)
        #expect(members.first?.standing == .accepted)
    }

    /// The share is what says who is in a collection, so somebody the owner has
    /// taken out stops being drawn even though their card is still in the zone.
    @Test("Somebody the share no longer lists is dropped")
    func dropsWhoIsGone() async throws {
        let one = SyncRecords.memberKey(forParticipantNamed: "_abc")
        let other = SyncRecords.memberKey(forParticipantNamed: "_def")

        try await store.remember(card: ShareMember(zoneName: zone, key: one, name: "Ada"))
        try await store.remember(card: ShareMember(zoneName: zone, key: other, name: "Grace"))
        try await store.reconcile([ShareMember(zoneName: zone, key: one, shareName: "Ada")], inZone: zone)

        let members = try await store.members(inZone: zone)
        #expect(members.map(\.key) == [one])
    }

    /// A fetch that failed says nothing about who is in a collection, so it is
    /// never handed here as an empty roster : this is what happens if it ever
    /// is, and it must not be a silent emptying of somebody's collection.
    @Test("A roster with nobody in it takes the collection with it")
    func anEmptyRosterIsNotHalfARoster() async throws {
        let key = SyncRecords.memberKey(forParticipantNamed: "_abc")
        try await store.remember(card: ShareMember(zoneName: zone, key: key, name: "Ada"))
        try await store.reconcile([], inZone: zone)

        #expect(try await store.members(inZone: zone).isEmpty)
    }

    @Test("One collection's people are not another's")
    func keepsCollectionsApart() async throws {
        let key = SyncRecords.memberKey(forParticipantNamed: "_abc")
        try await store.remember(card: ShareMember(zoneName: zone, key: key, name: "Ada"))
        try await store.remember(card: ShareMember(zoneName: "shared-other", key: key, name: "Ada"))
        try await store.forget(zoneName: zone)

        let all = try await store.all()
        #expect(all[zone] == nil)
        #expect(all["shared-other"]?.count == 1)
    }

    // MARK: - What the reader's own address book adds

    /// Somebody invited who has not accepted has no identity for CloudKit to
    /// resolve, so the row is the address the invitation went to. The reader
    /// knows who that is, because it is in their contacts.
    @Test("A name out of the address book stands in front of a bare address")
    func prefersTheAddressBookToAnAddress() {
        var member = ShareMember(zoneName: zone, key: "a", shareName: "33695754884")
        #expect(member.displayName == "33695754884")
        #expect(member.isUnnamed)

        member.contactName = "Elise Hupin Jouan"
        #expect(member.displayName == "Elise Hupin Jouan")
        #expect(!member.isUnnamed)
    }

    /// It is looked up only for somebody the share would not name, so what it
    /// stands in front of is never a person's own name for themselves.
    @Test("A name of their own is never overruled by the address book")
    func doesNotOverruleTheirOwnName() {
        let member = ShareMember(zoneName: zone, key: "a", name: "Ada", contactName: "Somebody else")
        #expect(member.displayName == "Ada")
    }

    @Test("A face off their own card comes before one out of the address book")
    func prefersTheirOwnFace() {
        var member = ShareMember(zoneName: zone, key: "a", contactPicture: Data([9]))
        #expect(member.face == Data([9]))

        member.picture = Data([1])
        #expect(member.face == Data([1]))
    }

    /// The reader is drawn from their own profile : asking the address book who
    /// this device belongs to is the wrong question of the wrong book.
    @Test("The reader is never somebody to look up")
    func doesNotLookUpTheReader() {
        #expect(!ShareMember(zoneName: zone, key: "a", isMe: true).isUnnamed)
    }

    @Test("What the address book says is kept apart from the other two halves")
    func keepsTheThreeSourcesApart() async throws {
        let key = SyncRecords.memberKey(forParticipantNamed: "_them")
        try await store.reconcile(
            [ShareMember(zoneName: zone, key: key, shareName: "33695754884", standing: .invited)],
            inZone: zone
        )
        try await store.note(name: "Elise", picture: Data([7]), for: key, inZone: zone)

        var found = try await store.members(inZone: zone).first
        #expect(found?.displayName == "Elise")
        #expect(found?.shareName == "33695754884")

        // A roster arriving again leaves it standing, exactly as it leaves a
        // card standing.
        try await store.reconcile(
            [ShareMember(zoneName: zone, key: key, shareName: "33695754884", standing: .accepted)],
            inZone: zone
        )
        found = try await store.members(inZone: zone).first
        #expect(found?.contactName == "Elise")
        #expect(found?.standing == .accepted)
    }

    // MARK: - The order they are read in

    @Test("The owner comes first, then whoever has joined, then the invitations")
    func ordersThePeople() {
        let owner = ShareMember(zoneName: zone, key: "a", name: "Zoe", isOwner: true, standing: .accepted)
        let joined = ShareMember(zoneName: zone, key: "b", name: "Ada", standing: .accepted)
        let asked = ShareMember(zoneName: zone, key: "c", name: "Alan", standing: .invited)

        #expect([asked, joined, owner].sorted(by: ShareMember.before).map(\.name) == ["Zoe", "Ada", "Alan"])
    }

    @Test("Somebody who cannot be named goes last rather than first")
    func ordersTheUnnamedLast() {
        let named = ShareMember(zoneName: zone, key: "a", name: "Ada", standing: .accepted)
        let unnamed = ShareMember(zoneName: zone, key: "b", standing: .accepted)

        #expect([unnamed, named].sorted(by: ShareMember.before).map(\.key) == ["a", "b"])
    }

    // MARK: - Recognizing the reader themselves

    /// **CloudKit does not name you to yourself.** Failing to recognize the
    /// reader is what puts them in their own collection as `Someone`, with no
    /// name and no face, since their own card is then filed under a different
    /// key from their roster row and the roster deletes it.
    @Test("The reader is recognized by their own record in the container")
    func recognizesTheReaderByTheirRecord() {
        #expect(ShareParticipants.isTheReader(record: "_abc", isOwner: false, isOwnShare: false, me: "_abc"))
        #expect(!ShareParticipants.isTheReader(record: "_def", isOwner: false, isOwnShare: false, me: "_abc"))
    }

    /// The name CloudKit uses for whoever is asking rather than for anybody in
    /// particular, which is what it hands back in a share of the reader's own.
    @Test("The reader is recognized under the name CloudKit gives the asker")
    func recognizesTheDefaultOwner() {
        #expect(
            ShareParticipants.isTheReader(
                record: CKCurrentUserDefaultName,
                isOwner: true,
                isOwnShare: true,
                me: "_abc"
            )
        )
    }

    /// True whether or not the container answered who they are, which is what
    /// makes it worth having as well as the other two.
    @Test("The owner of a share in the reader's own database is the reader")
    func recognizesTheOwnerOfTheirOwnShare() {
        #expect(ShareParticipants.isTheReader(record: nil, isOwner: true, isOwnShare: true, me: nil))
        // Somebody else's share : its owner is somebody else.
        #expect(!ShareParticipants.isTheReader(record: "_owner", isOwner: true, isOwnShare: false, me: "_abc"))
        // And a participant in a share of the reader's own is not the reader.
        #expect(!ShareParticipants.isTheReader(record: "_them", isOwner: false, isOwnShare: true, me: "_abc"))
    }

    // MARK: - What stands in for a face

    @Test("Initials are the first letter of the first name and of the last")
    func takesInitials() {
        #expect(ProfilePicture.initials(of: "François Rousselet") == "FR")
        // A telephone number initialled would be a circle with a `3` in it,
        // against a person : nothing is better, and the generic face says
        // `somebody` where a digit says something untrue.
        #expect(ProfilePicture.initials(of: "33695754884") == nil)
        #expect(ProfilePicture.initials(of: "+33 6 95 75 48 84") == nil)
        #expect(ProfilePicture.initials(of: "Ada King Lovelace") == "AL")
        #expect(ProfilePicture.initials(of: "Prince") == "P")
        #expect(ProfilePicture.initials(of: "   ") == nil)
        #expect(ProfilePicture.initials(of: "") == nil)
    }

    /// The card the person wrote first, since that is the name they chose in
    /// this application ; the share's own after ; nothing at all rather than an
    /// identifier nobody can read.
    @Test("A name off a card is preferred to the one the share gives")
    func prefersTheCardsName() {
        var member = ShareMember(zoneName: zone, key: "a", name: "Ada", shareName: "a@example.com")
        #expect(member.displayName == "Ada")
        #expect(member.initials == "A")

        member.name = nil
        #expect(member.displayName == "a@example.com")

        member.shareName = nil
        #expect(member.displayName == nil)
        #expect(member.initials == nil)
    }
}
