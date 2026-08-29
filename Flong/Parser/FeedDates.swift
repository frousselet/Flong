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

        if let date = internetDateTime(trimmed) { return date }
        for formatter in formatters {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

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
