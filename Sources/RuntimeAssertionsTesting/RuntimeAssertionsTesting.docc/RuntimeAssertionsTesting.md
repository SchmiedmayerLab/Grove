# ``RuntimeAssertionsTesting``

<!--

This source file is part of the Stanford RuntimeAssertions open-source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Test assertions and preconditions using Swift Testing.

## Overview

This package allows developers to test assertions and preconditions in tests using Swift Testing.

> Note: Make sure to use the `RuntimeAssertions` runtime support in your system under test.

### Testing Runtime Assertions

In your unit tests you can use the ``expectRuntimeAssertion(_:expectedCount:sourceLocation:_:assertion:)-25h24`` and
``expectRuntimePrecondition(timeout:_:sourceLocation:_:precondition:)-5w4q1`` functions to test a block of code for which you expect
a runtime assertion to occur.

Below is a short code example demonstrating this for assertions:

```swift
import RuntimeAssertionsTesting
import Testing

@Test
func testAssertion() {
    expectRuntimeAssertion {
        // code containing a call to assert() of the runtime support ...
    }
}
```

Below is a short code example demonstrating this for preconditions:

```swift
import RuntimeAssertionsTesting
import Testing

@Test
func testPrecondition() {
    expectRuntimePrecondition {
        // code containing a call to precondition() of the runtime support ...
    }
}
```

> Tip: Both expectation methods also support the execution of `async` code.


## Topics

### Testing Assertions

- ``expectRuntimeAssertion(_:expectedCount:sourceLocation:_:assertion:)-25h24``
- ``expectRuntimePrecondition(timeout:_:sourceLocation:_:precondition:)-5w4q1``

### Testing Preconditions

- ``expectRuntimePrecondition(timeout:_:sourceLocation:_:precondition:)-5w4q1``
- ``expectNoRuntimePrecondition(timeout:_:sourceLocation:_:precondition:)-kae3``
