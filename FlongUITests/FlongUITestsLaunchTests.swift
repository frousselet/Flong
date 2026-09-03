//
//  FlongUITestsLaunchTests.swift
//  FlongUITests
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

final class FlongUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Portrait, whatever the simulator was left in. XCUITest reports an
        // element's frame in the device's own space and taps in the screen's :
        // in landscape the two come apart, so a tap aimed at one row of a sheet
        // lands on another and the test fails somewhere it never went near.
        // The iPhone is portrait only and cannot get there ; the iPad turns,
        // and these suites run on it.
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
