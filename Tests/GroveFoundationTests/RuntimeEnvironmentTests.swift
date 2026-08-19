//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

import Foundation
import GroveFoundation
import Testing
import XCTest


@Suite
struct RuntimeEnvironmentTests {
    @Test
    func sandbox() {
        #if os(macOS) || targetEnvironment(macCatalyst)
        // by default, the tests aren't sandboxed on macOS
        #expect(!ProcessInfo.isRunningInSandbox)
        #else
        #expect(ProcessInfo.isRunningInSandbox)
        #endif
    }
    
    @Test
    func runningInXCTest() {
        #expect(ProcessInfo.isRunningInXCTest)
    }
}


final class RuntimeEnvironmentXCTests: XCTestCase {
    func testIsRunningInXCTest() {
        XCTAssert(ProcessInfo.isRunningInXCTest)
    }
}
