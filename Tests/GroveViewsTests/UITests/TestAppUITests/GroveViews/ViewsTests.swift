//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFoundation
import XCTest
import XCTestExtensions


final class ViewsTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    @MainActor
    func testGeometryReader() throws {
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait())

        app.open(target: "GroveViews")

        let geometryReader = app.buttons["Geometry Reader"]
        XCTAssert(geometryReader.wait(for: \.isHittable, toEqual: true, timeout: 5))
        geometryReader.tap()

        XCTAssert(app.staticTexts["300.000000"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["200.000000"].exists)
    }

    @MainActor
    func testLabel() throws {
        #if os(macOS)
        throw XCTSkip("Label is not supported on non-UIKit platforms")
        #endif
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait())

        app.open(target: "GroveViews")

        let label = app.collectionViews.buttons["Label"]
        XCTAssert(label.wait(for: \.isHittable, toEqual: true, timeout: 5))
        label.tap()

        // The string value needs to be searched for in the UI.
        // swiftlint:disable:next line_length
        let text = "This is a label ... An other text. This is longer and we can check if the justified text works as expected. This is a very long text."
        // both labels render the same text; wait for the second one before counting them
        let renderedLabels = app.staticTexts.matching("label CONTAINS %@", "This is longer and we can check if the justified text works as expected.")
        XCTAssert(renderedLabels.element(boundBy: 1).waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.allElementsBoundByIndex.filter { $0.label.replacingOccurrences(of: "\n", with: " ").contains(text) }.count, 2)
    }
    
    @MainActor
    func testLazyText() throws {
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait())

        app.open(target: "GroveViews")

        let lazyText = app.buttons["Lazy Text"]
        XCTAssert(lazyText.wait(for: \.isHittable, toEqual: true, timeout: 5))
        lazyText.tap()

        XCTAssert(app.staticTexts["This is a long text ..."].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["And some more lines ..."].exists)
        XCTAssert(app.staticTexts["And a third line ..."].exists)
        XCTAssert(app.staticTexts["An other lazy text ..."].exists)
    }

    @MainActor
    func testButtonsView() throws {
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait())

        app.open(target: "GroveViews", waitingFor: app.buttons["Geometry Reader"])

        app.collectionViews.firstMatch.swipeUp() // on visionOS and on iPads the AsyncButton is out of the frame due to the window size

        let buttons = app.buttons["Buttons"]
        XCTAssert(buttons.wait(for: \.isHittable, toEqual: true, timeout: 5))
        buttons.tap()

        XCTAssert(app.buttons["Hello World"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Hello World"].tap()

        XCTAssert(app.staticTexts["Action executed"].waitForExistence(timeout: 2))
        XCTAssert(app.buttons["Reset"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Reset"].tap()

        XCTAssert(app.buttons["Hello Throwing World"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Hello Throwing World"].tap()

#if os(macOS)
        let alerts = app.sheets
#else
        let alerts = app.alerts
#endif

        XCTAssert(alerts.staticTexts["Custom Error"].waitForExistence(timeout: 2))
        XCTAssert(alerts.staticTexts["Error was thrown!"].waitForExistence(timeout: 1))
        XCTAssert(alerts.buttons["OK"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        alerts.buttons["OK"].tap()

        XCTAssert(app.buttons["Hello Throwing World"].wait(for: \.isEnabled, toEqual: true, timeout: 2))

        let infoButton = app.buttons.matching(identifier: "info-button").firstMatch
        XCTAssert(infoButton.wait(for: \.isHittable, toEqual: true, timeout: 2))
        infoButton.tap()

        XCTAssertFalse(alerts.staticTexts["Custom Error"].exists)

        XCTAssert(app.staticTexts["Action executed"].waitForExistence(timeout: 2))
        XCTAssert(app.buttons["Reset"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Reset"].tap()

        XCTAssert(app.buttons["State Captured"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["State Captured"].tap()

        XCTAssert(app.staticTexts["Captured Hello World"].waitForExistence(timeout: 0.5))
    }

    @MainActor
    func testAsyncButtonDebounce() throws {
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait())

        app.open(target: "GroveViews", waitingFor: app.buttons["Geometry Reader"])
        app.collectionViews.firstMatch.swipeUp()

        let debounceTest = tappableElement(named: "Async Button Debounce", in: app)
        debounceTest.tap()

        let fastAction = tappableElement(named: "Fast Debounced Action", in: app)
        fastAction.tap()
        XCTAssert(app.staticTexts["Fast Completed: true"].waitForExistence(timeout: 2))
        // the action finishes well within the 2s debounce duration, so no processing indicator may show up during it
        XCTAssertFalse(app.activityIndicators.firstMatch.waitForExistence(timeout: 3))

        let slowAction = tappableElement(named: "Slow Debounced Action", in: app)
        slowAction.tap()
        XCTAssert(app.activityIndicators.firstMatch.waitForExistence(timeout: 4))
        XCTAssert(app.staticTexts["Slow Completed: true"].waitForExistence(timeout: 7))
        XCTAssert(app.activityIndicators.firstMatch.waitForNonExistence(timeout: 4))
    }

    @MainActor
    private func tappableElement(named name: String, in app: XCUIApplication, timeout: TimeInterval = 2) -> XCUIElement {
        let button = app.buttons[name]
        if button.wait(for: \.isHittable, toEqual: true, timeout: timeout) {
            return button
        }

        let element = app.descendants(matching: .any)[name]
        XCTAssertTrue(
            element.wait(for: \.isHittable, toEqual: true, timeout: timeout),
            "Unable to find \(name) in the debounce test fixture."
        )
        return element
    }

    @MainActor
    func testAsyncButtonInToolbar() throws {
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait(for: app.buttons["AsyncButton Toolbar Behaviour"]))
        app.buttons["AsyncButton Toolbar Behaviour"].tap()
        XCTAssert(app.staticTexts["Did cancel, false"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Did tap, false"].waitForExistence(timeout: 2))
        let cancelButton = app.navigationBars["AsyncButtonInToolbar"].buttons["Role Only Cancel"]
        XCTAssert(cancelButton.waitForExistence(timeout: 2))
        XCTAssertEqual(cancelButton.label, "Cancel")
        cancelButton.tap()
        XCTAssert(app.staticTexts["Did cancel, true"].waitForExistence(timeout: 2))

        let toolbarButton = app.navigationBars["AsyncButtonInToolbar"].buttons["Tap Me!"]
        XCTAssert(toolbarButton.wait(for: \.isHittable, toEqual: true, timeout: 2))
        toolbarButton.tap()
        XCTAssert(app.staticTexts["Did tap, true"].waitForExistence(timeout: 2))

        let overlayButton = app.buttons["Role Only Overlay"]
        XCTAssert(overlayButton.waitForExistence(timeout: 2))
        XCTAssertEqual(overlayButton.label, "Done")
        overlayButton.tap()
        XCTAssert(app.activityIndicators.firstMatch.waitForExistence(timeout: 2))
        XCTAssertFalse(overlayButton.isEnabled)
        XCTAssert(app.staticTexts["Overlay completed, true"].waitForExistence(timeout: 4))
        XCTAssert(app.activityIndicators.firstMatch.waitForNonExistence(timeout: 2))
        XCTAssertTrue(overlayButton.isEnabled)

        let listRowButton = app.buttons["Role Only List Row"]
        XCTAssert(listRowButton.waitForExistence(timeout: 2))
        XCTAssertEqual(listRowButton.label, "Done")
        listRowButton.tap()
        XCTAssert(app.activityIndicators.firstMatch.waitForExistence(timeout: 2))
        XCTAssertFalse(listRowButton.isEnabled)
        XCTAssert(app.staticTexts["List row completed, true"].waitForExistence(timeout: 4))
        XCTAssert(app.activityIndicators.firstMatch.waitForNonExistence(timeout: 2))
        XCTAssertTrue(listRowButton.isEnabled)
    }

    @MainActor
    func testListRowAccessibility() throws {
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait())
        app.open(target: "GroveViews", waitingFor: app.buttons["Geometry Reader"])
        app.collectionViews.firstMatch.swipeUp() // out of the window on visionOS and iPadOS

        XCTAssert(app.buttons["List Row"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["List Row"].tap()

        XCTAssert(app.staticTexts["Hello, World"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testManagedViewUpdateTests() {
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait())

        app.open(target: "GroveViews", waitingFor: app.buttons["Geometry Reader"])

        app.collectionViews.firstMatch.swipeUp() // out of the window on visionOS and iPadOS

        XCTAssert(app.buttons["Managed View Update"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Managed View Update"].tap()

        XCTAssert(app.navigationBars.staticTexts["Managed View Update"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["Value, 0"].waitForExistence(timeout: 2.0))
        XCTAssert(app.buttons["Increment"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))

        app.buttons["Increment"].tap()
        XCTAssert(app.staticTexts["Value, 0"].waitForExistence(timeout: 2.0))
        XCTAssertFalse(app.staticTexts["Value, 1"].exists)

        XCTAssert(app.buttons["Refresh"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Refresh"].tap()
        XCTAssert(app.staticTexts["Value, 1"].waitForExistence(timeout: 2.0))

        app.buttons["Increment"].tap()
        XCTAssert(app.staticTexts["Value, 1"].waitForExistence(timeout: 2.0))
        XCTAssertFalse(app.staticTexts["Value, 2"].exists)

        XCTAssert(app.buttons["Refresh in 2s"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Refresh in 2s"].tap()
        XCTAssert(app.staticTexts["Value, 2"].waitForExistence(timeout: 4.0))
    }

    @MainActor
    func testPickers() throws {
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait())

        app.open(target: "GroveViews", waitingFor: app.buttons["Geometry Reader"])

        app.collectionViews.firstMatch.swipeUp() // out of the window on visionOS and iPadOS

        XCTAssert(app.buttons["Picker"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Picker"].tap()

        XCTAssert(app.navigationBars.staticTexts["Picker"].waitForExistence(timeout: 2.0))

        XCTAssert(app.buttons["Selection, None"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Selection, None"].tap()

        XCTAssert(app.buttons["None"].waitForExistence(timeout: 2.0))
        XCTAssert(app.buttons["First"].exists)
        XCTAssert(app.buttons["Second"].exists)

        XCTAssert(app.buttons["First"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["First"].tap()

        XCTAssert(app.buttons["Selection, First"].waitForExistence(timeout: 2.0))

        // OPTION SET

#if os(visionOS)
        XCTAssert(app.staticTexts["nothing selected"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.staticTexts["nothing selected"].tap()
#else
        XCTAssert(app.buttons["Option Set, nothing selected"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Option Set, nothing selected"].tap()
#endif

        XCTAssert(app.buttons["Option 1"].firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Option 1"].firstMatch.tap()
    }
}


// MARK: Utils

func sleep(for duration: Duration) {
    usleep(UInt32(duration.timeInterval * 1000000))
}
