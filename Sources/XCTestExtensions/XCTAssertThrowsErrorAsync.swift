//
// This source file is part of the Stanford XCTestExtensions open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest


/// Asserts that an async expression throws an error.
///
/// - Note: This is an async version of [`XCTAssertThrowsError(_:_:file:line:_:)`](https://developer.apple.com/documentation/xctest/1500795-xctassertthrowserror).
///
/// - Parameters:
///   - expression: An async expression that can throw an error.
///   - message: An optional description of a failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
///   - errorHandler: An optional handler for errors that expression throws.
public func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure @Sendable  () async throws -> T,
    _ message: @autoclosure @Sendable () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: @Sendable (any Error) throws -> Void = { _ in }
) async rethrows {
    do {
        _ = try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        try errorHandler(error)
    }
}
