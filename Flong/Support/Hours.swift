//
//  Hours.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// A day, an hour at a time, as the reader's own calendar has it.
///
/// **The chart counted days over a month and counts hours over a day.** A month
/// of thirty-odd bars says which weeks were busy, which is a fact about the
/// press rather than about the reading : a reader looking at a wire wants to
/// know what has come in since they last looked, and that is a question about
/// this morning and last night, not about the fifteenth.
///
/// **Exactly the hours the day has**, which is twenty-three, twenty-four or
/// twenty-five : the day the clocks go back is twenty-five hours long, and a
/// chart that always drew twenty-four would put an hour of that day's arrivals
/// somewhere it did not happen. Everything is counted through `Calendar` rather
/// than by adding three thousand six hundred seconds, which is also what makes
/// it right in a calendar that is not Gregorian.
///
/// A day is named by its first moment, an hour by its own.
nonisolated enum Hours {
    /// How far back a chart will go, whatever the dates say.
    ///
    /// Feeds publish articles dated 1970, dated next century, and dated with a
    /// timezone they invented. One of those in the stream would otherwise ask
    /// for twenty thousand days of empty bars, and a chart nobody can scroll to
    /// the end of is worse than one that stops. Ninety days is a season, which
    /// is longer than a wire is ever read back.
    static let limit = 90

    /// The start of the day a moment falls in.
    static func containing(_ moment: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: moment)
    }

    /// The start of the hour a moment falls in.
    static func hour(of moment: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .hour, for: moment)?.start ?? moment
    }

    /// Every hour of a day, earliest first.
    static func of(_ day: Date, calendar: Calendar = .current) -> [Date] {
        let start = containing(day, calendar: calendar)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return [start] }

        var hours: [Date] = []
        var cursor = start
        while cursor < next {
            hours.append(cursor)
            guard let following = calendar.date(byAdding: .hour, value: 1, to: cursor), following > cursor
            else { break }
            cursor = following
        }
        return hours
    }

    /// Every day between two moments, newest first.
    ///
    /// A day nothing arrived on is still a day : dropping it would put a
    /// Tuesday next to the Friday before last and make a week of silence look
    /// like a quiet night.
    static func spanning(_ oldest: Date, to newest: Date, calendar: Calendar = .current) -> [Date] {
        let earliest = containing(min(oldest, newest), calendar: calendar)
        var cursor = containing(max(oldest, newest), calendar: calendar)
        var days: [Date] = []

        while days.count < limit {
            days.append(cursor)
            guard cursor > earliest, let previous = calendar.date(byAdding: .day, value: -1, to: cursor)
            else { break }
            cursor = previous
        }
        return days
    }
}
