# ``RuntimeAssertionsTesting``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Deprecated compatibility helpers for testing runtime assertions and preconditions.

## Overview

The APIs in this module are deprecated. With Swift 6.3 or newer, use Swift Testing's native
`#expect(processExitsWith:)` or `#require(processExitsWith:)` macro on a supported host platform such as macOS.

> Note: Make sure to use the `RuntimeAssertions` runtime support in your system under test.

### Migrating to Native Exit Tests

```swift
import Testing

#if os(macOS)
@Test
func testPrecondition() async throws {
    let result = try await #require(
        processExitsWith: .failure,
        observing: [\.standardErrorContent]
    ) {
        // code containing a call to RuntimeAssertions.precondition(...)
    }

    let standardError = String(decoding: result.standardErrorContent, as: UTF8.self)
    #expect(standardError.contains("Expected failure message"))
}
#endif
```

Native exit tests execute their closure in a child process. Values captured by the closure must be `Codable` and `Sendable`,
and mutations made in the child process are not visible to the parent test. Validate a distinctive stderr message so an unrelated
crash or thrown error cannot satisfy the expected failure.

The compatibility APIs below remain available so existing tests can migrate incrementally, including on platforms where native
exit tests are unavailable. They should not be used in new tests.


## Topics

### Deprecated Assertion Compatibility

- ``expectRuntimeAssertion(_:expectedCount:sourceLocation:_:assertion:)-25h24``

### Deprecated Precondition Compatibility

- ``expectRuntimePrecondition(timeout:_:sourceLocation:_:precondition:)-5w4q1``
- ``expectNoRuntimePrecondition(timeout:_:sourceLocation:_:precondition:)-kae3``
