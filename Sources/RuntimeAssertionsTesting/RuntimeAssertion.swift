//
// This source file is part of the Stanford RuntimeAssertions open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import RuntimeAssertions
public import Testing


/// Test assertions that use `assert` or `assertionFailure` of the `RuntimeAssertions` library.
/// - Parameters:
///   - expectedCount: The number of time the expected assertion should occur when the `expression` is invoked. Must be equal to or greater than 0.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and issues should be attributed.
///   - expression: The expression to be evaluated.
///   - assertion: Validate and handle the contents of the assertion.
@available(*, deprecated, message: "Use Swift 6.3's #expect(processExitsWith:) on a supported host platform such as macOS.")
public func expectRuntimeAssertion<T, E: Error>(
    _ comment: Comment? = nil,
    expectedCount: UInt = 1,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ expression: () throws(E) -> T,
    assertion: (@Sendable (String) -> Void)? = nil
) throws(E) -> T {
    try withRuntimeAssertion(validateAssertion: assertion, expression) { count in
        assertFulfillmentCount(count, expectedFulfillmentCount: expectedCount, comment, sourceLocation: sourceLocation)
    }
}


/// Test assertions that use `assert` or `assertionFailure` of the `RuntimeAssertions` library.
/// - Parameters:
///   - expectedCount: The number of time the expected assertion should occur when the `expression` is invoked. Must be equal to or greater than 0.
///   - comment: A comment describing the expectation.
///   - sourceLocation: The source location to which recorded expectations and issues should be attributed.
///   - expression: The expression to be evaluated.
///   - assertion: Validate and handle the contents of the assertion.
@available(*, deprecated, message: "Use Swift 6.3's #expect(processExitsWith:) on a supported host platform such as macOS.")
public func expectRuntimeAssertion<T, E: Error>(
    _ comment: Comment? = nil,
    expectedCount: UInt = 1,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ expression: () async throws(E) -> T,
    assertion: (@Sendable (String) -> Void)? = nil
) async throws(E) -> T {
    try await withRuntimeAssertion(validateAssertion: assertion, expression) { count in
        assertFulfillmentCount(count, expectedFulfillmentCount: expectedCount, comment, sourceLocation: sourceLocation)
    }
}


private func assertFulfillmentCount(
    _ fulfillmentCount: Int,
    expectedFulfillmentCount: UInt,
    _ comment: Comment?,
    sourceLocation: SourceLocation
) {
    Swift.precondition(expectedFulfillmentCount >= 0, "expectedFulfillmentCount has to be non-zero!")

    if fulfillmentCount != expectedFulfillmentCount {
        Issue.record(
             """
             Measured an fulfillment count of \(fulfillmentCount), expected \(expectedFulfillmentCount).
             \(comment?.description ?? "") at \(sourceLocation)
             """,
             sourceLocation: sourceLocation
        )
    }
}
