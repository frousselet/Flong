//
//  DayWindowTests.swift
//  FlongTests
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

@Suite("The stretch of days a chart shows")
struct DayWindowTests {
    /// Paris, where the clocks move.
    private func paris() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    @Test("A window is thirty days ending on the one it is named for")
    func days() throws {
        let calendar = paris()
        let days = DayWindow.days(endingAt: try day(2026, 8, 30, in: calendar), calendar: calendar)

        #expect(days.count == DayWindow.length)
        #expect(days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        #expect(calendar.isDate(try #require(days.last), inSameDayAs: try day(2026, 8, 30, in: calendar)))
        // Thirty days back from the thirtieth of August is the first of it.
        #expect(calendar.isDate(try #require(days.first), inSameDayAs: try day(2026, 8, 1, in: calendar)))
    }

    @Test("The window the clocks change in still starts at midnight")
    func daylightSaving() throws {
        let calendar = paris()
        // Europe puts its clocks back during Sunday 25 October 2026, which
        // makes that day twenty-five hours long. Counting in seconds would land
        // every day before it at eleven at night.
        let days = DayWindow.days(endingAt: try day(2026, 11, 10, in: calendar), calendar: calendar)

        #expect(days.count == DayWindow.length)
        #expect(days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        #expect(calendar.isDate(try #require(days.first), inSameDayAs: try day(2026, 10, 12, in: calendar)))
    }

    // MARK: - What a chart offers

    @Test("A month of articles is one window")
    func single() throws {
        let calendar = paris()
        let windows = DayWindow.spanning(
            try day(2026, 8, 10, in: calendar),
            to: try day(2026, 8, 30, in: calendar),
            calendar: calendar
        )
        #expect(windows.count == 1)
        #expect(calendar.isDate(try #require(windows.first), inSameDayAs: try day(2026, 8, 30, in: calendar)))
    }

    @Test("Anything older than thirty days is another window, newest first")
    func several() throws {
        let calendar = paris()
        let windows = DayWindow.spanning(
            try day(2026, 6, 15, in: calendar),
            to: try day(2026, 8, 30, in: calendar),
            calendar: calendar
        )

        #expect(windows.count == 3)
        #expect(windows.map { calendar.component(.month, from: $0) } == [8, 7, 7])
        #expect(windows.map { calendar.component(.day, from: $0) } == [30, 31, 1])
    }

    @Test("A feed dated 1970 does not ask for two thousand windows")
    func nonsense() throws {
        let calendar = paris()
        let windows = DayWindow.spanning(
            Date(timeIntervalSince1970: 0),
            to: try day(2026, 8, 30, in: calendar),
            calendar: calendar
        )
        #expect(windows.count == DayWindow.limit)
        // And what it does offer is the recent end of it, which is the end a
        // reader is in.
        #expect(calendar.isDate(try #require(windows.first), inSameDayAs: try day(2026, 8, 30, in: calendar)))
    }

    @Test("The order of the two ends does not matter")
    func reversed() throws {
        let calendar = paris()
        let oldest = try day(2026, 6, 15, in: calendar)
        let newest = try day(2026, 8, 30, in: calendar)

        #expect(
            DayWindow.spanning(newest, to: oldest, calendar: calendar)
                == DayWindow.spanning(oldest, to: newest, calendar: calendar)
        )
    }

    // MARK: - Which window a day is in

    @Test("A day is found in the window that holds it")
    func containing() throws {
        let calendar = paris()
        let newest = try day(2026, 8, 30, in: calendar)

        // The newest day, and the oldest day of its own window.
        #expect(DayWindow.containing(newest, newest: newest, calendar: calendar) == calendar.startOfDay(for: newest))
        #expect(
            DayWindow.containing(try day(2026, 8, 1, in: calendar), newest: newest, calendar: calendar)
                == calendar.startOfDay(for: newest)
        )

        // One day older than that is the window before, which ends on 31 July.
        let previous = DayWindow.containing(try day(2026, 7, 31, in: calendar), newest: newest, calendar: calendar)
        #expect(calendar.isDate(previous, inSameDayAs: try day(2026, 7, 31, in: calendar)))

        // And a day newer than the newest cannot fall outside the first window.
        #expect(
            DayWindow.containing(try day(2026, 9, 10, in: calendar), newest: newest, calendar: calendar)
                == calendar.startOfDay(for: newest)
        )
    }

    @Test("Every day of a span lands in a window the chart actually offers")
    func agreement() throws {
        let calendar = paris()
        let oldest = try day(2026, 6, 15, in: calendar)
        let newest = try day(2026, 8, 30, in: calendar)
        let windows = Set(DayWindow.spanning(oldest, to: newest, calendar: calendar))

        // The chart scrolls to whatever this returns, so a day it answers with
        // a window nobody drew would be a chart that scrolls to nowhere.
        var cursor = calendar.startOfDay(for: oldest)
        while cursor <= newest {
            #expect(windows.contains(DayWindow.containing(cursor, newest: newest, calendar: calendar)))
            cursor = try #require(calendar.date(byAdding: .day, value: 1, to: cursor))
        }
    }
}
