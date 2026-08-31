//
//  FeedDates.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Reads the dates feeds actually publish.
///
/// The specifications name two formats, RFC 822 for RSS and RFC 3339 for Atom,
/// and publishers write neither of them faithfully : missing seconds, a two
/// digit year, a named zone nobody agrees on, a space where the T belongs. Each
/// spelling is tried in turn, and a date that means nothing is left `nil` rather
/// than guessed at, since a wrong date sorts an article into the wrong week.
nonisolated enum FeedDates {
    static func date(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let spelled = normalized(trimmed)
        if let date = internetDateTime(spelled) { return date }
        for formatter in formatters {
            if let date = formatter.date(from: spelled) { return date }
        }
        return nil
    }

    /// The two spellings that cost the most articles, put right before anything
    /// tries to read them.
    ///
    /// Neither is exotic and both were silent : a date that will not parse
    /// leaves the article with none, and an article with none sorts on the day
    /// it arrived. In one store of fifteen hundred articles these two accounted
    /// for twenty, every one of them wearing the moment it was pulled as though
    /// it were the moment it was written.
    static func normalized(_ text: String) -> String {
        var text = text

        // `Fri,28 Aug 2026 01:03:20 GMT`. RFC 822 puts a space after the
        // weekday's comma ; `senat.fr` does not, and every article it publishes
        // was undated for it.
        if let comma = text.firstIndex(of: ","), text.index(after: comma) < text.endIndex,
            text[text.index(after: comma)] != " "
        {
            text.insert(" ", at: text.index(after: comma))
        }

        // `Mon, 03 Aug 2026 17:00:00 CEST`. The RFC names a handful of North
        // American abbreviations and a POSIX locale knows those ; European
        // publishers write their own, and a French reader's feeds are full of
        // them.
        for name in namedZonesByLength where text.hasSuffix(" \(name)") {
            return text.dropLast(name.count) + (namedZones[name] ?? "")
        }
        return text
    }

    /// The zone names feeds use that a POSIX locale has never heard of.
    ///
    /// Each abbreviation carries its own summer time, so the offset is fixed
    /// and there is nothing to work out from the date it is attached to.
    ///
    /// **`IST` is deliberately absent.** It is Indian, Irish and Israeli
    /// standard time at three different offsets, and this file's own rule is
    /// that a date which means nothing is left alone rather than guessed at,
    /// since a wrong date sorts an article into the wrong week. A date that
    /// does not parse costs one article its ordering ; a date parsed wrongly
    /// costs the reader their trust in the page.
    static let namedZones = [
        "CEST": "+0200",
        "CET": "+0100",
        "WEST": "+0100",
        "WET": "+0000",
        "EEST": "+0300",
        "EET": "+0200",
        "BST": "+0100",
        "MSK": "+0300",
        "JST": "+0900",
    ]

    /// Longest first, so `CEST` is never read as `CET` with a letter left over.
    private static let namedZonesByLength = namedZones.keys.sorted { $0.count > $1.count }

    /// RFC 3339, with and without fractional seconds.
    private static func internetDateTime(_ text: String) -> Date? {
        // A space instead of the T is common enough to be worth fixing rather
        // than refusing.
        let candidates = [text, text.replacingOccurrences(of: " ", with: "T")]

        for candidate in candidates {
            for options in [
                ISO8601DateFormatter.Options([.withInternetDateTime, .withFractionalSeconds]),
                [.withInternetDateTime],
            ] {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = options
                if let date = formatter.date(from: candidate) { return date }
            }
        }
        return nil
    }

    /// The spellings that turn up once the two specifications are exhausted.
    private static let formats = [
        "EEE, dd MMM yyyy HH:mm:ss zzz",  // RFC 822, as RSS states it
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm zzz",  // No seconds
        "EEE, dd MMM yyyy HH:mm:ss",  // No zone, taken as UTC
        "dd MMM yyyy HH:mm:ss zzz",  // No weekday
        "dd MMM yyyy HH:mm:ss Z",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd",
        "MM/dd/yyyy HH:mm:ss",
    ]

    private static let formatters: [DateFormatter] = formats.map { format in
        let formatter = DateFormatter()
        // A feed's dates are not written in the reader's language, and a French
        // device must still read "Wed, 27 Aug 2026".
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}
