//
//  MonthTests.swift
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

@Suite("Months, as a calendar has them")
struct MonthTests {
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

    @Test("A month is exactly the days it has, each of them a midnight")
    func days() throws {
        let calendar = paris()

        for (year, month, count) in [(2026, 8, 31), (2026, 4, 30), (2026, 2, 28), (2028, 2, 29)] {
            let days = Month.days(of: try day(year, month, 15, in: calendar), calendar: calendar)

            #expect(days.count == count)
            #expect(days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
            #expect(days.allSatisfy { calendar.component(.month, from: $0) == month })
            #expect(calendar.component(.day, from: try #require(days.first)) == 1)
            #expect(calendar.component(.day, from: try #require(days.last)) == count)
        }
    }

    @Test("The month the clocks change in is still all of its days, all at midnight")
    func daylightSaving() throws {
        let calendar = paris()
        // Europe puts its clocks back during Sunday 25 October 2026, which
        // makes that day twenty-five hours long. Counting in seconds would land
        // every day after it at eleven at night.
        let days = Month.days(of: try day(2026, 10, 15, in: calendar), calendar: calendar)

        #expect(days.count == 31)
        #expect(days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        #expect(calendar.component(.day, from: try #require(days.last)) == 31)
    }

    // MARK: - Which month a day is in

    @Test("A day is found in the month that holds it")
    func containing() throws {
        let calendar = paris()

        for date in [try day(2026, 8, 1, in: calendar), try day(2026, 8, 30, in: calendar)] {
            let month = Month.containing(date, calendar: calendar)
            #expect(calendar.component(.month, from: month) == 8)
            #expect(calendar.component(.day, from: month) == 1)
            #expect(calendar.component(.hour, from: month) == 0)
        }

        #expect(
            Month.containing(try day(2026, 7, 31, in: calendar), calendar: calendar)
                != Month.containing(try day(2026, 8, 1, in: calendar), calendar: calendar)
        )
    }

    // MARK: - What a chart offers

    @Test("A span inside one month is one month")
    func single() throws {
        let calendar = paris()
        let months = Month.spanning(
            try day(2026, 8, 3, in: calendar),
            to: try day(2026, 8, 30, in: calendar),
            calendar: calendar
        )
        #expect(months.count == 1)
    }

    @Test("Every month between the two ends is offered, newest first and none left out")
    func spanning() throws {
        let calendar = paris()
        let months = Month.spanning(
            try day(2026, 5, 20, in: calendar),
            to: try day(2026, 8, 3, in: calendar),
            calendar: calendar
        )

        #expect(months.map { calendar.component(.month, from: $0) } == [8, 7, 6, 5])
        #expect(months.allSatisfy { calendar.component(.day, from: $0) == 1 })
    }

    @Test("A span across the turn of the year keeps counting")
    func acrossTheYear() throws {
        let calendar = paris()
        let months = Month.spanning(
            try day(2025, 11, 20, in: calendar),
            to: try day(2026, 1, 5, in: calendar),
            calendar: calendar
        )

        #expect(months.map { calendar.component(.month, from: $0) } == [1, 12, 11])
        #expect(months.map { calendar.component(.year, from: $0) } == [2026, 2025, 2025])
    }

    @Test("A feed dated 1970 does not ask for six hundred months")
    func nonsense() throws {
        let calendar = paris()
        let months = Month.spanning(
            Date(timeIntervalSince1970: 0),
            to: try day(2026, 8, 30, in: calendar),
            calendar: calendar
        )

        #expect(months.count == Month.limit)
        // And what it does offer is the recent end of it, which is the end a
        // reader is in.
        #expect(calendar.component(.month, from: try #require(months.first)) == 8)
        #expect(calendar.component(.year, from: try #require(months.first)) == 2026)
    }

    @Test("The order of the two ends does not matter")
    func reversed() throws {
        let calendar = paris()
        let oldest = try day(2026, 5, 20, in: calendar)
        let newest = try day(2026, 8, 3, in: calendar)

        #expect(
            Month.spanning(newest, to: oldest, calendar: calendar)
                == Month.spanning(oldest, to: newest, calendar: calendar)
        )
    }

    @Test("Every day of a span lands in a month the chart actually offers")
    func agreement() throws {
        let calendar = paris()
        let oldest = try day(2026, 5, 20, in: calendar)
        let newest = try day(2026, 8, 3, in: calendar)
        let months = Set(Month.spanning(oldest, to: newest, calendar: calendar))

        // The chart scrolls to whatever `containing` returns, so a day it
        // answers with a month nobody drew would scroll to nowhere.
        var cursor = calendar.startOfDay(for: oldest)
        while cursor <= newest {
            #expect(months.contains(Month.containing(cursor, calendar: calendar)))
            cursor = try #require(calendar.date(byAdding: .day, value: 1, to: cursor))
        }
    }
}
