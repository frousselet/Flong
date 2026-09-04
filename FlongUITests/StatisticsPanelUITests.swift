//
//  StatisticsPanelUITests.swift
//  FlongUITests
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// The page of figures, opened the way a reader opens it.
///
/// XCUITest and not a unit test, because the question is about the window : the
/// chart in the corner opens the page, the page draws itself over whatever the
/// reader was looking at, and every one of the eight windows can be picked and
/// answers with a page rather than an empty one.
///
/// Every control is found by identifier and not by label : a label is
/// translated, and a test that looked for the English would pass here and fail
/// on a device set to the reader's own language.
final class StatisticsPanelUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
            XCUIDevice.shared.orientation = .portrait
        #endif
    }

    @MainActor
    func testTheCornerOpensTheFigures() throws {
        let app = XCUIApplication()
        app.launch()

        // **In the reader's own menu now, and it was a chart in the corner.**
        // That corner carried the sources, the subjects, the notices and then
        // this, which is four glyphs before the page has said anything : they
        // are rows in the one place a reader already looks for what is theirs.
        let face = app.buttons["reader"].firstMatch
        XCTAssertTrue(face.waitForExistence(timeout: 20), "The reader's own button is in the corner of every section")
        face.tap()

        let mark = app.buttons["statistics"].firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 5), "The menu leads to what their reading adds up to")
        mark.tap()

        // The window the page opens on. Its being there at all is what says the
        // page opened, since everything else on it depends on what the stream
        // happens to hold.
        let week = app.buttons["range-week"].firstMatch
        XCTAssertTrue(week.waitForExistence(timeout: 10), "The page opens on a week")
        XCTAssertTrue(week.isHittable, "And the window can be changed")
    }

    /// Every one of the eight windows can be picked.
    ///
    /// A window that cannot be reached is a window that does not exist, and the
    /// row scrolls sideways : the last of the eight is off the edge of a phone
    /// when the page opens.
    @MainActor
    func testEveryWindowCanBePicked() throws {
        let app = XCUIApplication()
        app.launch()

        let face = app.buttons["reader"].firstMatch
        XCTAssertTrue(face.waitForExistence(timeout: 20))
        face.tap()

        let mark = app.buttons["statistics"].firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 5))
        mark.tap()

        XCTAssertTrue(app.buttons["range-day"].firstMatch.waitForExistence(timeout: 10))

        for identifier in [
            "range-day", "range-week", "range-month", "range-quarter",
            "range-half", "range-threeQuarters", "range-year", "range-all",
        ] {
            let window = app.buttons[identifier].firstMatch
            XCTAssertTrue(window.waitForExistence(timeout: 5), "\(identifier) is one of the eight")

            // The row runs off the edge of a phone, so the last few have to be
            // brought into view before they can be pressed.
            //
            // **Swiped from whichever of them is on screen**, and it used to be
            // swiped from the first. Once the row has scrolled, the first is
            // off the edge, and XCUITest refuses to swipe an element whose
            // visible frame is empty : the test failed on the window after the
            // one that scrolled it.
            if !window.isHittable {
                let anchor = [
                    "range-day", "range-week", "range-month", "range-quarter",
                    "range-half", "range-threeQuarters", "range-year",
                ]
                .map { app.buttons[$0].firstMatch }
                .first { $0.exists && $0.isHittable }
                anchor?.swipeLeft()
            }
            guard window.isHittable else { continue }
            window.tap()

            // The figures are counted again for every window, and the page has
            // to come back with one rather than staying on the last.
            XCTAssertTrue(
                app.buttons["range-day"].firstMatch.waitForExistence(timeout: 10),
                "\(identifier) left the page standing"
            )
        }
    }
}
