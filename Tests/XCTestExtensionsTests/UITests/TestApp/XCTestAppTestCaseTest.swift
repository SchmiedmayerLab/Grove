//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI
import XCTestApp


struct XCTestAppTestCaseTest: TestAppTestCase {
    func runTests() async throws {
        try testAssert()
        try await testAssertEqual()
        try await testAssertNotEqual()
        try await testAssertNil()
        try await testAssertNotNil()
        try testAssertUnwrap()
        try testNoThrow()
    }
    
    
    private func assertThrows(_ block: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) throws {
        do {
            try block()
            throw XCTestFailure(message: "Did not trigger the expected assertion.", file: file, line: line)
        } catch { }
    }
    
    
    func testAssert() throws {
        try XCTAssert(true)
        try XCTAssertTrue(true)
        try XCTAssertFalse(false)
        try assertThrows {
            try XCTAssert(false)
        }
        try assertThrows {
            try XCTAssertTrue(false)
        }
        try assertThrows {
            try XCTAssertFalse(true)
        }
    }
    
    
    func testAssertEqual() async throws {
        try await Task.sleep(for: .seconds(0.1))
        try XCTAssertEqual(42, 42)
        try assertThrows {
            try XCTAssertEqual(42, 43)
        }
    }
    
    
    func testAssertNotEqual() async throws {
        try await Task.sleep(for: .seconds(0.1))
        try XCTAssertNotEqual(42, 43)
        try assertThrows {
            try XCTAssertNotEqual(42, 42)
        }
    }
    
    
    func testAssertNil() async throws {
        try XCTAssertNil(Optional<Int>.none)
        try assertThrows {
            try XCTAssertNil(42)
        }
        try await Task.sleep(for: .seconds(0.1))
    }
    
    
    func testAssertNotNil() async throws {
        try XCTAssertNotNil(52)
        try assertThrows {
            try XCTAssertNotNil(Optional<Void>.none)
        }
        try await Task.sleep(for: .seconds(0.1))
    }
    
    
    func testAssertUnwrap() throws {
        print(try XCTUnwrap(42))
        try assertThrows {
            _ = try XCTUnwrap(Optional<Int>.none)
        }
    }
    
    
    func testNoThrow() throws {
        struct FakeError: Error {}
        try XCTAssertNoThrow({ () throws in }())
        try assertThrows {
            try XCTAssertNoThrow({ () throws in
                throw FakeError()
            }())
        }
    }
}
