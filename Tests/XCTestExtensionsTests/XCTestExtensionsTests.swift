//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


final class XCTestExtensionsTests: XCTestCase {
    func testXCTAssertThrowsPositive() async throws {
        try await XCTAssertThrowsErrorAsync({ throw CancellationError() }()) { error in
            _ = try XCTUnwrap(error as? CancellationError)
        }
    }
}
