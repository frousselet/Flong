//
//  Credentials.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// What is needed to open a session on an instance.
///
/// The description is redacted on purpose : these values end up in error paths
/// and logs, and the API password must never appear there.
nonisolated struct Credentials: Codable, Hashable, Sendable, CustomStringConvertible {
    var serverURL: URL
    var username: String
    /// FreshRSS API password, set under Profile and distinct from the web password.
    var password: String

    init(serverURL: URL, username: String, password: String) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
    }

    var description: String {
        "Credentials(serverURL: \(serverURL.absoluteString), username: \(username), password: <redacted>)"
    }
}

/// How far the stored credentials actually reach.
nonisolated enum CredentialStorage: Sendable, Equatable {
    /// Written to the synchronizable keychain, which iCloud Keychain carries to
    /// the other devices of the same Apple Account.
    case syncedAcrossDevices
    /// Written to the local keychain only, because the synchronizable one was
    /// refused. A build without the keychain entitlement lands here.
    case thisDeviceOnly
}

nonisolated struct StoredCredentials: Sendable, Equatable {
    let credentials: Credentials
    let storage: CredentialStorage
}
