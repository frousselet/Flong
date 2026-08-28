//
//  ProbeModel.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Exercises the Google Reader layer against a live instance and reports what
/// each endpoint answered.
///
/// This is a bench, not a feature : it exists so the client can be verified
/// against a real server before any of the app is built on top of it. Read
/// checks always run; the write check is opt-in because it touches the account,
/// and it puts back what it changed.
@MainActor
@Observable
final class ProbeModel {
    private static let serverKey = "flong.probe.server"
    private static let usernameKey = "flong.probe.username"

    /// Articles pulled when looking for one to flip during the write check.
    private static let writeCheckWindow = 50

    var server: String
    var username: String
    /// Kept in memory only, never written anywhere.
    var password = ""
    var includesWriteCheck = false

    private(set) var checks: [ProbeCheck] = []
    private(set) var isRunning = false
    private(set) var addressError: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.server = defaults.string(forKey: Self.serverKey) ?? ""
        self.username = defaults.string(forKey: Self.usernameKey) ?? ""
    }

    var canRun: Bool {
        !isRunning
            && !server.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
    }

    var failureCount: Int { checks.filter(\.isFailure).count }

    var hasRun: Bool { !checks.isEmpty }

    // MARK: - Run

    func run() async {
        guard let serverURL = ServerAddress.normalized(from: server) else {
            addressError = String(localized: "This address cannot be read as a server URL.")
            return
        }

        addressError = nil
        isRunning = true
        checks = Self.makeChecks(includesWrite: includesWriteCheck)
        defer { isRunning = false }

        // The address and the username come back on the next launch. The
        // password does not, deliberately.
        defaults.set(server, forKey: Self.serverKey)
        defaults.set(username, forKey: Self.usernameKey)

        let provider = GReaderProvider(
            serverURL: serverURL,
            credentials: GReaderCredentials(username: username, password: password)
        )

        guard await runReadChecks(with: provider) else { return }
        if includesWriteCheck {
            await runWriteCheck(with: provider)
        }
    }

    /// - Returns: false when signing in failed, which makes every later check moot.
    private func runReadChecks(with provider: GReaderProvider) async -> Bool {
        let signedIn = await perform("signIn") {
            let token = try await provider.signIn()
            return String(localized: "Session opened, token of \(token.count) characters")
        }
        guard signedIn else {
            skipRemaining(after: "signIn")
            return false
        }

        await perform("folders") {
            let folders = try await provider.folders()
            let names = folders.prefix(3).map(\.name).joined(separator: ", ")
            return Self.summary(count: folders.count, sample: names)
        }

        let feeds = await perform("feeds") {
            let feeds = try await provider.feeds()
            let titles = feeds.prefix(2).map(\.title).joined(separator: ", ")
            return (feeds, Self.summary(count: feeds.count, sample: titles))
        }

        await perform("unreadCounts") {
            let counts = try await provider.unreadCounts()
            let total = counts[GReaderStreamID.readingList] ?? 0
            return String(localized: "\(counts.count) entries, \(total) unread in total")
        }

        await perform("articles") {
            let page = try await provider.articles(in: .all, unreadOnly: false, limit: 10, continuation: nil)
            guard let newest = page.articles.first else {
                return String(localized: "No article in this stream")
            }
            return String(localized: "\(page.articles.count) articles, newest: \(newest.title)")
        }

        await perform("unreadArticles") {
            let page = try await provider.articles(in: .all, unreadOnly: true, limit: 10, continuation: nil)
            return String(localized: "\(page.articles.count) unread articles returned")
        }

        await perform("pagination") {
            let first = try await provider.articles(in: .all, unreadOnly: false, limit: 1, continuation: nil)
            guard let token = first.continuation else {
                return String(localized: "No continuation, the stream fits in one page")
            }
            let second = try await provider.articles(in: .all, unreadOnly: false, limit: 1, continuation: token)
            let advanced = second.articles.first?.id != first.articles.first?.id
            guard advanced else {
                throw ProbeFailure.pageDidNotAdvance
            }
            return String(localized: "Second page returns a different article")
        }

        // Reading one specific feed only makes sense once the feed list is known.
        if let feed = feeds?.first {
            await perform("feedStream") {
                let page = try await provider.articles(
                    in: .feed(id: feed.id), unreadOnly: false, limit: 5, continuation: nil
                )
                return String(localized: "\(page.articles.count) articles from \(feed.title)")
            }
        } else {
            setOutcome(.skipped, for: "feedStream")
        }

        return true
    }

    /// Flips the read state of one article and puts it back, checking the server
    /// agreed both times.
    private func runWriteCheck(with provider: GReaderProvider) async {
        await perform("writeRoundTrip") {
            let page = try await provider.articles(
                in: .all, unreadOnly: false, limit: Self.writeCheckWindow, continuation: nil
            )
            guard let article = page.articles.first else {
                throw ProbeFailure.noArticleToWriteTo
            }

            let original = article.isRead
            try await provider.setRead(!original, articleIDs: [article.id])
            guard try await Self.readState(of: article, from: provider) == !original else {
                // Leave the account as it was found before giving up.
                try? await provider.setRead(original, articleIDs: [article.id])
                throw ProbeFailure.stateDidNotChange
            }

            try await provider.setRead(original, articleIDs: [article.id])
            guard try await Self.readState(of: article, from: provider) == original else {
                throw ProbeFailure.stateNotRestored
            }

            let state =
                original
                ? String(localized: "read") : String(localized: "unread")
            return String(localized: "Toggled and restored one article, left \(state)")
        }
    }

    /// Re-reads one article's state from its own feed.
    private static func readState(of article: RemoteArticle, from provider: GReaderProvider) async throws -> Bool? {
        let page = try await provider.articles(
            in: .feed(id: article.feedID), unreadOnly: false, limit: writeCheckWindow, continuation: nil
        )
        return page.articles.first { $0.id == article.id }?.isRead
    }

    // MARK: - Check bookkeeping

    /// Runs a check whose only product is its summary line.
    @discardableResult
    private func perform(_ id: String, _ work: () async throws -> String) async -> Bool {
        await perform(id) { ((), try await work()) } != nil
    }

    /// Runs a check whose value later steps need.
    private func perform<T>(_ id: String, _ work: () async throws -> (T, String)) async -> T? {
        setOutcome(.running, for: id)
        do {
            let (value, detail) = try await work()
            setOutcome(.passed(detail), for: id)
            return value
        } catch {
            setOutcome(.failed(error.localizedDescription), for: id)
            return nil
        }
    }

    private func setOutcome(_ outcome: ProbeCheck.Outcome, for id: String) {
        guard let index = checks.firstIndex(where: { $0.id == id }) else { return }
        checks[index].outcome = outcome
    }

    private func skipRemaining(after id: String) {
        guard let start = checks.firstIndex(where: { $0.id == id }) else { return }
        for index in checks.indices where index > start {
            checks[index].outcome = .skipped
        }
    }

    private static func summary(count: Int, sample: String) -> String {
        sample.isEmpty
            ? String(localized: "\(count) returned")
            : String(localized: "\(count) returned, including \(sample)")
    }

    private static func makeChecks(includesWrite: Bool) -> [ProbeCheck] {
        var checks = [
            ProbeCheck(id: "signIn", title: "Sign in", endpoint: "POST accounts/ClientLogin"),
            ProbeCheck(id: "folders", title: "Folders", endpoint: "GET reader/api/0/tag/list"),
            ProbeCheck(id: "feeds", title: "Feeds", endpoint: "GET reader/api/0/subscription/list"),
            ProbeCheck(id: "unreadCounts", title: "Unread counts", endpoint: "GET reader/api/0/unread-count"),
            ProbeCheck(
                id: "articles", title: "Articles", endpoint: "GET reader/api/0/stream/contents/…/reading-list"
            ),
            ProbeCheck(id: "unreadArticles", title: "Unread only", endpoint: "… &xt=…/state/com.google/read"),
            ProbeCheck(id: "pagination", title: "Pagination", endpoint: "… &n=1&c=<continuation>"),
            ProbeCheck(id: "feedStream", title: "One feed", endpoint: "GET reader/api/0/stream/contents/feed/<id>"),
        ]
        if includesWrite {
            checks.append(
                ProbeCheck(id: "writeRoundTrip", title: "Read state round trip", endpoint: "POST reader/api/0/edit-tag")
            )
        }
        return checks
    }
}

/// Failures the bench itself detects, as opposed to those the server reports.
nonisolated enum ProbeFailure: Error, LocalizedError, Equatable {
    case pageDidNotAdvance
    case noArticleToWriteTo
    case stateDidNotChange
    case stateNotRestored

    var errorDescription: String? {
        switch self {
        case .pageDidNotAdvance:
            String(localized: "The second page returned the same article, the continuation was ignored.")
        case .noArticleToWriteTo:
            String(localized: "No article available to test a write on.")
        case .stateDidNotChange:
            String(localized: "The server accepted the change but the state did not move.")
        case .stateNotRestored:
            String(localized: "The article state could not be put back, check it by hand.")
        }
    }
}
