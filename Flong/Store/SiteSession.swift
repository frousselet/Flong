//
//  SiteSession.swift
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

/// One cookie of a signed-in session, reduced to what a request needs.
///
/// `HTTPCookie` carries a dictionary of `Any`, which is not something to write
/// to a keychain and read back. These five fields are what it takes to put the
/// cookie back on a request, and nothing else is kept.
nonisolated struct SessionCookie: Hashable, Sendable, Codable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expiresAt: Date?
    var isSecure: Bool

    init?(_ cookie: HTTPCookie) {
        guard !cookie.name.isEmpty else { return nil }
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path.isEmpty ? "/" : cookie.path
        expiresAt = cookie.expiresDate
        isSecure = cookie.isSecure
    }

    /// A cookie spelled out, for a test that needs one without a browser.
    init(named name: String, value: String, domain: String, path: String = "/", expiresAt: Date? = nil) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresAt = expiresAt
        self.isSecure = true
    }

    /// Whether it is still worth sending.
    func isValid(at date: Date = Date()) -> Bool {
        guard let expiresAt else { return true }
        return expiresAt > date
    }

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
        ]
        if let expiresAt { properties[.expires] = expiresAt }
        if isSecure { properties[.secure] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
}

/// A reader's signed-in session on one site.
///
/// **This is the part of section 9 that used to say `out of scope`.** The reason
/// it gave was a good one and still holds : a site's login form is not an
/// interface anybody promised to keep, and a session breaks when the site
/// decides it does, with no warning and no error a program can read.
///
/// It is here because the alternative is worse for the reader who pays. What
/// the decision buys is that a subscriber reads what they paid for in the reader
/// they chose ; what it costs is a session that has to be renewed by hand now
/// and then. The cost is made legible rather than hidden : the session says when
/// it was signed in and when it last worked, and a site that starts refusing
/// says so instead of quietly serving teasers.
///
/// **What it is not.** No credentials of the site are ever held : the reader
/// signs in on the site's own page, in a web view, and what is kept is the
/// cookies that page left behind. Flong never sees a password, never types one,
/// and never automates a login form.
nonisolated struct SiteSession: Hashable, Sendable, Codable {
    /// The host the session belongs to, without its `www`.
    var host: String
    var cookies: [SessionCookie]
    var signedInAt: Date
    /// The last time a page came back whole, which is the only honest proof a
    /// session still works.
    var lastWorkedAt: Date?

    init(host: String, cookies: [SessionCookie], signedInAt: Date = Date(), lastWorkedAt: Date? = nil) {
        self.host = host
        self.cookies = cookies
        self.signedInAt = signedInAt
        self.lastWorkedAt = lastWorkedAt
    }

    /// The cookies still worth sending.
    func valid(at date: Date = Date()) -> [SessionCookie] {
        cookies.filter { $0.isValid(at: date) }
    }

    /// Whether there is anything left to send.
    func isUsable(at date: Date = Date()) -> Bool {
        !valid(at: date).isEmpty
    }

    /// Whether a cookie of this session belongs on a request to that address.
    ///
    /// A site's cookies go to that site and nowhere else. `lemonde.fr` covers
    /// `www.lemonde.fr` and `secure.lemonde.fr` ; it does not cover
    /// `notlemonde.fr`, and the dot is what tells the two apart.
    func covers(_ url: URL) -> Bool {
        guard let target = FeedURL.room(of: url) else { return false }
        return target == host || target.hasSuffix("." + host)
    }

    /// The site a set of cookies belongs to, as the cookies themselves say.
    ///
    /// A reader signs in at `www.lemonde.fr`, and the session is wanted for
    /// every feed and article of the site : `abonnes.lemonde.fr`,
    /// `rss.lemonde.fr`, the lot. Guessing that from the address they happened
    /// to sign in at would mean guessing where a domain ends, which needs the
    /// public suffix list and gets `example.co.uk` wrong.
    ///
    /// The cookies say it themselves. A site that wants its session to work
    /// across its subdomains sets `.lemonde.fr`, and that declaration is the
    /// site's own and is authoritative. The broadest of them is the site.
    static func site(of cookies: [SessionCookie], signedInAt host: String) -> String {
        let claimed =
            cookies
            .map { $0.domain.hasPrefix(".") ? String($0.domain.dropFirst()) : $0.domain }
            .filter { host == $0 || host.hasSuffix("." + $0) }

        // The shortest is the broadest, and a site that claims nothing keeps
        // the host the reader signed in at.
        return claimed.min { $0.count < $1.count } ?? host
    }
}

/// Where a reader's sessions are kept, which is the keychain and nowhere else.
nonisolated protocol SessionStoring: Sendable {
    func session(for host: String) throws -> SiteSession?
    func setSession(_ session: SiteSession?, for host: String) throws
    func hosts() throws -> [String]
    /// Signs out of every site at once, for a reset.
    func removeEverything() throws
}

/// The keychain, keyed by host.
nonisolated struct KeychainSessions: SessionStoring {
    static let service = "com.rslt.Flong.sessions"

    private let service: String

    init(service: String = KeychainSessions.service) {
        self.service = service
    }

    func session(for host: String) throws -> SiteSession? {
        var query = baseQuery(for: host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw CredentialError.unreadable }
            return try? JSONDecoder().decode(SiteSession.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialError.keychain(status)
        }
    }

    func setSession(_ session: SiteSession?, for host: String) throws {
        guard let session else {
            let status = SecItemDelete(baseQuery(for: host) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialError.keychain(status)
            }
            return
        }

        let data = try JSONEncoder().encode(session)
        let updated = SecItemUpdate(
            baseQuery(for: host) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw CredentialError.keychain(updated) }

        var item = baseQuery(for: host)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw CredentialError.keychain(added) }
    }

    func hosts() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            let items = result as? [[String: Any]] ?? []
            return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
        case errSecItemNotFound:
            return []
        default:
            throw CredentialError.keychain(status)
        }
    }

    /// Signs out of every site, including any whose feeds are already gone.
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

    private func baseQuery(for host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
            kSecAttrSynchronizable as String: true,
        ]
    }
}

/// Sessions held for the length of a test.
nonisolated final class MemorySessions: SessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [String: SiteSession] = [:]

    init() {}

    func session(for host: String) throws -> SiteSession? {
        lock.withLock { sessions[host] }
    }

    func setSession(_ session: SiteSession?, for host: String) throws {
        lock.withLock { sessions[host] = session }
    }

    func hosts() throws -> [String] {
        lock.withLock { sessions.keys.sorted() }
    }

    func removeEverything() throws {
        lock.withLock { sessions.removeAll() }
    }
}
