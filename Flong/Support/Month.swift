//
//  Month.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// A month, as the reader's own calendar has it.
///
/// **Exactly the days the month has**, which is twenty-eight, twenty-nine,
/// thirty or thirty-one : a rolling stretch of thirty is a stretch nobody
/// keeps, and a chart of it cannot be compared with the one beside it. A month
/// can, and February being short is a fact about February rather than a gap in
/// the drawing.
///
/// Everything is counted through `Calendar` rather than by adding
/// eighty-six thousand four hundred seconds : the day the clocks go back is
/// twenty-five hours long, and arithmetic on seconds puts the whole chart out
/// by a day for half the year. It is also what makes this right in a calendar
/// that is not Gregorian, where a month is not thirty-odd days at all.
///
/// A month is named by its first day.
nonisolated enum Month {
    /// How far back a chart will go, whatever the dates say.
    ///
    /// Feeds publish articles dated 1970, dated next century, and dated with a
    /// timezone they invented. One of those in the stream would otherwise ask
    /// for six hundred months of empty bars, and a chart nobody can scroll to
    /// the end of is worse than one that stops.
    static let limit = 12

    /// The first day of the month a day falls in.
    static func containing(_ day: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: day)?.start ?? calendar.startOfDay(for: day)
    }

    /// Every day of a month, oldest first.
    static func days(of month: Date, calendar: Calendar = .current) -> [Date] {
        let start = containing(month, calendar: calendar)
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 0
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Every month between two days, newest first.
    ///
    /// A month nothing arrived in is still a month : dropping it would put two
    /// distant seasons side by side and make a summer of silence look like a
    /// quiet Tuesday.
    static func spanning(_ oldest: Date, to newest: Date, calendar: Calendar = .current) -> [Date] {
        let earliest = containing(min(oldest, newest), calendar: calendar)
        var cursor = containing(max(oldest, newest), calendar: calendar)
        var months: [Date] = []

        while months.count < limit {
            months.append(cursor)
            guard cursor > earliest, let previous = calendar.date(byAdding: .month, value: -1, to: cursor)
            else { break }
            cursor = previous
        }
        return months
    }
}
