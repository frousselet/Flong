//
//  KeychainCredentialStore.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import OSLog
import Security

/// Keychain storage, with the credentials shared across the devices of one Apple Account.
///
/// Two flags carry that : `kSecAttrSynchronizable`, which hands the item to
/// iCloud Keychain, and `kSecUseDataProtectionKeychain`, which is what selects
/// the modern keychain on macOS. Without the second, macOS reaches for its
/// legacy file-based keychain, which never syncs.
///
/// Both require the `keychain-access-groups` entitlement, which in turn needs a
/// provisioning profile. A build without one is refused with
/// `errSecMissingEntitlement`, so the store falls back to the local keychain
/// rather than leaving the app unusable, and reports which one it used.
///
/// Sync also depends on iCloud Keychain being switched on for the account.
/// Nothing in the API reports that, so `syncedAcrossDevices` means the item was
/// handed to iCloud Keychain, not that it has landed elsewhere yet.
nonisolated struct KeychainCredentialStore: CredentialStore {
    enum Failure: Error, LocalizedError, Equatable {
        case unexpectedStatus(OSStatus)
        case unreadableItem

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                String(localized: "Keychain error \(status).")
            case .unreadableItem:
                String(localized: "The credentials stored in the keychain could not be read.")
            }
        }
    }

    private static let credentialsAccount = "credentials"
    private static let sessionTokenAccount = "sessionToken"

    let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.rslt.Flong") {
        self.service = service
    }

    // MARK: - Credentials

    func loadCredentials() throws -> StoredCredentials? {
        // A device that synced earlier holds the item in the synchronizable
        // keychain; one that fell back holds it locally. Look in both.
        for storage in [CredentialStorage.syncedAcrossDevices, .thisDeviceOnly] {
            guard let data = try read(account: Self.credentialsAccount, storage: storage) else { continue }
            do {
                let credentials = try JSONDecoder().decode(Credentials.self, from: data)
                return StoredCredentials(credentials: credentials, storage: storage)
            } catch {
                throw Failure.unreadableItem
            }
        }
        return nil
    }

    @discardableResult
    func saveCredentials(_ credentials: Credentials) throws -> CredentialStorage {
        let data = try JSONEncoder().encode(credentials)

        do {
            try write(data, account: Self.credentialsAccount, storage: .syncedAcrossDevices)
            // Drop any copy left by an earlier fallback, so the two cannot diverge.
            try? delete(account: Self.credentialsAccount, storage: .thisDeviceOnly)
            return .syncedAcrossDevices
        } catch Failure.unexpectedStatus(errSecMissingEntitlement) {
            Log.auth.warning("Synchronizable keychain refused, storing credentials on this device only")
            try write(data, account: Self.credentialsAccount, storage: .thisDeviceOnly)
            return .thisDeviceOnly
        }
    }

    // MARK: - Session token

    /// The token is a cache, rebuildable from the credentials, so it stays on the
    /// device rather than travelling to the others.
    func loadSessionToken() throws -> String? {
        guard let data = try read(account: Self.sessionTokenAccount, storage: .thisDeviceOnly) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveSessionToken(_ token: String?) throws {
        guard let token else {
            try delete(account: Self.sessionTokenAccount, storage: .thisDeviceOnly)
            return
        }
        try write(Data(token.utf8), account: Self.sessionTokenAccount, storage: .thisDeviceOnly)
    }

    func clear() throws {
        try delete(account: Self.credentialsAccount, storage: .syncedAcrossDevices)
        try delete(account: Self.credentialsAccount, storage: .thisDeviceOnly)
        try delete(account: Self.sessionTokenAccount, storage: .thisDeviceOnly)
    }

    // MARK: - Keychain

    private func read(account: String, storage: CredentialStorage) throws -> Data? {
        var query = baseQuery(account: account, storage: storage)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw Failure.unreadableItem }
            return data
        case errSecItemNotFound, errSecMissingEntitlement:
            return nil
        default:
            throw Failure.unexpectedStatus(status)
        }
    }

    private func write(_ data: Data, account: String, storage: CredentialStorage) throws {
        let query = baseQuery(account: account, storage: storage)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)

        switch update {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = query
            insert[kSecValueData as String] = data
            // A synchronizable item cannot use a ThisDeviceOnly protection class.
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let add = SecItemAdd(insert as CFDictionary, nil)
            guard add == errSecSuccess else { throw Failure.unexpectedStatus(add) }
        default:
            throw Failure.unexpectedStatus(update)
        }
    }

    private func delete(account: String, storage: CredentialStorage) throws {
        let status = SecItemDelete(baseQuery(account: account, storage: storage) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound, errSecMissingEntitlement:
            return
        default:
            throw Failure.unexpectedStatus(status)
        }
    }

    /// Every operation must carry the same flags : a query that omits
    /// `kSecAttrSynchronizable` only ever matches non-synchronizable items.
    private func baseQuery(account: String, storage: CredentialStorage) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: storage == .syncedAcrossDevices,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
