//
//  AddressBook.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Contacts
import Foundation
import OSLog

/// What the reader's own address book calls somebody, and what face it has for
/// them.
///
/// **The one question CloudKit cannot answer.** A person invited to a
/// collection and who has not accepted yet has no identity for the system to
/// resolve : `CKUserIdentity` gives no name components and no picture, and all
/// the share carries is the address the invitation went to. Drawn as it comes,
/// that is a bare telephone number with a digit for an initial, against a
/// person the reader knows perfectly well.
///
/// They know them because the number is in their address book, under a name and
/// often under a face. So that is where it is asked.
///
/// **It is theirs, it stays here, and it never travels.** What is found is
/// written into columns of its own, beside the share's half and the card's
/// half : it is never put into anybody's card, never sent to a zone, and never
/// shown to another participant, who has their own address book or nothing. A
/// name out of somebody's contacts is a fact about them and not about the
/// person they have filed.
///
/// **Asked for at the moment it is needed and at no other.** Not at launch, not
/// on the chance it might help : only when a collection actually holds somebody
/// this device cannot name, which is the one moment the reader can see what the
/// question is for. Refusing costs them the name and nothing else, and the
/// address stands where the name would have been.
///
/// **Limited access is a full answer.** iOS lets a reader grant a few contacts
/// rather than the book, and the lookup then finds those and not the others,
/// which is exactly right : nothing here needs the book, it needs the person.
nonisolated enum AddressBook {
    /// Whether the reader has let this application look anybody up.
    static var isAllowed: Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: true
        default: false
        }
    }

    /// Whether the question has never been put to them.
    static var mayAsk: Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .notDetermined
    }

    /// Puts the question, once.
    ///
    /// The system asks at most once for the life of the installation, whatever
    /// this is called ; after that it answers from what the reader decided.
    @discardableResult
    static func ask() async -> Bool {
        guard mayAsk else { return isAllowed }
        return (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
    }

    /// Who the reader has filed at each of these addresses.
    ///
    /// Keyed by whatever the caller keyed the addresses by, so the answer lands
    /// back on the right row without this knowing what a row is.
    ///
    /// An address with nobody behind it is simply absent from the answer, which
    /// is not a failure : plenty of people are invited at an address their
    /// inviter never wrote down.
    static func people(at addresses: [String: String]) async -> [String: Person] {
        guard isAllowed, !addresses.isEmpty else { return [:] }

        let store = CNContactStore()
        let keys =
            [
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                CNContactThumbnailImageDataKey as CNKeyDescriptor,
            ]

        var found: [String: Person] = [:]
        for (key, address) in addresses {
            guard let contact = contact(at: address, in: store, keys: keys) else { continue }

            let name = CNContactFormatter.string(from: contact, style: .fullName)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Through the same scaling a picture of the reader's own goes
            // through : it is drawn at the size a face is drawn at, and what
            // the address book hands over is not bounded by anything here.
            let picture = contact.thumbnailImageData.flatMap(ProfilePicture.scaled)

            guard name?.isEmpty == false || picture != nil else { continue }
            found[key] = Person(name: name?.isEmpty == false ? name : nil, picture: picture)
        }

        return found
    }

    /// One person, at an address that is either an email or a telephone number.
    ///
    /// Which of the two it is decided by the shape of it rather than asked of
    /// the caller : the share says `emailAddress` or `phoneNumber` and both
    /// arrive here as text, so an `@` is the whole of the test and there is
    /// nothing else it could be.
    private static func contact(at address: String, in store: CNContactStore, keys: [CNKeyDescriptor]) -> CNContact? {
        let predicate =
            address.contains("@")
            ? CNContact.predicateForContacts(matchingEmailAddress: address)
            : CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: address))

        do {
            return try store.unifiedContacts(matching: predicate, keysToFetch: keys).first
        } catch {
            // A refusal, or a book that would not open. Neither is worth
            // telling the reader about : they lose a name and keep the address.
            Log.store.notice("An address could not be looked up in the contacts")
            return nil
        }
    }

    /// What the address book had to say about one person.
    nonisolated struct Person: Hashable, Sendable {
        var name: String?
        var picture: Data?
    }
}
