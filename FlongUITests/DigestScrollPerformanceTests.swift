//
//  DigestScrollPerformanceTests.swift
//  FlongUITests
//
//  Created by François Rousselet on 04/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// What the front page costs to scroll.
///
/// **A number rather than an impression.** A reader reported the page dropping
/// frames badly enough to be unusable, and every candidate for it is plausible :
/// an animation on a lazy stack, a transition on a row, a value decoded from a
/// property list in a view body. Reasoning tells them apart badly. This tells
/// them apart by measuring the same gesture before and after.
///
/// **The processor's time and not the clock's.** The system's own
/// `scrollingAndDecelerationMetric` measures how long the scroll lasted, which
/// is almost entirely the gesture and the deceleration curve : a page dropping
/// every other frame takes exactly as long to coast as one that does not, so
/// that number barely moves and says nothing. What a dropped frame is made of
/// is work that did not fit in sixteen milliseconds, so what is measured here
/// is the work : the processor time spent while the same gesture is performed.
/// The signpost duration is kept beside it as the sanity check that the gesture
/// itself was the same one.
///
/// It needs a page with something on it. A device with no feeds scrolls nothing
/// and the measure would be of an empty screen, so the test says so and stops
/// rather than reporting a fast page that is fast because it is blank.
final class DigestScrollPerformanceTests: XCTestCase {

    override func setUpWithError() throws {
        // Opt in, like the search corpus and for the same reason : five measured
        // passes over a real page is a minute, and nobody should wait for it to
        // find out that a panel stopped opening. `FLONG_PERFORMANCE` is what
        // the search suite is gated on and what continuous integration will set
        // once there is any.
        //
        // ```bash
        // FLONG_PERFORMANCE=1 xcodebuild test -project Flong.xcodeproj -scheme Flong \
        //   -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
        //   -only-testing:FlongUITests/DigestScrollPerformanceTests
        // ```
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["FLONG_PERFORMANCE"] == nil,
            "Set FLONG_PERFORMANCE to measure the scroll"
        )
        continueAfterFailure = false
        #if os(iOS)
            XCUIDevice.shared.orientation = .portrait
        #endif
    }

    @MainActor
    func testScrollingTheDigest() throws {
        let app = XCUIApplication()
        app.launch()

        // The page has to have arrived. The edition is written behind the
        // launch, and measuring while the model is still working would be
        // measuring the model.
        let page = app.scrollViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "The front page is there")
        try XCTSkipUnless(app.images.count > 0, "This device has nothing on its front page to scroll")

        measure(metrics: [XCTCPUMetric(), XCTOSSignpostMetric.scrollingAndDecelerationMetric]) {
            page.swipeUp(velocity: .fast)
            page.swipeDown(velocity: .fast)
        }
    }
}
