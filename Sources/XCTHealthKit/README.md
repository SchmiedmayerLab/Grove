<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# XCTHealthKit



XCTHealthKit is an XCTest-based framework to test the creation of HealthKit samples using the Apple Health App on the iPhone simulator.


## How To Use XCTHealthKit

You can use XCTHealthKit in your UI tests. The [API documentation](XCTHealthKit.docc/XCTHealthKit.md) provides a detailed overview of the public interface of XCTHealthKit.

The framework has the following functionalities:


### Add Mock Data Using the Apple Health App

Use the `XCTestCase.launchAndAddSample(healthApp:_:) throws` function passing in an `NewHealthSampleInput` instance to add mock data using the Apple Health app:
```swift
import XCTest
import XCTHealthKit

class HealthKitUITests: XCTestCase {
    func testAddMockData() throws {
        let healthApp = XCUIApplication.healthApp
        try launchAndAddSample(healthApp: healthApp, .steps(value: 71))
        try launchAndAddSample(healthApp: healthApp, .electrocardiogram())
    }
}
```

Alternatively, the `XCTestCase.launchAndAddSamples(healthApp:_:) throws` function can be used to add multiple samples in a single call:
```swift
import XCTest
import XCTHealthKit

class HealthKitUITests: XCTestCase {
    func testAddMockData() throws {
        let healthApp = XCUIApplication.healthApp
        try launchAndAddSamples(healthApp: healthApp, [
            .activeEnergy(),
            .electrocardiogram(),
            .pushes(value: 117),
            .restingHeartRate(value: 91),
            .steps()
        ])
    }
}
```

### Handle the HealthKit Authorization Sheet

You can use the `XCUIApplication`'s `handleHealthKitAuthorization() throws` function to handle the HealthKit authorization sheet:
```swift
import XCTest
import XCTHealthKit


class HealthKitUITests: XCTestCase {
    func testHandleTheHealthKitAuthorizationSheet() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Request HealthKit Authorization"].tap()
        try app.handleHealthKitAuthorization()
    }
}
```


## Installation

Add the Spezi monorepo package to your app and select the `XCTHealthKit` product.

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
        .product(name: "XCTHealthKit", package: "Spezi")
    ]
)
```

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
