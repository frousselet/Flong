//
//  SessionModel.swift
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

/// Holds the signed-in account and the provider built from it.
///
/// Credentials are checked against the server before they are stored, so a
/// saved account is always one that worked at least once.
@MainActor
@Observable
final class SessionModel {
    nonisolated struct Account: Equatable, Sendable {
        let serverURL: URL
        let username: String
    }

    enum State: Equatable {
        case restoring
        case signedOut
        case signedIn(account: Account, storage: CredentialStorage)
    }

    private(set) var state: State = .restoring
    private(set) var isSigningIn = false
    private(set) var signInError: String?
    private(set) var provider: (any FeedProvider)?

    private let store: any CredentialStore
    private let urlSession: URLSession

    /// - Parameter urlSession: injected so tests can drive the real provider
    ///   against a stubbed server rather than a mock of the provider itself.
    init(store: any CredentialStore = KeychainCredentialStore(), urlSession: URLSession = .shared) {
        self.store = store
        self.urlSession = urlSession
        restore()
    }

    var account: Account? {
        if case .signedIn(let account, _) = state { return account }
        return nil
    }

    var storage: CredentialStorage? {
        if case .signedIn(_, let storage) = state { return storage }
        return nil
    }

    // MARK: - Lifecycle

    /// Rebuilds the session from the keychain at launch.
    func restore() {
        do {
            guard let stored = try store.loadCredentials() else {
                state = .signedOut
                return
            }
            let token = try? store.loadSessionToken()
            provider = makeProvider(for: stored.credentials, authToken: token)
            state = .signedIn(account: Self.account(from: stored.credentials), storage: stored.storage)
        } catch {
            Log.auth.error("Stored credentials could not be read: \(error.localizedDescription)")
            state = .signedOut
        }
    }

    /// Validates the credentials against the server, then stores them.
    func signIn(server: String, username: String, password: String) async {
        guard let serverURL = ServerAddress.normalized(from: server) else {
            signInError = String(localized: "This address cannot be read as a server URL.")
            return
        }

        signInError = nil
        isSigningIn = true
        defer { isSigningIn = false }

        let credentials = Credentials(serverURL: serverURL, username: username, password: password)
        let provider = makeProvider(for: credentials, authToken: nil)

        do {
            let token = try await provider.signIn()
            let storage = try store.saveCredentials(credentials)
            try store.saveSessionToken(token)

            self.provider = provider
            state = .signedIn(account: Self.account(from: credentials), storage: storage)
        } catch {
            Log.auth.info("Sign in refused")
            signInError = error.localizedDescription
        }
    }

    func signOut() {
        do {
            try store.clear()
        } catch {
            Log.auth.error("Stored credentials could not be cleared: \(error.localizedDescription)")
        }
        provider = nil
        signInError = nil
        state = .signedOut
    }

    func dismissSignInError() {
        signInError = nil
    }

    // MARK: - Wiring

    private func makeProvider(for credentials: Credentials, authToken: String?) -> any FeedProvider {
        // `store` is an immutable Sendable property, so the renewal callback can
        // reach it from whatever context the provider calls back on.
        let store = self.store
        return GReaderProvider(
            serverURL: credentials.serverURL,
            credentials: GReaderCredentials(username: credentials.username, password: credentials.password),
            authToken: authToken,
            session: urlSession,
            tokenDidChange: { token in try? store.saveSessionToken(token) }
        )
    }

    private static func account(from credentials: Credentials) -> Account {
        Account(serverURL: credentials.serverURL, username: credentials.username)
    }
}
