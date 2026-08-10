<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# RuntimeAssertions


Test assertions and preconditions.


## Overview

This library provides the necessary runtime support to support unit testing assertions and preconditions.
The library overloads Swifts runtime assertions:
* `assert(_:_:file:line:)`
* `assertionFailure(_:file:line:)`
* `precondition(_:_:file:line:)`
* `preconditionFailure(_:file:line:)`

Always call this method in your System under Test.
Only if requested within a unit test, their implementations are swapped to assert a runtime assertion.
Release builds will completely optimize out this runtime support library and direct calls to the original Swift implementation.

### Configure your System under Test

To configure your System under Test, you just need to import the `RuntimeAssertion` library and call your runtime assertions functions as usual.

```swift
import RuntimeAssertions

func foo() {
    precondition(someFooCondition, "Foo condition is unmet.")
    // ...
}
```

### Testing Runtime Assertions

With Swift 6.3 or newer, use Swift Testing's native exit-test support on a supported host platform such as macOS:

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

Exit tests run the expression in a child process. Construct non-`Codable` or non-`Sendable` fixtures inside the exit-test closure,
and validate a distinctive stderr message so an unrelated crash cannot satisfy the test.

The `RuntimeAssertionsTesting` product remains available for source compatibility on platforms without native exit tests, but all
of its APIs are deprecated. Don't import it in your application target.

## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing%20Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
