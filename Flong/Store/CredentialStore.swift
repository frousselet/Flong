//
//  CredentialStore.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Security

/// Where a secret is kept.
///
/// A protocol so that a test can hold credentials without a keychain : the
/// keychain refuses to answer at all in some test environments, and a suite that
/// cannot run is a suite that says nothing about anything.
nonisolated protocol CredentialStoring: Sendable {
    func credential(for id: UUID) throws -> FeedCredential?
    func setCredential(_ credential: FeedCredential?, for id: UUID) throws
    func identifiers() throws -> Set<UUID>

    /// Which parameters of one feed's addresses the reader said are theirs.
    ///
    /// Beside the credential rather than part of it : a feed authenticated by a
    /// password can still put a subscriber's token on the links inside it, and
    /// a feed with no credential at all can too.
    func secretParameters(for id: UUID) throws -> SecretParameters?
    func setSecretParameters(_ parameters: SecretParameters?, for id: UUID) throws
    /// Every designation there is, for a pass with many feeds to consider.
    ///
    /// Filing a hundred articles into a shared collection touches as many feeds
    /// as they came from, and asking the keychain once per article is asking it
    /// a hundred times for an answer that did not change.
    func everySecretParameter() throws -> [UUID: SecretParameters]

    /// Deletes every secret this application put in there, for a reset.
    func removeEverything() throws
}

/// Why the keychain would not answer.
nonisolated enum CredentialError: Error, Hashable, Sendable {
    /// The keychain refused, with the code it refused by.
    case keychain(OSStatus)
    /// What came back is not what was put in, which means a different version
    /// of the application wrote it.
    case unreadable
}

/// The keychain, which is the only place a secret lives.
///
/// Section 9 of the specification, and section 20 : secrets in the keychain
/// exclusively, propagated between the reader's devices by iCloud Keychain,
/// under the protection class that lets background work read them. Never in the
/// database, never in CloudKit, never in a log.
///
/// **Why `afterFirstUnlock`.** The database is under the same class, for the
/// same reason : a feed refreshed by a background task at four in the morning
/// needs its credential, and a device that has been unlocked once since it
/// booted is a device its owner has proved they are holding. `whenUnlocked`
/// would be stricter and would stop background refresh working at all for
/// exactly the feeds a reader pays for.
///
/// **Why synchronizable.** A reader who has paid once should not have to sign in
/// again on their iPad. iCloud Keychain is Apple's own end-to-end encrypted
/// channel, which is a better place for a password than anything this
/// application could build, and it is what the specification asks for.
nonisolated struct KeychainCredentials: CredentialStoring {
    /// What the keychain files these under.
    static let service = "com.rslt.Flong.credentials"

    private let service: String

    /// Where the designations of ``SecretParameters`` go.
    ///
    /// A service of its own rather than a second field on the credential : the
    /// keychain keys an item by its service and its account, and the account is
    /// already the feed. Two things about one feed are therefore two items, and
    /// a feed may perfectly well have the second without the first.
    private let parameterService: String

    init(service: String = KeychainCredentials.service) {
        self.service = service
        self.parameterService = service + ".parameters"
    }

    func credential(for id: UUID) throws -> FeedCredential? {
        try read(FeedCredential.self, from: service, for: id)
    }

    func setCredential(_ credential: FeedCredential?, for id: UUID) throws {
        try write(credential, to: service, for: id)
    }

    func secretParameters(for id: UUID) throws -> SecretParameters? {
        try read(SecretParameters.self, from: parameterService, for: id)
    }

    func setSecretParameters(_ parameters: SecretParameters?, for id: UUID) throws {
        // A designation of nothing is no designation, so it is deleted rather
        // than stored as an empty set nobody would ever read as absent.
        try write((parameters?.isEmpty ?? true) ? nil : parameters, to: parameterService, for: id)
    }

    func everySecretParameter() throws -> [UUID: SecretParameters] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: parameterService,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            let items = result as? [[String: Any]] ?? []
            return items.reduce(into: [:]) { found, item in
                guard let account = item[kSecAttrAccount as String] as? String,
                    let id = UUID(uuidString: account),
                    let data = item[kSecValueData as String] as? Data,
                    let parameters = try? JSONDecoder().decode(SecretParameters.self, from: data)
                else { return }
                found[id] = parameters
            }
        case errSecItemNotFound:
            return [:]
        default:
            throw CredentialError.keychain(status)
        }
    }

    // MARK: - The keychain itself

    private func read<Value: Decodable>(_ type: Value.Type, from service: String, for id: UUID) throws -> Value? {
        var query = baseQuery(for: id, in: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw CredentialError.unreadable }
            guard let value = try? JSONDecoder().decode(Value.self, from: data) else {
                throw CredentialError.unreadable
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialError.keychain(status)
        }
    }

    private func write(_ value: (some Encodable)?, to service: String, for id: UUID) throws {
        guard let value else {
            let status = SecItemDelete(baseQuery(for: id, in: service) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialError.keychain(status)
            }
            return
        }

        let data = try JSONEncoder().encode(value)
        let update = [kSecValueData as String: data]

        let updated = SecItemUpdate(baseQuery(for: id, in: service) as CFDictionary, update as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw CredentialError.keychain(updated) }

        var item = baseQuery(for: id, in: service)
        item[kSecValueData as String] = data
        // The class that lets a background refresh read it : see the note above.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw CredentialError.keychain(added) }
    }

    /// Which subscriptions have a credential, without reading any of them.
    ///
    /// The interface needs to know that a feed is authenticated in order to say
    /// so, and knowing that is not the same as holding the secret.
    func identifiers() throws -> Set<UUID> {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        query[kSecReturnData as String] = false

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            let items = result as? [[String: Any]] ?? []
            return Set(items.compactMap { ($0[kSecAttrAccount as String] as? String).flatMap(UUID.init(uuidString:)) })
        case errSecItemNotFound:
            return []
        default:
            throw CredentialError.keychain(status)
        }
    }

    /// Deletes every credential Flong holds, whichever feed it belonged to.
    ///
    /// By service rather than feed by feed, so a secret whose subscription is
    /// already gone goes with the rest : a reset that left an orphan behind
    /// would leave the one thing section 20 is most careful about.
    ///
    /// **Both services**, since the designations are secrets of a kind too : a
    /// list of exactly which parameters carry a subscription is worth having if
    /// you are looking for one, and a reset that emptied everything else and
    /// left it behind would have missed the point.
    func removeEverything() throws {
        for service in [service, parameterService] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ]

            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialError.keychain(status)
            }
        }
    }

    private func baseQuery(for id: UUID, in service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            // Carried to the reader's other devices by iCloud Keychain, which
            // is end-to-end encrypted and is not this application's to reinvent.
            kSecAttrSynchronizable as String: true,
        ]
    }
}

/// Credentials held for the length of a test, and nowhere else.
nonisolated final class MemoryCredentials: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: [UUID: FeedCredential] = [:]
    private var parameters: [UUID: SecretParameters] = [:]

    init() {}

    func credential(for id: UUID) throws -> FeedCredential? {
        lock.withLock { credentials[id] }
    }

    func setCredential(_ credential: FeedCredential?, for id: UUID) throws {
        lock.withLock { credentials[id] = credential }
    }

    func identifiers() throws -> Set<UUID> {
        lock.withLock { Set(credentials.keys) }
    }

    func secretParameters(for id: UUID) throws -> SecretParameters? {
        lock.withLock { parameters[id] }
    }

    func setSecretParameters(_ parameters: SecretParameters?, for id: UUID) throws {
        lock.withLock { self.parameters[id] = (parameters?.isEmpty ?? true) ? nil : parameters }
    }

    func everySecretParameter() throws -> [UUID: SecretParameters] {
        lock.withLock { parameters }
    }

    func removeEverything() throws {
        lock.withLock {
            credentials.removeAll()
            parameters.removeAll()
        }
    }
}
