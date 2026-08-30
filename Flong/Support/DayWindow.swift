//
//  DayWindow.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The stretch of days a chart shows at once.
///
/// Everything is counted through `Calendar` rather than by adding
/// eighty-six thousand four hundred seconds : the day the clocks go back is
/// twenty-five hours long, and arithmetic on seconds puts the whole chart out
/// by a day for half the year.
///
/// A window is named by its last day, which is the newest one in it.
nonisolated enum DayWindow {
    /// How many days a chart shows at once.
    static let length = 30

    /// How far back a chart will go, whatever the dates say.
    ///
    /// Feeds publish articles dated 1970, dated next century, and dated with a
    /// timezone they invented. One of those in the stream would otherwise ask
    /// for two thousand windows of empty bars, and a chart nobody can scroll to
    /// the end of is worse than one that stops.
    static let limit = 12

    /// The days of a window, oldest first.
    static func days(endingAt last: Date, calendar: Calendar = .current) -> [Date] {
        let end = calendar.startOfDay(for: last)
        return (0..<length).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: end) }
    }

    /// Every window between two days, newest first.
    ///
    /// A window nothing arrived in is still a window : dropping it would put
    /// two distant months side by side and make a season of silence look like
    /// a quiet Tuesday.
    static func spanning(_ oldest: Date, to newest: Date, calendar: Calendar = .current) -> [Date] {
        let earliest = calendar.startOfDay(for: min(oldest, newest))
        var cursor = calendar.startOfDay(for: max(oldest, newest))
        var windows: [Date] = []

        while windows.count < limit {
            windows.append(cursor)
            guard let start = calendar.date(byAdding: .day, value: -(length - 1), to: cursor), start > earliest,
                let previous = calendar.date(byAdding: .day, value: -length, to: cursor)
            else { break }
            cursor = previous
        }
        return windows
    }

    /// The window a day falls in, counting back from the newest day of all.
    static func containing(_ day: Date, newest: Date, calendar: Calendar = .current) -> Date {
        let end = calendar.startOfDay(for: newest)
        let target = calendar.startOfDay(for: day)

        let back = calendar.dateComponents([.day], from: target, to: end).day ?? 0
        guard back > 0 else { return end }
        return calendar.date(byAdding: .day, value: -(back / length * length), to: end) ?? end
    }
}
