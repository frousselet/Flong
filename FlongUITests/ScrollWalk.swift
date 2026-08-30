import XCTest
final class ScrollWalk: XCTestCase {
    func testLongScroll() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Flux"].firstMatch.tap()
        sleep(3)
        for _ in 0..<40 { app.swipeUp(velocity: .fast) }
        sleep(2)
        for _ in 0..<20 { app.swipeDown(velocity: .fast) }
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground, "the application is no longer running")
        print("STATE=\(app.state.rawValue)")
    }
}
