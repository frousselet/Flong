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
/// about the window : that the face in the corner opens the panel, that the
/// panel leads to its pages, and that the repair for a source removed on
/// another device is on one of them and can be reached. A unit test can say
/// what the command does and cannot say that anybody can press it.
///
/// Every control is found by identifier and not by label : a label is
/// translated, and a test that looked for the English would pass here and fail
/// on a device set to the reader's own language.
final class ReaderPanelUITests: XCTestCase {

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
    func testTidyingTheSourcesIsReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let face = app.buttons["reader"].firstMatch
        XCTAssertTrue(face.waitForExistence(timeout: 20), "The reader's own button is in the corner of every section")
        face.tap()

        // The panel shows and does not set : every setting there is stands
        // behind one of its rows, and what this one leads to is what this
        // device and the reader's iCloud hold.
        let data = app.buttons["reader-data"].firstMatch
        XCTAssertTrue(data.waitForExistence(timeout: 5), "The panel leads to the page about the reader's own data")
        data.tap()

        // The command that puts right a device holding a source another one
        // stopped following. It is under the reader's own face because it is
        // about their devices rather than about any one publisher.
        let tidy = app.buttons["tidy-sources"].firstMatch
        XCTAssertTrue(tidy.waitForExistence(timeout: 5), "The repair stands on that page")
        XCTAssertTrue(tidy.isHittable, "And it can be pressed")
    }

    /// The repair for an iCloud out of step is offered to everybody.
    ///
    /// It shipped behind `#if DEBUG` for a while, so a release build had the
    /// one command that puts a drifted device right and no way to reach it.
    /// This is what notices if it goes back behind a build flag.
    @MainActor
    func testResynchronizingIsReachableInEveryBuild() throws {
        let app = XCUIApplication()
        app.launch()

        let face = app.buttons["reader"].firstMatch
        XCTAssertTrue(face.waitForExistence(timeout: 20))
        face.tap()

        let data = app.buttons["reader-data"].firstMatch
        XCTAssertTrue(data.waitForExistence(timeout: 5))
        data.tap()

        let repair = app.buttons["force-synchronization"].firstMatch
        XCTAssertTrue(repair.waitForExistence(timeout: 5), "The repair stands in `Your data`")
        XCTAssertTrue(repair.isHittable, "And it can be pressed")
    }

    /// Every subject the panel names leads somewhere.
    ///
    /// The rows are the whole of the panel's purpose : it shows the reader and
    /// hands them off, so a row that led nowhere would be a subject with no
    /// page behind it.
    @MainActor
    func testEverySubjectLeadsToItsPage() throws {
        let app = XCUIApplication()
        app.launch()

        let face = app.buttons["reader"].firstMatch
        XCTAssertTrue(face.waitForExistence(timeout: 20))
        face.tap()

        // The three that moved here out of the opposite corner stand first,
        // then the reader themselves, then what is theirs beyond this device.
        let rows = [
            "sources", "subjects", "notifications",
            "reader-profile", "reader-appearance", "reader-editions",
            "reader-popular", "reader-sites", "reader-about",
        ]
        for identifier in rows {
            let row = app.buttons[identifier].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), "\(identifier) stands in the panel")
            row.tap()

            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5), "\(identifier) opened a page with a way back")
            back.tap()
        }
    }
}
