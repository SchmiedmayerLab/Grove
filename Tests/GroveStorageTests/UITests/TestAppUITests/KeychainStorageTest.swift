//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


final class KeychainStorageTests: XCTestCase {
    @MainActor
    func testKeychainStorage() throws {
        let app = XCUIApplication()
        let keychainStorage = app.buttons["Keychain Storage"]
        XCTAssert(app.launchAndWait(for: keychainStorage), "The app did not come up.")

        keychainStorage.tap()

        XCTAssertTrue(app.staticTexts["Passed"].waitForExistence(timeout: 2))
    }
}
