//
//  ServiceImportUITests.swift
//  FlongUITests
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// The way in to an import from another service, opened the way a reader opens
/// it.
///
/// **What this is for is the route rather than the import.** Everything the
/// import itself does is covered against a stubbed server in `FlongTests` ; what
/// no unit test can say is whether a reader arriving with a FreshRSS account can
/// find the screen at all. It shipped once behind a menu nobody thought to open.
///
/// Every element is found by an identifier rather than by a name, since the
/// names are translated and a test that looked for the English would fail on a
/// device set to the reader's own language.
final class ServiceImportUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
            XCUIDevice.shared.orientation = .portrait
        #endif
    }

    @MainActor
    func testTheImportIsReachableFromTheSources() throws {
        let app = XCUIApplication()
        app.launch()

        let sources = app.buttons["sources"].firstMatch
        XCTAssertTrue(
            sources.waitForExistence(timeout: 20), "The sources are one press from every section a reader reads in")
        sources.tap()

        // The three ways to add a source stand under one menu, and this is the
        // fourth : the one a reader arriving from another reader wants first.
        let add = app.buttons["add-source"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), "The panel offers the ways to add a source")
        add.tap()

        let importing = app.buttons["import-freshrss"].firstMatch
        XCTAssertTrue(importing.waitForExistence(timeout: 5), "One of them is an account held elsewhere")
        importing.tap()

        // Nothing is asked for beyond an address, a name and the API password,
        // and nothing is written until the reader has chosen what to take.
        let address = app.textFields["service-address"].firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 5), "The screen opens on the instance to sign in to")
        XCTAssertTrue(address.isHittable, "And it can be typed into")
    }
}
