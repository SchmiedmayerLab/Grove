<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Spezi HealthKit


Access Health data in your Spezi app.

## Overview

The Spezi HealthKit module enables apps to integrate with Apple's HealthKit system, fetch data, set up long-lived background data collection, and visualize Health-related data.

### Setup

Add the Spezi monorepo package to your app and select the products you need, such as `SpeziHealthKit`, `SpeziHealthKitBulkExport`, or `SpeziHealthKitUI`.

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
        .product(name: "SpeziHealthKit", package: "Spezi"),
        .product(name: "SpeziHealthKitBulkExport", package: "Spezi"),
        .product(name: "SpeziHealthKitUI", package: "Spezi")
    ]
)
```

> [!IMPORTANT]
> If your application is not yet configured to use Spezi, follow the [Spezi setup article](../Spezi/Spezi.docc/Initial%20Setup.md) to set up the core Spezi infrastructure.


### Health Data Collection

Before you configure the `HealthKit`  module, make sure your `Standard` in your Spezi Application conforms to the `HealthKitConstraint` protocol to receive HealthKit data.
The `HealthKitConstraint/handleNewSamples(_:ofType:)` function is called once for every batch of newly collected HealthKit samples, and the `HealthKitConstraint/handleDeletedObjects(_:ofType:)` function is called once for every batch of deleted HealthKit objects.
```swift
actor ExampleStandard: Standard, HealthKitConstraint {
    // Add the newly collected HealthKit samples to your application.
    func handleNewSamples<Sample>(
        _ addedSamples: some Collection<Sample> & Sendable,
        ofType sampleType: SampleType<Sample>
    ) async {
        // ...
    }

    // Remove the deleted HealthKit objects from your application.
    func handleDeletedObjects<Sample>(
        _ deletedObjects: some Collection<HKDeletedObject> & Sendable,
        ofType sampleType: SampleType<Sample>
    ) async {
        // ...
    }
}
```


Then, you can configure the `HealthKit` module in the configuration section of your `SpeziAppDelegate`.
You can, e.g., use `CollectSamples` to collect a wide variety of HealthKit data types:
```swift
class ExampleAppDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration(standard: ExampleStandard()) {
            HealthKit {
                CollectSamples(.activeEnergyBurned)
                CollectSamples(.stepCount, start: .manual)
                CollectSamples(.pushCount, start: .manual)
                CollectSamples(.heartRate, continueInBackground: true)
                CollectSamples(.electrocardiogram, start: .manual)
                RequestReadAccess(quantity: [.bloodOxygen])
            }
        }
    }
}
```

> [!TIP]
> See `SampleType` for a complete list of supported sample types.


### Querying Health Data in SwiftUI

You can use `SpeziHealthKitUI`'s `HealthKitQuery` and `HealthKitStatisticsQuery` property wrappers to access the Health database in a View:
```swift
struct ExampleView: View {
    @HealthKitQuery(.heartRate, timeRange: .today)
    private var heartRateSamples

    var body: some View {
        ForEach(heartRateSamples) { sample in
            // ...
        }
    }
}
```

Additionally, you can use `SpeziHealthKitUI`'s `HealthChart` to visualise query results:
```swift
struct ExampleView: View {
    @HealthKitQuery(.heartRate, timeRange: .today)
    private var heartRateSamples

    var body: some View {
        HealthChart {
            HealthChartEntry($heartRateSamples, drawingConfig: .init(mode: .line, color: .red))
        }
    }
}
```


For more information, please refer to the [SpeziHealthKit](SpeziHealthKit.docc/SpeziHealthKit.md), [SpeziHealthKitUI](../SpeziHealthKitUI/SpeziHealthKitUI.docc/SpeziHealthKitUI.md), and [SpeziHealthKitBulkExport](../SpeziHealthKitBulkExport/SpeziHealthKitBulkExport.docc/BulkHealthExporter.md) documentation.

## The Spezi Template Application

The Spezi Template Application provides a great starting point and example using the `SpeziHealthKit` module.


## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing%20Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
