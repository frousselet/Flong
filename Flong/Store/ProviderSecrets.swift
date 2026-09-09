//
//  ProviderSecrets.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Security

/// What a model of the reader's own needs in order to answer, and which never
/// leaves the keychain.
nonisolated struct ProviderSecret: Hashable, Sendable, Codable {
    /// The key the reader pasted.
    ///
    /// Empty for a server that asks for none, which is a real case and not a
    /// missing value : a model server on the reader's own network
    /// authenticates nobody.
    var key: String

    /// The whole address, path and query included, where the reader said the
    /// address is itself a secret. Nothing where it is in the open and the
    /// account holds it.
    var endpoint: URL?

    /// The values of the headers whose names the account holds.
    var headers: [String: String]

    init(key: String = "", endpoint: URL? = nil, headers: [String: String] = [:]) {
        self.key = key
        self.endpoint = endpoint
        self.headers = headers
    }

    var isEmpty: Bool { key.isEmpty && endpoint == nil && headers.isEmpty }
}

/// Where a provider's key is kept, which is the keychain and nowhere else.
///
/// A protocol so that a test can hold one without a keychain : the keychain
/// refuses to answer at all in some test environments, and a suite that cannot
/// run is a suite that says nothing about anything.
nonisolated protocol ProviderSecretStoring: Sendable {
    func secret(for id: UUID) throws -> ProviderSecret?
    func setSecret(_ secret: ProviderSecret?, for id: UUID) throws
    /// Which providers have something in here, without reading any of it.
    ///
    /// The interface has to say that a provider is configured, and knowing that
    /// is not the same as holding the key.
    func identifiers() throws -> Set<UUID>
    /// Deletes every provider key Flong holds, for a reset.
    func removeEverything() throws
}

/// The keychain, keyed by the provider's own identifier.
///
/// Section 20 : secrets in the keychain exclusively, never the database, never
/// the key-value store, never a log, never an error message, never an export.
///
/// **Why `afterFirstUnlock`.** The same reason a feed credential is under it :
/// the night's pass writes a page while the device is locked, and a key that
/// could not be read then would be a provider that only answers while the
/// reader is watching, which is an empty front page every morning.
///
/// **Why synchronizable.** The accounts themselves travel through the reader's
/// key-value store, so a key that did not travel with them would leave the iPad
/// holding an account it cannot use : a row that looks configured and fails on
/// every call, which is worse than either honest state.
nonisolated struct KeychainProviderSecrets: ProviderSecretStoring {
    /// What the keychain files these under. A service of its own : this is not
    /// a feed credential and a reset has to be able to name it separately.
    static let service = "com.rslt.Flong.providers"

    private let service: String

    init(service: String = KeychainProviderSecrets.service) {
        self.service = service
    }

    func secret(for id: UUID) throws -> ProviderSecret? {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw CredentialError.unreadable }
            guard let secret = try? JSONDecoder().decode(ProviderSecret.self, from: data) else {
                throw CredentialError.unreadable
            }
            return secret
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialError.keychain(status)
        }
    }

    func setSecret(_ secret: ProviderSecret?, for id: UUID) throws {
        // A secret with nothing in it is no secret, so it is deleted rather
        // than stored as an empty one nobody would read as absent.
        guard let secret, !secret.isEmpty else {
            let status = SecItemDelete(baseQuery(for: id) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialError.keychain(status)
            }
            return
        }

        let data = try JSONEncoder().encode(secret)
        let updated = SecItemUpdate(
            baseQuery(for: id) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw CredentialError.keychain(updated) }

        var item = baseQuery(for: id)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw CredentialError.keychain(added) }
    }

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

    /// Deletes every provider key, by service rather than one by one, so a key
    /// whose account is already gone goes with the rest.
    func removeEverything() throws {
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

    private func baseQuery(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            // Carried to the reader's other devices by iCloud Keychain, which
            // is end-to-end encrypted and is not this application's to
            // reinvent.
            kSecAttrSynchronizable as String: true,
        ]
    }
}

/// Provider keys held for the length of a test, and nowhere else.
nonisolated final class MemoryProviderSecrets: ProviderSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [UUID: ProviderSecret] = [:]

    init() {}

    func secret(for id: UUID) throws -> ProviderSecret? {
        lock.withLock { secrets[id] }
    }

    func setSecret(_ secret: ProviderSecret?, for id: UUID) throws {
        lock.withLock { secrets[id] = (secret?.isEmpty ?? true) ? nil : secret }
    }

    func identifiers() throws -> Set<UUID> {
        lock.withLock { Set(secrets.keys) }
    }

    func removeEverything() throws {
        lock.withLock { secrets.removeAll() }
    }
}
