//
//  FeedProvider.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// A folder of subscriptions.
nonisolated struct RemoteFolder: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

/// A feed the account subscribes to.
nonisolated struct RemoteFeed: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let feedURL: URL?
    let siteURL: URL?
    let iconURL: URL?
    let folderIDs: [String]
}

/// An article. `summary` holds HTML as served by the backend.
nonisolated struct RemoteArticle: Identifiable, Hashable, Sendable {
    let id: String
    let feedID: String
    let title: String
    let author: String?
    let summary: String
    let url: URL?
    let published: Date
    let isRead: Bool
    let isStarred: Bool
}

/// A page of articles. `continuation` feeds the next request when present.
nonisolated struct ArticlePage: Sendable {
    let articles: [RemoteArticle]
    let continuation: String?
}

/// The logical stream to read from.
nonisolated enum StreamSelector: Hashable, Sendable {
    case all
    case starred
    case folder(id: String)
    case feed(id: String)
}

/// Contract a reading service must fulfil.
///
/// FreshRSS fulfils it through `GReaderProvider`. Nothing above this protocol may
/// reference a backend type, so a second service plugs in without touching the
/// data layer or the interface.
nonisolated protocol FeedProvider: Sendable {
    /// Opens a session and returns the token to cache for later launches.
    @discardableResult
    func signIn() async throws -> String

    func folders() async throws -> [RemoteFolder]
    func feeds() async throws -> [RemoteFeed]

    /// Unread counts, keyed by feed or folder identifier.
    func unreadCounts() async throws -> [String: Int]

    func articles(
        in stream: StreamSelector,
        unreadOnly: Bool,
        limit: Int,
        continuation: String?
    ) async throws -> ArticlePage

    func setRead(_ isRead: Bool, articleIDs: [String]) async throws
    func setStarred(_ isStarred: Bool, articleIDs: [String]) async throws
    func markAllRead(in stream: StreamSelector, olderThan date: Date) async throws
}
