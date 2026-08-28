//
//  GReaderError.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

nonisolated enum GReaderError: Error, LocalizedError, Equatable {
    case invalidServerURL
    case notAuthenticated
    case badCredentials
    case missingAuthToken
    case http(status: Int, body: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            String(localized: "The server address is not valid.")
        case .notAuthenticated:
            String(localized: "Session expired, please sign in again.")
        case .badCredentials:
            String(localized: "The server rejected this username or API password.")
        case .missingAuthToken:
            String(localized: "The server did not return an authentication token.")
        case .http(let status, _):
            String(localized: "The server replied with error \(status).")
        case .decoding(let detail):
            String(localized: "Unreadable server response: \(detail)")
        }
    }

    /// True when the error warrants opening a fresh session and replaying.
    var requiresReauthentication: Bool {
        switch self {
        case .notAuthenticated, .badCredentials: true
        case .http(let status, _): status == 401 || status == 403
        default: false
        }
    }
}
