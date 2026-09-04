//
//  TopicEditorUITests.swift
//  FlongUITests
//
//  Created by François Rousselet on 04/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// Writing a subject, and picking the mark it wears.
///
/// XCUITest and not a unit test, because the question is about the window : the
/// subjects are behind the reader's own menu now, adding one opens a sheet over
/// that sheet, and the palette is drawn in it. None of that is answerable by a
/// function taking names and giving back a value.
///
/// **It writes nothing.** The editor is opened and cancelled : a test that added
/// a subject would leave it in the store of whichever device ran it, and the
/// simulator this runs on holds the author's own feeds.
///
/// Every control is found by identifier and not by label : a label is
/// translated, and a test that looked for the English would pass here and fail
/// on a device set to the reader's own language.
final class TopicEditorUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
            XCUIDevice.shared.orientation = .portrait
        #endif
    }

    @MainActor
    func testASubjectIsWrittenWithAMark() throws {
        let app = XCUIApplication()
        app.launch()

        let face = app.buttons["reader"].firstMatch
        XCTAssertTrue(face.waitForExistence(timeout: 20), "The reader's own button is in the corner of every section")
        face.tap()

        let subjects = app.buttons["subjects"].firstMatch
        XCTAssertTrue(subjects.waitForExistence(timeout: 5), "The menu leads to every subject there is")
        subjects.tap()

        let add = app.buttons["add-subject"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), "A subject can be written from the panel")
        add.tap()

        // A subject is a word and a glyph, and the sheet asks for both at once :
        // added without the glyph it would wear the tag until the reader found
        // their way back to change it.
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The sheet asks for the name")

        // The palette is what the sections wear : a picker of every symbol the
        // system has would be a thousand glyphs and a search field.
        let mark = app.buttons["newspaper"].firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 5), "And offers the marks the sections wear")
        XCTAssertTrue(mark.isHittable, "One of which can be picked")

        // Nothing is written : the store this ran against is somebody's own.
        app.buttons["cancel"].firstMatch.tap()
    }
}
