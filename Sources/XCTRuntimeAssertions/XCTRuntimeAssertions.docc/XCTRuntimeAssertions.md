# ``XCTRuntimeAssertions``

<!--

This source file is part of the Stanford RuntimeAssertions open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Test assertions and preconditions using XCTest.

## Overview

This package allows developers to test assertions and preconditions in tests using XCTest.

> Note: Make sure to use the `RuntimeAssertions` runtime support in your system under test.

### Testing Runtime Assertions

In your unit tests you can use the ``XCTRuntimeAssertion(validateRuntimeAssertion:expectedFulfillmentCount:_:file:line:_:)-60zkv`` and
``XCTRuntimePrecondition(validateRuntimeAssertion:timeout:_:file:line:_:)-2c7hq`` functions to test a block of code for which you expect
a runtime assertion to occur.

Below is a short code example demonstrating this for assertions:

```swift
import XCTRuntimeAssertions

XCTRuntimeAssertion {
    // code containing a call to assert() of the runtime support ...
}
```

Below is a short code example demonstrating this for preconditions:

```swift
import XCTRuntimeAssertions

XCTRuntimePrecondition {
    // code containing a call to precondition() of the runtime support ...
}
```

> Tip: Both methods also support the execution of `async` code.


## Topics

### Testing Assertions

- ``XCTRuntimeAssertion(validateRuntimeAssertion:expectedFulfillmentCount:_:file:line:_:)-60zkv``
- ``XCTRuntimeAssertion(validateRuntimeAssertion:expectedFulfillmentCount:_:file:line:_:)-1mx3a``

### Testing Preconditions

- ``XCTRuntimePrecondition(validateRuntimeAssertion:timeout:_:file:line:_:)-2c7hq``
- ``XCTRuntimePrecondition(validateRuntimeAssertion:timeout:_:file:line:_:)-8m9qt``
