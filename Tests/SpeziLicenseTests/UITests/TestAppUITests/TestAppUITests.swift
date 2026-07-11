//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest


class TestAppUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }
    

    @MainActor
    func testSpeziLicense() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2.0))

        XCTAssertTrue(app.buttons["TestApp, MIT, Version: 1.0"].waitForExistence(timeout: 2))

        do {
            let button = app.buttons.matching(NSPredicate(
                format: "label LIKE 'zstd, *Version: 1.*'"
            )).element
            var numScrolls = 0
            while true {
                guard numScrolls < 10 else {
                    throw XCTestError(.failureWhileWaiting, userInfo: [
                        NSLocalizedDescriptionKey: "Unable to find button"
                    ])
                }
                if !button.exists {
                    app.swipeUp()
                    numScrolls += 1
                } else {
                    button.tap()
                    break
                }
            }
        }
        
        sleep(1)
        print(app.debugDescription)
        let licensePred = NSPredicate(
            format: "label CONTAINS 'Copyright (c) Meta Platforms, Inc. and affiliates. All rights reserved.'"
        )
        XCTAssert(app.staticTexts.matching(licensePred).element.exists)
        app.navigationBars.buttons["Open in Browser"].tap()
        
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssert(
            safari.staticTexts["Zstandard - Fast real-time compression algorithm"].waitForExistence(timeout: 20)
        )
    }
}
