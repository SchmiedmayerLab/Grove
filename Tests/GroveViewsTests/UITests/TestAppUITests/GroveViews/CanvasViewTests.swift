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


final class CanvasViewTests: XCTestCase {
    override func setUpWithError() throws {
        #if !canImport(PencilKit) || os(macOS)
        throw XCTSkip("PencilKit is not supported on this platform")
        #endif
        #if targetEnvironment(simulator) && (arch(i386) || arch(x86_64))
        throw XCTSkip("PKCanvas view-related tests are currently skipped on Intel-based iOS simulators due to a metal bug on the simulator.")
        #endif
        try super.setUpWithError()
        continueAfterFailure = false
    }
    
    
    @MainActor
    func testCanvas() throws {
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait(for: app.staticTexts["CanvasTest"]))
        app.staticTexts["CanvasTest"].tap()

        let toolPicker = app.otherElements["Drawing-Palette"]

        XCTAssert(app.staticTexts["Did Draw Anything, false"].waitForExistence(timeout: 5))
        XCTAssertFalse(toolPicker.exists)

        let canvasView = app.scrollViews["Canvas"].firstMatch
        XCTAssert(canvasView.wait(for: \.isHittable, toEqual: true, timeout: 5))
        canvasView.swipeRight()
        canvasView.swipeDown()

        let didDraw = app.staticTexts["Did Draw Anything, true"]
        if !didDraw.waitForExistence(timeout: 5) {
            canvasView.swipeRight()
        }
        XCTAssert(didDraw.waitForExistence(timeout: 5))

        XCTAssert(app.buttons["Toggle Tool Picker"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Toggle Tool Picker"].tap()
        XCTAssertTrue(toolPicker.waitForExistence(timeout: 5))
        canvasView.swipeLeft()
        XCTAssertTrue(canvasView.waitForExistence(timeout: 2.0))

        XCTAssert(app.buttons["Toggle Tool Picker"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Toggle Tool Picker"].tap()
        XCTAssertTrue(toolPicker.waitForNonExistence(timeout: 5))
        canvasView.swipeUp()
    }
    
    
    // Tests:
    // - that the CanvasView properly respects the `.disabled(_:)` view modifier,
    // - that mutating the drawing through the binding causes the CanvasView to update its state.
    @MainActor
    func testCanvasDisableAndMutateThroughBinding() throws {
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait(for: app.staticTexts["CanvasTest"]))
        app.staticTexts["CanvasTest"].tap()

        XCTAssert(app.staticTexts["Did Draw Anything, false"].waitForExistence(timeout: 5))

        let canvasView = app.scrollViews["Canvas"].firstMatch
        XCTAssert(canvasView.wait(for: \.isHittable, toEqual: true, timeout: 5))

        XCTAssert(app.buttons["Enable/Disable Canvas, true"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Enable/Disable Canvas"].tap()
        XCTAssert(app.buttons["Enable/Disable Canvas, false"].waitForExistence(timeout: 2))
        // the "swipe down" action here will, since the CanvasView is disabled, attempt to dismiss the sheet,
        // which will fail since we have explicitly disabled the CanvasTestView's interactive dismissal.
        canvasView.swipeDown()
        XCTAssert(app.staticTexts["Did Draw Anything, false"].waitForExistence(timeout: 2))

        XCTAssert(app.buttons["Enable/Disable Canvas"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Enable/Disable Canvas"].tap()
        XCTAssert(app.buttons["Enable/Disable Canvas, true"].waitForExistence(timeout: 2))
        canvasView.swipeRight()
        canvasView.swipeDown()
        XCTAssert(app.staticTexts["Did Draw Anything, true"].waitForExistence(timeout: 2))

        XCTAssert(app.buttons["Clear"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Clear"].tap()
        XCTAssert(app.staticTexts["Did Draw Anything, false"].waitForExistence(timeout: 2))
    }
    
    
    // Tests that:
    // - selecting a different tool via PencilKit's picker properly updates the binding
    // - selecting a different tool by updating the binding properly updated PencilKit's picker
    @MainActor
    func testCanvasToolBinding() throws {
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait(for: app.staticTexts["CanvasTest"]))
        app.staticTexts["CanvasTest"].tap()

        let toolInfo = app.staticTexts["ToolInfo"]
        let toolPicker = app.otherElements["Drawing-Palette"]
        var currentToolDesc: String {
            toolInfo.value as? String ?? ""
        }

        XCTAssert(toolInfo.waitForExistence(timeout: 5))
        XCTAssertFalse(toolPicker.exists)

        XCTAssert(app.buttons["Toggle Tool Picker"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        app.buttons["Toggle Tool Picker"].tap()
        XCTAssertTrue(toolPicker.waitForExistence(timeout: 5))

        /// Waits for the tool info label to catch up with the selection, which the binding propagates asynchronously.
        func assertToolInfo(_ predicateFormat: String, _ args: Any..., line: UInt = #line) {
            let predicate = NSPredicate(format: predicateFormat, argumentArray: args)
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: toolInfo)
            XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 2), .completed, "actual: \(currentToolDesc)", line: line)
        }

        /// Selects a tool in the picker and waits for the picker to reflect the new selection.
        func selectTool(_ name: String, line: UInt = #line) {
            let tool = toolPicker.buttons[name]
            XCTAssert(tool.wait(for: \.isHittable, toEqual: true, timeout: 2), line: line)
            tool.tap()
            XCTAssert(tool.wait(for: \.isSelected, toEqual: true, timeout: 2), line: line)
        }

        assertToolInfo("value CONTAINS %@", "PKInkingTool")
        assertToolInfo("value CONTAINS %@", "com.apple.ink.pen color=UIExtendedSRGBColorSpace 1 0 0 1 width=10")
        XCTAssert(toolPicker.buttons["Pen"].isSelected)

        selectTool("Marker")
        XCTAssertFalse(toolPicker.buttons["Pen"].isSelected)
        XCTAssertFalse(toolPicker.buttons["Eraser"].isSelected)
        assertToolInfo("value CONTAINS %@", "PKInkingTool")
        assertToolInfo("value CONTAINS %@", "com.apple.ink.marker")

        selectTool("Eraser")
        XCTAssertFalse(toolPicker.buttons["Pen"].isSelected)
        XCTAssertFalse(toolPicker.buttons["Marker"].isSelected)
        assertToolInfo("value CONTAINS %@", "PKEraserTool")

        do {
            let oldTool = currentToolDesc
            XCTAssert(app.buttons["Random Tool"].wait(for: \.isHittable, toEqual: true, timeout: 2))
            app.buttons["Random Tool"].tap()
            assertToolInfo("NOT value == %@", oldTool)
        }
    }
}
