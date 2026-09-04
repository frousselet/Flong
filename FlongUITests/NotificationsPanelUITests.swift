//
//  NotificationsPanelUITests.swift
//  FlongUITests
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// The panel a reader opens when they want to be told about something.
///
/// XCUITest and not a unit test, for the reason the whole change exists : a
/// reader who follows thirty feeds and wants to know when any of them publishes
/// could not say so anywhere. A unit test can say what the switch does once it
/// is thrown. Only this can say that the switch is there and can be pressed.
///
/// Every control is found by identifier and not by label : a label is
/// translated, and a test that looked for the English would pass here and fail
/// on a device set to the reader's own language.
final class NotificationsPanelUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Portrait, whatever the simulator was left in. XCUITest reports an
        // element's frame in the device's own space and taps in the screen's :
        // in landscape the two come apart, so a tap aimed at one row of a sheet
        // lands on another and the test fails somewhere it never went near.
        // The iPhone is portrait only and cannot get there ; the iPad turns,
        // and these suites run on it.
        #if os(iOS)
            XCUIDevice.shared.orientation = .portrait
        #endif
    }

    @MainActor
    func testTheSwitchForEverySourceIsThere() throws {
        let app = XCUIApplication()
        app.launch()

        // **In the reader's own menu now, and it was a bell in the corner.**
        // That corner carried the sources, the subjects and the notices, which
        // is three glyphs before the page has said anything : they are rows in
        // the one place a reader already looks for what is theirs.
        let face = app.buttons["reader"].firstMatch
        XCTAssertTrue(face.waitForExistence(timeout: 20), "The reader's own button is in the corner of every section")
        face.tap()

        let bell = app.buttons["notifications"].firstMatch
        XCTAssertTrue(bell.waitForExistence(timeout: 5), "The menu leads to what Flong may interrupt them for")
        bell.tap()

        // The one a reader arrives looking for. It covers every source they
        // follow, and its absence was what a reader meant by saying Flong did
        // not notify them.
        let articles = app.switches["notify-new-articles"].firstMatch
        XCTAssertTrue(articles.waitForExistence(timeout: 5), "The panel offers a switch about new articles")
        XCTAssertTrue(articles.isHittable, "And it can be pressed")

        let stories = app.switches["notify-new-stories"].firstMatch
        XCTAssertTrue(stories.waitForExistence(timeout: 5), "And the one about stories is still beside it")
    }
}
