//
//  ReadStateBlock.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CryptoKit
import Foundation

/// A short, device independent name for an article.
///
/// Two devices give the same article two different local identifiers, so a read
/// state cannot travel as one. It travels as this instead : eight bytes of a
/// digest of the feed address and the article's own identity, which both devices
/// work out to the same value without ever having spoken.
///
/// Eight bytes is enough. Over the hundred and twenty five thousand articles of
/// the target corpus the chance of two colliding is around one in five thousand
/// million, and the cost of a collision is one article marked read that was not.
nonisolated struct ArticleFingerprint: Hashable, Sendable, Comparable {
    let value: UInt64

    init(value: UInt64) {
        self.value = value
    }

    init(feedURL: URL, guid: String) {
        var hasher = SHA256()
        hasher.update(data: Data(feedURL.absoluteString.utf8))
        hasher.update(data: Data([0x0A]))
        hasher.update(data: Data(guid.utf8))

        let digest = Array(hasher.finalize())
        value = digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    static func < (lhs: ArticleFingerprint, rhs: ArticleFingerprint) -> Bool { lhs.value < rhs.value }
}

/// What a block of read states is about.
nonisolated enum ReadStateKind: String, Hashable, Sendable, CaseIterable {
    case read
}

/// The read articles of one period, as one compressed set.
///
/// This is the record type the whole synchronization budget rests on. One record
/// per month, holding every article read in it, instead of one record per
/// article : three years of reading is a few dozen records rather than a hundred
/// thousand, which is the difference between a synchronization that works and
/// one CloudKit rate limits into uselessness.
///
/// **Merging is a union**, so it is commutative and idempotent and there is no
/// conflict to resolve. Two devices that read different articles in August both
/// end up with both. It follows that reading is one way : marking an article
/// unread is a local decision and does not travel, since a set that only grows
/// has nothing to say about what left it. That is the price of having no
/// conflict resolution at all, and it is worth paying.
nonisolated struct ReadStateBlock: Hashable, Sendable {
    /// The month the articles were published in, `2026-08`, or `undated`.
    let period: String
    let kind: ReadStateKind
    private(set) var fingerprints: Set<ArticleFingerprint>

    init(period: String, kind: ReadStateKind = .read, fingerprints: Set<ArticleFingerprint> = []) {
        self.period = period
        self.kind = kind
        self.fingerprints = fingerprints
    }

    var isEmpty: Bool { fingerprints.isEmpty }

    func contains(_ fingerprint: ArticleFingerprint) -> Bool { fingerprints.contains(fingerprint) }

    /// The union of two blocks of the same period.
    func merged(with other: ReadStateBlock) -> ReadStateBlock {
        precondition(period == other.period && kind == other.kind, "Only blocks of one period and kind merge")
        return ReadStateBlock(period: period, kind: kind, fingerprints: fingerprints.union(other.fingerprints))
    }

    mutating func insert(_ fingerprints: some Sequence<ArticleFingerprint>) {
        self.fingerprints.formUnion(fingerprints)
    }

    // MARK: - The wire

    /// The set, sorted and compressed.
    ///
    /// Sorting costs nothing and makes the bytes identical on every device for
    /// the same set, which is what lets two devices notice they already agree.
    /// The compression is worth little on digests, which are random by
    /// construction, and it is applied anyway : it costs one call and it pays
    /// off the day a set turns out to be sparse.
    func encoded() -> Data {
        var bytes = Data(capacity: fingerprints.count * 8)
        for fingerprint in fingerprints.sorted() {
            withUnsafeBytes(of: fingerprint.value.bigEndian) { bytes.append(contentsOf: $0) }
        }

        guard !bytes.isEmpty, let compressed = try? (bytes as NSData).compressed(using: .lzfse) as Data else {
            return bytes
        }
        return compressed.count < bytes.count ? compressed : bytes
    }

    /// Reads back what `encoded()` wrote, compressed or not.
    static func decode(_ data: Data, period: String, kind: ReadStateKind = .read) -> ReadStateBlock {
        var bytes = data
        if data.count % 8 != 0, let expanded = try? (data as NSData).decompressed(using: .lzfse) as Data {
            bytes = expanded
        } else if let expanded = try? (data as NSData).decompressed(using: .lzfse) as Data, expanded.count % 8 == 0 {
            bytes = expanded
        }

        var fingerprints: Set<ArticleFingerprint> = []
        fingerprints.reserveCapacity(bytes.count / 8)

        var index = bytes.startIndex
        while index + 8 <= bytes.endIndex {
            let value = bytes[index..<index + 8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            fingerprints.insert(ArticleFingerprint(value: value))
            index += 8
        }

        return ReadStateBlock(period: period, kind: kind, fingerprints: fingerprints)
    }

    // MARK: - Periods

    /// The period an article belongs to, which both devices work out alike.
    ///
    /// The month it was **published** in, never the month it was read or
    /// received : those differ from one device to the next, and a block whose
    /// name depended on them would be a block no two devices could agree on.
    static func period(for date: Date?) -> String {
        guard let date else { return "undated" }
        return periodFormatter.string(from: date)
    }

    private static let periodFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
}
