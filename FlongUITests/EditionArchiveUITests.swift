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
/// **Under the page, and not behind a calendar.** They stood behind a button in
/// the corner, which is a control that has to be found, opened, chosen from and
/// closed to get at a page that was already written. A reader does not open a
/// drawer to find yesterday's paper : it is under today's. So the question this
/// asks is a scrolling question, and XCUITest is the only thing that can ask
/// it.
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

    /// How many flicks it is worth spending to reach the seam.
    ///
    /// A long paper is twenty stories with their pictures, and a flick moves
    /// about half a screen, so the seam can be a good way down. Bounded all the
    /// same : a loop that scrolled until it found something would hang rather
    /// than fail on a page that has no seam at all.
    private static let flicks = 60

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
            XCUIDevice.shared.orientation = .portrait
        #endif
    }

    @MainActor
    func testTheBackNumbersAreUnderThePage() throws {
        let app = XCUIApplication()
        app.launch()

        let page = app.scrollViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "The digest is the section the application opens on")

        // No edition on this device, which is a legitimate state and one the
        // page has to say out loud rather than render blank. There is no
        // history under a page that does not exist.
        guard app.otherElements["edition-head"].waitForExistence(timeout: 20) else {
            XCTAssertTrue(app.staticTexts.count > 0, "A page with no edition still says something")
            return
        }

        // Any kind of element : the masthead combines its children for
        // VoiceOver, so what carries the identifier is a text rather than the
        // container it was written on.
        let seam = app.descendants(matching: .any)["back-numbers"]
        var flicks = 0
        while !seam.exists, flicks < Self.flicks {
            page.swipeUp()
            flicks += 1
        }

        XCTAssertTrue(seam.exists, "Today's paper ends at a seam, and the back numbers are under it")

        // **Closed until it is asked for.** A year of back numbers that a flick
        // could carry the reader into would be a page whose bottom nobody
        // trusts, so the paper ends where it ends.
        let headline = app.buttons["back-number-headline"]
        XCTAssertFalse(headline.exists, "The archive is not simply under the page, it is pulled for")

        // And the page says it has a bottom worth reaching : a gesture nobody
        // knows about is a feature nobody has.
        XCTAssertTrue(
            app.descendants(matching: .any)["pull-mark"].exists,
            "The foot of the page carries the mark that says to pull"
        )

        // A slow drag with a hold at the end, which is a pull past the foot of
        // the page rather than a flick. More than one, because a gesture that
        // has to reach past the end of the content is the one kind of gesture a
        // simulator does not always land the first time.
        for _ in 0..<4 where !headline.exists {
            let from = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let to = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            from.press(forDuration: 0.15, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 1.0)
        }

        XCTAssertTrue(headline.exists, "Pulling past the foot of the page opens the back numbers")
    }
}
