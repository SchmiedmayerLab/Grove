<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# XCTestExtensions


This Swift Package provides convenient extension points to write tests using XCTest.

`XCTestExtensions` is a collection of extensions for commonly used functionality in UI tests using XCTest. You can learn more about `XCTestExtensions` in the [XCTestExtensions API documentation](XCTestExtensions.docc/XCTestExtensions.md).
It includes the functionality to
- delete & launch an application to reset the application
- disable password autofill on an iOS simulator to avoid challenges with the text entry in secure text fields
- enable a simple text entry in plain and secure text fields

The `XCTestApp` target enables writing test-based apps that can be verified in a UI test. You can learn more about `XCTestApp` in the [XCTestApp API documentation](../XCTestApp/XCTestApp.docc/XCTestApp.md).

## Installation

Add the Spezi monorepo package to your app and select the `XCTestExtensions` and `XCTestApp` products.

In Xcode, select **File > Add Package Dependencies...**, enter:

```text
https://github.com/SchmiedmayerLab/Spezi.git
```

Choose **Up to Next Minor Version** and enter the latest tagged `0.x` release, for example `0.1.0`.

If you manage dependencies in a `Package.swift`, add the package dependency:

```swift
.package(url: "https://github.com/SchmiedmayerLab/Spezi.git", .upToNextMinor(from: "0.1.0"))
```

Then add the product dependency to the target that needs it:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "XCTestExtensions", package: "Spezi"),
        .product(name: "XCTestApp", package: "Spezi")
    ]
)
```

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
