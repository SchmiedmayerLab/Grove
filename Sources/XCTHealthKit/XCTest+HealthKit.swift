//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import XCTest


struct XCTHealthKitError: Error {
    // periphery:ignore - surfaces in XCTest failure output via Error reflection
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
}


extension XCUIApplication {
    /// The Apple Health app
    public static var healthApp: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.Health")
    }
}


extension XCUIElement {
    /// Waits for the element to become hittable and taps it.
    ///
    /// An element that exists but never becomes hittable is usually just below the fold, so it is tapped anyway
    /// and left to `tap()`'s own scroll-to-visible.
    func tapWhenHittable(timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        if !wait(for: \.isHittable, toEqual: true, timeout: timeout) {
            XCTAssert(exists, "\(debugDescription) never appeared", file: file, line: line)
        }
        tap()
    }
}


extension XCUIApplication {
    /// Returns the `XCUIApplication`'s bundle identifier.
    nonisolated public var bundleIdentifier: String {
        let desc = self.description
        for prefix in ["Application '", "Target Application '"] {
            guard desc.hasPrefix(prefix) && desc.hasSuffix("'") else {
                continue
            }
            return String(desc.dropFirst(prefix.count).dropLast())
        }
        return ""
    }
    
    /// Checks whether the app is in fact apple's Health app.
    nonisolated public var isHealthApp: Bool {
        self.bundleIdentifier == "com.apple.Health"
    }
    
    /// Asserts that this is the Health app.
    nonisolated public func assertIsHealthApp() throws {
        guard isHealthApp else {
            throw XCTHealthKitError("App \(bundleIdentifier) is not the Health app!")
        }
    }
}


extension XCUIApplication {
    /// Detects and dismisses the HealthKit Authorization sheet.
    ///
    /// - parameter timeout: how long the function should wait for the sheet to appear.
    /// - parameter requireSheetToAppear: Whether the function should require the sheet to appear, i.e. whether it should fail if no Health permissions sheet is presented within the `timeout`.
    public func handleHealthKitAuthorization(
        timeout: TimeInterval = 20,
        requireSheetToAppear: Bool = false
    ) {
        let sheet = self.navigationBars["Health Access"]
        guard sheet.waitForExistence(timeout: timeout) else {
            if requireSheetToAppear {
                XCTFail("No Health permissions sheet appeared within the timeout (\(timeout) sec)")
            }
            return
        }
        // The nav bar renders before healthd has populated the type list, so the row has to be waited for.
        let turnOnAll = self.tables.staticTexts["Turn On All"]
        XCTAssert(turnOnAll.wait(for: \.isHittable, toEqual: true, timeout: 10), "The Health permissions sheet did not finish loading")
        turnOnAll.tap()
        let allow = self.buttons["Allow"]
        XCTAssert(allow.wait(for: \.isHittable, toEqual: true, timeout: 10), "'Allow' never became hittable")
        allow.tap()
        if !sheet.waitForNonExistence(timeout: 10) {
            // The tap can land before the toggles commit, which leaves 'Allow' disabled and the tap a no-op.
            allow.tap()
            XCTAssert(sheet.waitForNonExistence(timeout: 10), "The Health permissions sheet did not dismiss")
        }
    }
}
