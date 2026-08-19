//
// This source file is part of the Grove open-source project
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
    func testGroveLicense() throws {
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
        // Tapping "Open in Browser" opens the package's repository URL
        // (https://github.com/SchmiedmayerLab/zstd.git) in Safari. That Safari comes to the
        // foreground is the only behavior GroveLicense actually controls, so that is what we assert.
        // We deliberately do NOT assert on the fetched GitHub page's markup (title / About /
        // repo header): that content is third-party, changes without notice (especially for a fork),
        // and rendering it in mobile Safari on the self-hosted CI runner is subject to network,
        // rate-limiting, and login/consent interstitials — i.e. flaky and out of scope for this test.
        XCTAssert(safari.wait(for: .runningForeground, timeout: 20))
    }
}
