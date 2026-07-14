//
// This source file is part of the Stanford RuntimeAssertions open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
import RuntimeAssertions
import XCTest


/// `XCTAssertRuntimePrecondition` allows you to test assertions of types that use the `precondition` and `preconditionFailure` functions of the `XCTRuntimeAssertions` target.
///
/// - Important: The `expression` is executed on a background thread, even though it is not annotated as `@Sendable`. This is by design. Preconditions return `Never` and, therefore,
/// need to be run on a separate thread that can block forever. Without this workaround, testing preconditions that are isolated to `@MainActor` would be impossible.
/// Make sure to only run isolated parts of your code that don't suffer from concurrency issues in such a scenario.
///
/// - Parameters:
///   - validateRuntimeAssertion: An optional closure that can be used to further validate the messages passed to the
///                               `precondition` and `preconditionFailure` functions of the `XCTRuntimeAssertions` target.
///   - timeout: A timeout defining how long to wait for the precondition to be triggered.
///   - message: A message that is posted on failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
///   - expression: The expression that is evaluated.
public func XCTAssertRuntimePrecondition(
    validateRuntimeAssertion: (@Sendable (String) -> Void)? = nil,
    timeout: TimeInterval = 2,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: @escaping () -> Void
) {
    withRuntimePrecondition(timeout: timeout, validatePrecondition: validateRuntimeAssertion, expression) { count in
        assertFulfillmentCount(count, expected: 1, message, file: file, line: line)
    }
}

/// `XCTAssertNoRuntimePrecondition` allows you to test the absence of assertions of types that use the `precondition` and `preconditionFailure` functions of the `XCTRuntimeAssertions` target.
///
/// - Important: The `expression` is executed on a background thread, even though it is not annotated as `@Sendable`. This is by design. Preconditions return `Never` and, therefore,
/// need to be run on a separate thread that can block forever. Without this workaround, testing preconditions that are isolated to `@MainActor` would be impossible.
/// Make sure to only run isolated parts of your code that don't suffer from concurrency issues in such a scenario.
///
/// - Parameters:
///   - timeout: A timeout defining how long to wait for the precondition to not be triggered.
///   - message: A message that is posted on failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
///   - expression: The expression that is evaluated.
public func XCTAssertNoRuntimePrecondition(
    timeout: TimeInterval = 2,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: @escaping () -> Void
) {
    withRuntimePrecondition(timeout: timeout, validatePrecondition: nil, expression) { count in
        assertFulfillmentCount(count, expected: 0, message, file: file, line: line)
    }
}

/// `XCTAssertRuntimePrecondition` allows you to test async assertions of types that use the `precondition` and `preconditionFailure` functions of the `XCTRuntimeAssertions` target.
///
/// - Important: The `expression` is executed on a background thread, even though it is not annotated as `@Sendable`. This is by design. Preconditions return `Never` and, therefore,
/// need to be run on a separate thread that can block forever. Without this workaround, testing preconditions that are isolated to `@MainActor` would be impossible.
/// Make sure to only run isolated parts of your code that don't suffer from concurrency issues in such a scenario.
///
/// - Parameters:
///   - validateRuntimeAssertion: An optional closure that can be used to further validate the messages passed to the
///                               `precondition` and `preconditionFailure` functions of the `XCTRuntimeAssertions` target.
///   - timeout: A timeout defining how long to wait for the precondition to be triggered.
///   - message: A message that is posted on failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
///   - expression: The async expression that is evaluated.
public func XCTAssertRuntimePrecondition(
    validateRuntimeAssertion: (@Sendable (String) -> Void)? = nil,
    timeout: TimeInterval = 2,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: @escaping () async -> Void
) {
    withRuntimePrecondition(timeout: timeout, validatePrecondition: validateRuntimeAssertion, expression) { count in
        assertFulfillmentCount(count, expected: 1, message, file: file, line: line)
    }
}

/// `XCTAssertNoRuntimePrecondition` allows you to test the absence of async assertions of types that use the `precondition` and `preconditionFailure` functions of the `XCTRuntimeAssertions` target.
///
/// - Important: The `expression` is executed on a background thread, even though it is not annotated as `@Sendable`. This is by design. Preconditions return `Never` and, therefore,
/// need to be run on a separate thread that can block forever. Without this workaround, testing preconditions that are isolated to `@MainActor` would be impossible.
/// Make sure to only run isolated parts of your code that don't suffer from concurrency issues in such a scenario.
///
/// - Parameters:
///   - timeout: A timeout defining how long to wait for the precondition to not be triggered.
///   - message: A message that is posted on failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
///   - expression: The async expression that is evaluated.
public func XCTAssertNoRuntimePrecondition(
    timeout: TimeInterval = 2,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: @escaping () async -> Void
) {
    withRuntimePrecondition(timeout: timeout, validatePrecondition: nil, expression) { count in
        assertFulfillmentCount(count, expected: 0, message, file: file, line: line)
    }
}


/// - parameter expected: the expected number of `precondition` or `preconditionFailure` calls.
private func assertFulfillmentCount(
    _ fulfillmentCount: Int,
    expected: UInt,
    _ message: () -> String,
    file: StaticString,
    line: UInt
) {
    guard fulfillmentCount != expected else {
        // everything is fine
        return
    }
    if expected > fulfillmentCount {
        XCTFail(
            """
            The precondition was called too many times (expected \(expected); got \(fulfillmentCount)).
            \(message()) at \(file):\(line)
            """
        )
    } else {
        XCTFail(
            """
            The precondition was called too few times (expected \(expected); got \(fulfillmentCount)).
            \(message()) at \(file):\(line)
            """
        )
    }
}
