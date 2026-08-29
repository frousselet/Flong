//
//  QueryDates.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Reads the dates and the durations a query carries.
///
/// A reader types `after:2026-01`, not a timestamp. A month means its first
/// instant, a year means the first of January, and `age:<7d` means the last
/// seven days.
nonisolated enum QueryDates {
    /// `2026`, `2026-08` or `2026-08-25`, read in the reader's own time zone.
    static func date(from text: String) -> Date? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count), parts.allSatisfy({ $0.allSatisfy(\.isNumber) && !$0.isEmpty }) else {
            return nil
        }
        guard let year = Int(parts[0]), (1000...9999).contains(year) else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = parts.count > 1 ? Int(parts[1]) : 1
        components.day = parts.count > 2 ? Int(parts[2]) : 1

        guard let month = components.month, (1...12).contains(month) else { return nil }
        guard let day = components.day, (1...31).contains(day) else { return nil }

        return Calendar.current.date(from: components)
    }

    /// `<7d`, `>2w`, `<=1y`, and the same without an operator, which means
    /// younger than.
    static func age(from text: String) -> QueryDate? {
        var text = text.trimmingCharacters(in: .whitespaces)
        var isYounger = true

        if text.hasPrefix("<") {
            text.removeFirst()
        } else if text.hasPrefix(">") {
            isYounger = false
            text.removeFirst()
        }
        if text.hasPrefix("=") { text.removeFirst() }

        guard let last = text.last, let unit = units[last] else { return nil }
        guard let amount = Double(text.dropLast()), amount > 0 else { return nil }

        let seconds = amount * unit
        return isYounger ? .youngerThan(seconds) : .olderThan(seconds)
    }

    private static let units: [Character: TimeInterval] = [
        "h": 3600,
        "d": 86400,
        "w": 7 * 86400,
        "m": 30 * 86400,
        "y": 365 * 86400,
    ]
}
