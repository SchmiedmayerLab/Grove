//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


final class ManagedNavigationStackTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    @MainActor
    func testNavigation() throws { // swiftlint:disable:this function_body_length
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait(for: app.buttons["ManagedNavigationStack"]))
        app.open(target: "ManagedNavigationStack")

        func checkIsAtStep(_ name: String, line: UInt = #line) {
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 1), line: line)
        }

        /// Taps a button, waiting for the ongoing navigation transition to settle first.
        func tap(_ title: String, line: UInt = #line) {
            let button = app.buttons[title]
            XCTAssertTrue(button.wait(for: \.isHittable, toEqual: true, timeout: 5), line: line)
            button.tap()
        }

        func tapBack(line: UInt = #line) {
            let back = app.navigationBars.buttons["Back"]
            XCTAssertTrue(back.wait(for: \.isHittable, toEqual: true, timeout: 5), line: line)
            back.tap()
        }

        let skipNextStepSwitch = app.switches["skipNextStepToggle"].firstMatch

        // we start at step 1, which is the sheet presentation following the launch and therefore slower than the pushes below
        XCTAssertTrue(app.staticTexts["Step 1"].waitForExistence(timeout: 15))

        // go to step 2
        tap("Next Step")
        checkIsAtStep("Step 2")

        // go to step 3
        tap("Next Step")
        checkIsAtStep("Step 3")
        // make sure the "skip next step" toggle ie ON
        XCTAssertTrue(skipNextStepSwitch.waitForExistence(timeout: 2))
        XCTAssertEqual(try XCTUnwrap(skipNextStepSwitch.value as? String), "1")


        // go to step 5, skipping step 4
        tap("Next Step")
        checkIsAtStep("Step 5")

        // go back from step 5. since we skipped 4, we'll end up at 3
        tapBack()
        checkIsAtStep("Step 3")
        // check that the "skip next step" toggls is still ON
        XCTAssertTrue(skipNextStepSwitch.waitForExistence(timeout: 2))
        XCTAssertEqual(try XCTUnwrap(skipNextStepSwitch.value as? String), "1")
        // turn the toggle off, so that we no longer skip step 4
        try skipNextStepSwitch.flipToggle()

        // go to step 4
        tap("Next Step")
        checkIsAtStep("Step 4")

        // go to step 5
        tap("Next Step")
        checkIsAtStep("Step 5")

        // go to step 7, via path A (which does not include the intermediate steps)
        tap("Go to Step 7 (A)")
        checkIsAtStep("Step 7")
        // go back to step 5
        tapBack()
        checkIsAtStep("Step 5")
        // go to step 7, via path B (which does include the intermediate steps)
        tap("Go to Step 7 (B)")
        checkIsAtStep("Step 7")
        // go back to step 6
        tapBack()
        checkIsAtStep("Step 6")
        // go back to step 5
        tapBack()
        checkIsAtStep("Step 5")
        // push a custom view onto the stack
        tap("Append Custom View")
        checkIsAtStep("Custom Step")
        // perform a normal navigation step, to step 6
        tap("Next Step")
        checkIsAtStep("Step 6")
        // go to step 7
        tap("Next Step")
        checkIsAtStep("Step 7")
        // go back to the step before the custom step
        tapBack()
        checkIsAtStep("Step 6")
        tapBack()
        checkIsAtStep("Custom Step")
        tapBack()
        checkIsAtStep("Step 5")
        // go forward using normal navigation. we expect the custom step to be removed form the stack.
        tap("Next Step")
        checkIsAtStep("Step 6")
        // go to step 7
        tap("Next Step")
        checkIsAtStep("Step 7")
        // go to step 8
        tap("Next Step")
        checkIsAtStep("Step 8")
        // go to the next step. since the counter is currently even, we expect to get to "9A (even)"
        tap("Next Step")
        checkIsAtStep("Step 9A (even)")
        // go back, increment the counter, go forward again.
        // we now expect to end up at "9B (odd)"
        tapBack()
        tap("Increment Counter")
        tap("Next Step")
        checkIsAtStep("Step 9B (odd)")
        // go back, increment, expect even
        tapBack()
        tap("Increment Counter")
        tap("Next Step")
        checkIsAtStep("Step 9A (even)")
        // go back, increment, expect odd
        tapBack()
        tap("Increment Counter")
        tap("Next Step")
        checkIsAtStep("Step 9B (odd)")
        tapBack()
        tap("Increment Counter")
        tap("Next Step")
        // go back, increment, expect even
        checkIsAtStep("Step 9A (even)")
        // go to final step.
        tap("Next Step")
    }
}
