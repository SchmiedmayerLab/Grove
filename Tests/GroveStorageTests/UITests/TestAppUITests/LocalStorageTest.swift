//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


final class LocalStorageTests: XCTestCase {
    @MainActor
    func testLocalStorage() throws {
        let app = XCUIApplication()
        let localStorage = app.buttons["Local Storage"]
        XCTAssert(app.launchAndWait(for: localStorage), "The app did not come up.")
        localStorage.tap()
        XCTAssertTrue(app.staticTexts["Passed"].waitForExistence(timeout: 2))
    }


    @MainActor
    func testLocalStorageLiveUpdates() throws {
        let app = XCUIApplication()

        func assertNumberEquals(_ expected: Int, file: StaticString = #filePath, line: UInt = #line) {
            let pred = NSPredicate(format: "label MATCHES %@", "Number.*\(expected)")
            XCTAssertTrue(app.staticTexts.matching(pred).element.waitForExistence(timeout: 0.5), file: file, line: line)
        }

        let liveUpdates = app.buttons["Local Storage (Live Update)"]
        XCTAssert(app.launchAndWait(for: liveUpdates), "The app did not come up.")
        liveUpdates.tap()

        let doubleNumber = app.buttons["Double Number"]
        XCTAssert(doubleNumber.wait(for: \.isHittable, toEqual: true, timeout: 10), "The live update test view did not appear.")

        let numbers = (0..<17).map { _ in Int.random(in: 0..<5) }
        for number in numbers {
            let button = app.buttons["\(number)"]
            XCTAssert(button.wait(for: \.isHittable, toEqual: true, timeout: 2))
            button.tap()
            assertNumberEquals(number)
        }
        doubleNumber.tap()
        assertNumberEquals(numbers[numbers.endIndex - 1] * 2)
    }
}
