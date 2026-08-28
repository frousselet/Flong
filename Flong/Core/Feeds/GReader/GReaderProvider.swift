//
//  GReaderProvider.swift
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

nonisolated struct GReaderCredentials: Sendable {
    let username: String
    /// FreshRSS API password, set under Profile and distinct from the web password.
    let password: String
}

/// `FeedProvider` backed by the Google Reader API of a FreshRSS instance.
///
/// Every operation makes sure a session is open, and replays the request once
/// after signing in again when the server rejects the token.
nonisolated final class GReaderProvider: FeedProvider {
    /// Article identifiers sent per `edit-tag` call.
    ///
    /// The endpoint repeats the `i` field once per article, and PHP drops input
    /// fields beyond `max_input_vars`, which defaults to 1000. Batching well
    /// below that keeps a large selection from being silently truncated.
    private static let editBatchSize = 100

    /// Ceiling applied to the `n` parameter. The server defaults to 20 when it
    /// is absent and imposes no maximum of its own.
    private static let maxPageSize = 1000

    private let client: GReaderClient
    private let credentials: GReaderCredentials
    private let tokenDidChange: (@Sendable (String) -> Void)?

    init(
        serverURL: URL,
        credentials: GReaderCredentials,
        authToken: String? = nil,
        session: URLSession = .shared,
        tokenDidChange: (@Sendable (String) -> Void)? = nil
    ) {
        self.client = GReaderClient(baseURL: serverURL, session: session, authToken: authToken)
        self.credentials = credentials
        self.tokenDidChange = tokenDidChange
    }

    /// Injects a client directly, for tests.
    init(
        client: GReaderClient,
        credentials: GReaderCredentials,
        tokenDidChange: (@Sendable (String) -> Void)? = nil
    ) {
        self.client = client
        self.credentials = credentials
        self.tokenDidChange = tokenDidChange
    }

    // MARK: - Session

    @discardableResult
    func signIn() async throws -> String {
        let token = try await client.clientLogin(email: credentials.username, password: credentials.password)
        tokenDidChange?(token)
        return token
    }

    /// Runs an operation against a live session, replaying it once if the server refuses the token.
    @discardableResult
    private func authenticated<T>(_ operation: () async throws -> T) async throws -> T {
        if await client.currentAuthToken == nil {
            try await signIn()
        }
        do {
            return try await operation()
        } catch let error as GReaderError where error.requiresReauthentication {
            Log.auth.info("Token refused, signing in again")
            try await signIn()
            return try await operation()
        }
    }

    private static let jsonOutput = URLQueryItem(name: "output", value: "json")

    // MARK: - Reading

    func folders() async throws -> [RemoteFolder] {
        let list = try await authenticated {
            try await client.get("reader/api/0/tag/list", query: [Self.jsonOutput], as: GReaderDTO.TagList.self)
        }
        return Self.mapFolders(list.tags)
    }

    func feeds() async throws -> [RemoteFeed] {
        let list = try await authenticated {
            try await client.get(
                "reader/api/0/subscription/list",
                query: [Self.jsonOutput],
                as: GReaderDTO.SubscriptionList.self
            )
        }
        return list.subscriptions.map(Self.mapFeed)
    }

    func unreadCounts() async throws -> [String: Int] {
        let list = try await authenticated {
            try await client.get(
                "reader/api/0/unread-count",
                query: [Self.jsonOutput],
                as: GReaderDTO.UnreadCountList.self
            )
        }
        return Dictionary(list.unreadcounts.map { ($0.id, $0.count.value) }, uniquingKeysWith: { _, last in last })
    }

    func articles(
        in stream: StreamSelector,
        unreadOnly: Bool,
        limit: Int,
        continuation: String?
    ) async throws -> ArticlePage {
        let path = "reader/api/0/stream/contents/" + GReaderStreamID.pathComponents(for: stream)

        var query = [
            Self.jsonOutput,
            URLQueryItem(name: "n", value: String(min(max(limit, 1), Self.maxPageSize))),
        ]
        if unreadOnly {
            query.append(URLQueryItem(name: "xt", value: GReaderStreamID.read))
        }
        // The server ignores a continuation that is not all digits, so a stray
        // value silently restarts the stream rather than failing loudly.
        if let continuation, !continuation.isEmpty, continuation.allSatisfy(\.isNumber) {
            query.append(URLQueryItem(name: "c", value: continuation))
        }

        let contents = try await authenticated {
            try await client.get(path, query: query, as: GReaderDTO.StreamContents.self)
        }
        return ArticlePage(articles: contents.items.map(Self.mapArticle), continuation: contents.continuation)
    }

    // MARK: - Writing

    func setRead(_ isRead: Bool, articleIDs: [String]) async throws {
        try await editTag(GReaderStreamID.read, add: isRead, articleIDs: articleIDs)
    }

    func setStarred(_ isStarred: Bool, articleIDs: [String]) async throws {
        try await editTag(GReaderStreamID.starred, add: isStarred, articleIDs: articleIDs)
    }

    /// Marks a whole stream as read up to `date`.
    ///
    /// `ts` is compared against article identifiers, which FreshRSS derives from
    /// the insertion date in microseconds (`WHERE id <= ?`). Sending any other
    /// unit marks the wrong set : nanoseconds would mark the entire account.
    func markAllRead(in stream: StreamSelector, olderThan date: Date) async throws {
        let microseconds = Int(date.timeIntervalSince1970 * 1_000_000)
        try await authenticated {
            try await client.post(
                "reader/api/0/mark-all-as-read",
                form: [
                    ("s", GReaderStreamID.value(for: stream)),
                    ("ts", String(microseconds)),
                ]
            )
        }
    }

    private func editTag(_ tag: String, add: Bool, articleIDs: [String]) async throws {
        guard !articleIDs.isEmpty else { return }

        for batch in articleIDs.chunked(into: Self.editBatchSize) {
            var form: [(String, String)] = batch.map { ("i", $0) }
            form.append((add ? "a" : "r", tag))
            try await authenticated {
                try await client.post("reader/api/0/edit-tag", form: form)
            }
        }
    }

    // MARK: - Wire to model

    /// Keeps the folders out of `tag/list`.
    ///
    /// The reply mixes three kinds of entry : the built-in states, which carry no
    /// `type`, the folders, typed `folder`, and the article labels, typed `tag`.
    /// Folders and labels share the `user/-/label/` prefix, so the type is the
    /// only thing separating them.
    static func mapFolders(_ tags: [GReaderDTO.Tag]) -> [RemoteFolder] {
        tags.compactMap { tag in
            guard tag.type == "folder", let name = GReaderStreamID.folderName(fromID: tag.id) else { return nil }
            return RemoteFolder(id: tag.id, name: name)
        }
    }

    static func mapFeed(_ subscription: GReaderDTO.Subscription) -> RemoteFeed {
        RemoteFeed(
            id: subscription.id,
            title: subscription.title?.nonEmpty ?? subscription.htmlUrl?.nonEmpty ?? subscription.id,
            feedURL: subscription.url?.nonEmpty.flatMap(URL.init(string:)),
            siteURL: subscription.htmlUrl?.nonEmpty.flatMap(URL.init(string:)),
            iconURL: subscription.iconUrl?.nonEmpty.flatMap(URL.init(string:)),
            folderIDs: subscription.categories?.map(\.id) ?? []
        )
    }

    static func mapArticle(_ item: GReaderDTO.Item) -> RemoteArticle {
        let states = item.categories ?? []
        let link = (item.canonical ?? []).first?.href ?? (item.alternate ?? []).first?.href

        return RemoteArticle(
            id: item.id,
            feedID: item.origin?.streamId ?? "",
            title: item.title?.nonEmpty ?? "",
            author: item.author?.nonEmpty,
            // FreshRSS serializes in compatibility mode and fills `summary` only,
            // while other servers put the full body in `content`.
            summary: item.content?.content ?? item.summary?.content ?? "",
            url: link?.nonEmpty.flatMap(URL.init(string:)),
            published: Self.publishedDate(for: item),
            isRead: states.contains(GReaderStreamID.read),
            isStarred: states.contains(GReaderStreamID.starred)
        )
    }

    /// `published` is in seconds. The crawl dates are the fallbacks, in
    /// microseconds and milliseconds respectively, and FreshRSS omits `updated`.
    private static func publishedDate(for item: GReaderDTO.Item) -> Date {
        if let seconds = item.published?.value ?? item.updated?.value {
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        if let microseconds = item.timestampUsec.flatMap(Int.init) {
            return Date(timeIntervalSince1970: TimeInterval(microseconds) / 1_000_000)
        }
        if let milliseconds = item.crawlTimeMsec.flatMap(Int.init) {
            return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        }
        return .distantPast
    }
}

nonisolated extension String {
    /// `nil` when the string is empty once trimmed.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
