//
//  ReaderPanelUITests.swift
//  FlongUITests
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// The reader's own panel, opened the way a reader opens it.
///
/// XCUITest and not a unit test, because what is being asked is a question
/// about the window : that the face in the corner opens the panel, and that the
/// repair for a source removed on another device is in it and can be reached.
/// A unit test can say what the command does and cannot say that anybody can
/// press it.
///
/// Both controls are found by identifier and not by label : a label is
/// translated, and a test that looked for the English would pass here and fail
/// on a device set to the reader's own language.
final class ReaderPanelUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTidyingTheSourcesIsReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let face = app.buttons["reader"].firstMatch
        XCTAssertTrue(face.waitForExistence(timeout: 20), "The reader's own button is in the corner of every section")
        face.tap()

        // The command that puts right a device holding a source another one
        // stopped following. It is under the reader's own face because it is
        // about their devices rather than about any one publisher.
        //
        // Scrolled to rather than waited for : the panel opens on the reader's
        // own face and their name, and a form in SwiftUI builds its rows as
        // they come into view, so a row further down does not exist yet.
        //
        // Dragged half a screen at a time rather than flicked. A flick carries
        // momentum, and a row scrolled past is a row that no longer exists any
        // more than one not reached yet : the test passed or failed on how far
        // the list happened to coast.
        let tidy = app.buttons["tidy-sources"].firstMatch
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))

        for _ in 0..<12 where !tidy.exists {
            lower.press(forDuration: 0.1, thenDragTo: upper)
        }

        XCTAssertTrue(tidy.waitForExistence(timeout: 5), "The repair stands in the reader's own panel")
        XCTAssertTrue(tidy.isHittable, "And it can be pressed")
    }
}
