//
//  CredentialStore.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Persistence for the account credentials and the session token.
///
/// The two are deliberately separate : credentials belong on every device of the
/// Apple Account, while the session token is a cache that each device can rebuild
/// on its own from the credentials.
nonisolated protocol CredentialStore: Sendable {
    func loadCredentials() throws -> StoredCredentials?
    @discardableResult
    func saveCredentials(_ credentials: Credentials) throws -> CredentialStorage

    func loadSessionToken() throws -> String?
    func saveSessionToken(_ token: String?) throws

    /// Removes the credentials and the session token.
    func clear() throws
}

/// In-memory implementation, for tests and previews.
nonisolated final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: Credentials?
    private var token: String?

    let storage: CredentialStorage

    init(credentials: Credentials? = nil, storage: CredentialStorage = .syncedAcrossDevices) {
        self.credentials = credentials
        self.storage = storage
    }

    func loadCredentials() throws -> StoredCredentials? {
        lock.withLock {
            credentials.map { StoredCredentials(credentials: $0, storage: storage) }
        }
    }

    @discardableResult
    func saveCredentials(_ credentials: Credentials) throws -> CredentialStorage {
        lock.withLock {
            self.credentials = credentials
            return storage
        }
    }

    func loadSessionToken() throws -> String? {
        lock.withLock { token }
    }

    func saveSessionToken(_ token: String?) throws {
        lock.withLock { self.token = token }
    }

    func clear() throws {
        lock.withLock {
            credentials = nil
            token = nil
        }
    }
}
