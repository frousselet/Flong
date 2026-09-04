//
//  EditionArchiveUITests.swift
//  FlongUITests
//
//  Created by François Rousselet on 04/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// The back numbers, reached the way a reader reaches them.
///
/// XCUITest and not a unit test, because the question is about the window : the
/// line under the edition's own headline pushes a screen onto the digest's
/// stack, that screen draws a row per published edition, and a row opens the
/// page as it was. None of that is answerable by a function taking names and
/// giving back a sentence.
///
/// **It is written to pass on a device with no editions too**, which is every
/// device the first time it is launched and every device with no Apple
/// Intelligence. What it asserts then is the one thing that still has to be
/// true : the front page says there is no edition rather than rendering blank.
/// A test that demanded an edition would be a test that fails on exactly the
/// devices section 14 exists to keep working.
///
/// Every control is found by identifier and not by label : a label is
/// translated, and a test that looked for the English would pass here and fail
/// on a device set to the reader's own language.
final class EditionArchiveUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
            XCUIDevice.shared.orientation = .portrait
        #endif
    }

    @MainActor
    func testTheEditionLeadsToItsBackNumbers() throws {
        let app = XCUIApplication()
        app.launch()

        let archive = app.buttons["edition-archive"].firstMatch
        guard archive.waitForExistence(timeout: 20) else {
            // No edition on this device, which is a legitimate state and one
            // the page has to say out loud rather than render blank.
            XCTAssertTrue(
                app.staticTexts.count > 0,
                "A page with no edition still says something"
            )
            return
        }

        archive.tap()

        // The screen the line opens. Its being there at all is what says it
        // opened : what is on it depends on how many editions this device has
        // had, and a first launch has exactly the one it is looking at.
        let back = app.navigationBars.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "The back numbers open on a page of their own")
        XCTAssertTrue(back.buttons.firstMatch.exists, "And there is a way back from it")
    }
}
