//
// This source file is part of the Stanford RuntimeAssertions open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


// MARK: precondition

/// `XCTRuntimePrecondition` allows you to test assertions of types that use the `precondition` and `preconditionFailure` functions of the `XCTRuntimeAssertions` target.
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
@available(*, deprecated, renamed: "XCTAssertRuntimePrecondition")
public func XCTRuntimePrecondition(
    validateRuntimeAssertion: (@Sendable (String) -> Void)? = nil,
    timeout: TimeInterval = 2,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: @escaping () -> Void
) {
    XCTAssertRuntimePrecondition(
        validateRuntimeAssertion: validateRuntimeAssertion,
        timeout: timeout,
        message(),
        file: file,
        line: line,
        expression
    )
}

/// `XCTRuntimePrecondition` allows you to test async assertions of types that use the `precondition` and `preconditionFailure` functions of the `XCTRuntimeAssertions` target.
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
@available(*, deprecated, renamed: "XCTAssertRuntimePrecondition")
public func XCTRuntimePrecondition(
    validateRuntimeAssertion: (@Sendable (String) -> Void)? = nil,
    timeout: TimeInterval = 2,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: @escaping () async -> Void
) {
    XCTAssertRuntimePrecondition(
        validateRuntimeAssertion: validateRuntimeAssertion,
        timeout: timeout,
        message(),
        file: file,
        line: line,
        expression
    )
}


// MARK: assert

/// `XCTRuntimeAssertion` allows you to test assertions of types that use the `assert` and `assertionFailure` functions of the `XCTRuntimeAssertions` target.
/// - Parameters:
///   - validateRuntimeAssertion: An optional closure that can be used to further validate the messages passed to the
///                               `assert` and `assertionFailure` functions of the `XCTRuntimeAssertions` target.
///   - expectedFulfillmentCount: The expected fulfillment count on how often the `assert` and `assertionFailure` functions of
///                               the `XCTRuntimeAssertions` target are called. The default value is 1. The value must be non-zero.
///   - message: A message that is posted on failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
///   - expression: The expression that is evaluated.
@available(*, deprecated, renamed: "XCTAssertRuntimeAssertion")
public func XCTRuntimeAssertion<T, E: Error>(
    validateRuntimeAssertion: (@Sendable (String) -> Void)? = nil,
    expectedFulfillmentCount: UInt = 1,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: () throws(E) -> T
) throws(E) -> T {
    try XCTAssertRuntimeAssertion(
        validateRuntimeAssertion: validateRuntimeAssertion,
        expectedFulfillmentCount: expectedFulfillmentCount,
        message(),
        file: file,
        line: line,
        expression
    )
}

/// `XCTRuntimeAssertion` allows you to test async assertions of types that use the `assert` and `assertionFailure` functions of the `XCTRuntimeAssertions` target.
/// - Parameters:
///   - validateRuntimeAssertion: An optional closure that can be used to further validate the messages passed to the
///                               `assert` and `assertionFailure` functions of the `XCTRuntimeAssertions` target.
///   - expectedFulfillmentCount: The expected fulfillment count on how often the `assert` and `assertionFailure` functions of
///                               the `XCTRuntimeAssertions` target are called. The default value is 1. The value must be non-zero.
///   - message: A message that is posted on failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
///   - expression: The async expression that is evaluated.
@available(*, deprecated, renamed: "XCTAssertRuntimeAssertion")
public func XCTRuntimeAssertion<T, E: Error>(
    validateRuntimeAssertion: (@Sendable (String) -> Void)? = nil,
    expectedFulfillmentCount: UInt = 1,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: () async throws(E) -> T
) async throws(E) -> T {
    try await XCTAssertRuntimeAssertion(
        validateRuntimeAssertion: validateRuntimeAssertion,
        expectedFulfillmentCount: expectedFulfillmentCount,
        message(),
        file: file,
        line: line,
        expression
    )
}
