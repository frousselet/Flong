//
//  HoursTests.swift
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

/// A day, an hour at a time.
///
/// Everything here is asked of `Calendar` rather than of arithmetic on seconds,
/// which is the whole point : the day the clocks change is not twenty-four
/// hours long, and a chart that always drew twenty-four bars would put an
/// hour's arrivals somewhere they did not happen.
@Suite("Hours of a day")
struct HoursTests {
    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, in calendar: Calendar) throws -> Date {
        try #require(
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
        )
    }

    @Test("An ordinary day has twenty-four hours, the first of them midnight")
    func ordinary() throws {
        let calendar = paris
        let hours = Hours.of(try moment(2026, 8, 30, 13, in: calendar), calendar: calendar)

        #expect(hours.count == 24)
        #expect(calendar.component(.hour, from: hours[0]) == 0)
        #expect(calendar.component(.hour, from: hours[23]) == 23)
        // Earliest first, which is the order they are drawn in.
        #expect(hours == hours.sorted())
    }

    @Test("The day the clocks go back has twenty-five, and the one forward has twenty-three")
    func theClocksChange() throws {
        let calendar = paris

        // Europe/Paris, the last Sunday of October and of March.
        #expect(Hours.of(try moment(2026, 10, 25, 12, in: calendar), calendar: calendar).count == 25)
        #expect(Hours.of(try moment(2026, 3, 29, 12, in: calendar), calendar: calendar).count == 23)
    }

    @Test("An hour is named by its own first moment")
    func theHour() throws {
        let calendar = paris
        let quarterPast = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: 14, minute: 15, second: 30))
        )

        let hour = Hours.hour(of: quarterPast, calendar: calendar)
        #expect(calendar.component(.hour, from: hour) == 14)
        #expect(calendar.component(.minute, from: hour) == 0)
        #expect(calendar.component(.second, from: hour) == 0)
    }

    @Test("A day is named by its own midnight, and two days are two days")
    func theDay() throws {
        let calendar = paris
        let evening = try moment(2026, 8, 30, 23, in: calendar)

        #expect(calendar.component(.hour, from: Hours.containing(evening, calendar: calendar)) == 0)
        #expect(
            Hours.containing(try moment(2026, 8, 30, 23, in: calendar), calendar: calendar)
                != Hours.containing(try moment(2026, 8, 31, 0, in: calendar), calendar: calendar)
        )
    }

    @Test("Every day between two moments is offered, newest first, gaps included")
    func spanning() throws {
        let calendar = paris
        let days = Hours.spanning(
            try moment(2026, 8, 25, 9, in: calendar),
            to: try moment(2026, 8, 30, 21, in: calendar),
            calendar: calendar
        )

        // A day nothing arrived on is still a day : dropping it would put a
        // Tuesday next to the Friday before last.
        #expect(days.count == 6)
        #expect(days == days.sorted(by: >))
        #expect(Hours.containing(days[0], calendar: calendar) == days[0])
    }

    @Test("A date nobody meant does not ask for twenty thousand bars")
    func theLimit() throws {
        let calendar = paris
        // Feeds publish articles dated 1970 and dated next century.
        let days = Hours.spanning(
            try moment(1970, 1, 1, 0, in: calendar),
            to: try moment(2026, 8, 30, 12, in: calendar),
            calendar: calendar
        )

        #expect(days.count == Hours.limit)
    }
}
