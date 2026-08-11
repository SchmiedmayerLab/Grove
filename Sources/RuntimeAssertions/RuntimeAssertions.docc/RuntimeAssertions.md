# ``RuntimeAssertions``

<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Runtime support to test assertions and preconditions.

## Overview

This library provides the necessary runtime support to support unit testing assertions and preconditions.
The library overloads Swifts runtime assertions:
* ``assert(_:_:file:line:)``
* ``assertionFailure(_:file:line:)``
* ``precondition(_:_:file:line:)``
* ``preconditionFailure(_:file:line:)``

Always call this method in your System under Test.
Only if requested within a unit test, their implementations are swapped to assert a runtime assertion.
Release builds will completely optimize out this runtime support library and direct calls to the original Swift implementation, unless the program is running in an XCTest environment.

### Configure your System under Test

To configure your System under Test, you just need to import the `RuntimeAssertion` library and call your runtime assertions functions as usual.

```swift
import RuntimeAssertions

func foo() {
    precondition(someFooCondition, "Foo condition is unmet.")
    // ...
}
```


## Topics

### Assertions

- ``assert(_:_:file:line:)``
- ``assertionFailure(_:file:line:)``

### Preconditions

- ``precondition(_:_:file:line:)``
- ``preconditionFailure(_:file:line:)``
