//
//  ModelSettingsUITests.swift
//  FlongUITests
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// The page where a reader says which model writes what.
///
/// Every control is found by its identifier and never by its label : the labels
/// are translated, and a test that looked for the English would pass here and
/// fail on a device set to the reader's own language.
///
/// Nothing here reaches a network. The address is `models.example.com` and the
/// key is obviously not one, and the test button is never pressed.
final class ModelSettingsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func openModels(_ app: XCUIApplication) {
        let face = app.buttons["reader"].firstMatch
        XCTAssertTrue(face.waitForExistence(timeout: 20))
        face.tap()

        let models = app.buttons["reader-models"].firstMatch
        XCTAssertTrue(models.waitForExistence(timeout: 5), "the models row stands in the panel")
        models.tap()
    }

    func testTheFourThingsAModelDoesAreThere() {
        let app = XCUIApplication()
        app.launch()
        openModels(app)

        for task in ["headlines", "subjects", "editions", "search"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["model-task-\(task)"].firstMatch.waitForExistence(timeout: 5),
                "\(task) has a row of its own"
            )
        }
        XCTAssertTrue(app.buttons["add-provider"].firstMatch.exists, "a provider can be added")
    }

    /// A provider written down appears in the list under the name the reader
    /// gave it.
    ///
    /// **What this does not do is press the row.** Whether a stored key is
    /// shown again is a rule about a draft, and it is held where it lives : a
    /// test that scrolled a virtualized list to find out would be testing the
    /// list. See `ProviderDraftTests`.
    func testAProviderCanBeWrittenDown() {
        let app = XCUIApplication()
        app.launch()
        openModels(app)

        // Whatever happens below, the account this writes down is taken back
        // out : these settings are the reader's own, and a test that left one
        // behind would be a test that configured their application for them.
        addTeardownBlock { Self.removeEveryProvider(app) }

        app.buttons["add-provider"].firstMatch.tap()

        let name = app.textFields["provider-name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the editor opened")
        name.tap()
        name.typeText("Mine")

        // Emptied a character at a time rather than through the editing menu,
        // whose items are translated : looking for `Select All` found nothing
        // on a French device and left the field's default in front of what was
        // typed after it.
        let address = app.textFields["provider-address"].firstMatch
        address.tap()
        address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 60))
        address.typeText("https://models.example.com/v1")

        let key = app.secureTextFields["provider-key"].firstMatch
        XCTAssertTrue(key.exists, "a new provider asks for a key")
        key.tap()
        key.typeText("not-a-real-key")

        let model = app.textFields["provider-model"].firstMatch
        XCTAssertTrue(model.exists, "a model can be typed when the service has not been asked")
        model.tap()
        model.typeText("a-model")

        let save = app.buttons["provider-save"].firstMatch
        XCTAssertTrue(save.isEnabled, "the sheet has a name, an address and a model")
        save.tap()

        // The sheet is out of the way and the account stands in the list. By
        // the prefix the rows carry and not by `provider-`, which the row
        // leading to the outgoing calls also begins with.
        XCTAssertFalse(save.waitForExistence(timeout: 3), "the editor closed and the panel stayed open")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'provider-row-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the provider stands in the list")
        XCTAssertTrue(app.staticTexts["Mine"].firstMatch.exists, "under the name the reader gave it")
    }

    ///
    /// **Waited on rather than swiped at.** Swiping in a loop scrolls the list
    /// out from under the very row being waited for, which is how this spent a
    /// whole timeout looking at a row it had just pushed off the top.
    private static func wait(untilHittable element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 8)
        -> Bool
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.isHittable { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return element.isHittable
    }

    /// Takes back every account the tests wrote down.
    private static func removeEveryProvider(_ app: XCUIApplication) {
        while true {
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'provider-row-'")).firstMatch
            guard row.waitForExistence(timeout: 2), wait(untilHittable: row, in: app, timeout: 6) else { return }
            row.tap()

            let remove = app.buttons["provider-remove"].firstMatch
            guard remove.waitForExistence(timeout: 3) else { return }
            remove.tap()

            let confirm = app.buttons["provider-remove-confirm"].firstMatch
            guard confirm.waitForExistence(timeout: 3) else { return }
            confirm.tap()
        }
    }
}
