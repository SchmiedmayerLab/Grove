<!--

This source file is part of the Stanford Spezi open-source project.

SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Spezi FHIR


Build FHIR-based healthcare applications with Spezi.

## Overview

The Spezi FHIR Swift Package provides essential building blocks for developing FHIR-based mobile healthcare applications using the Spezi framework. It includes comprehensive tools for FHIR resource management, HealthKit integration, and mock patient data for testing and development.

## Setup

### Add SpeziFHIR as a Dependency

Add the Spezi monorepo package to your app and select the products you need, such as `SpeziFHIR`, `SpeziHealthKitFHIR`, or `SpeziFHIRMockPatients`.

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
        .product(name: "SpeziFHIR", package: "Spezi"),
        .product(name: "SpeziHealthKitFHIR", package: "Spezi"),
        .product(name: "SpeziFHIRMockPatients", package: "Spezi")
    ]
)
```

> [!IMPORTANT]
> If your application is not yet configured to use Spezi, follow the [Spezi setup article](../Spezi/Spezi.docc/Initial%20Setup.md) to set up the core Spezi infrastructure.

## Targets

Spezi FHIR provides a number of targets to help developers integrate FHIR functionality in their Spezi-based applications:

- `SpeziFHIR`: Core FHIR resource management, storage, and utilities for working with FHIR R4 and DSTU2 resources.
- `SpeziHealthKitFHIR`: Seamless integration between HealthKit data and FHIR resources, enabling conversion of health data to FHIR format.
- `SpeziFHIRMockPatients`: Mock patient data and FHIR bundles for testing and development purposes.

### SpeziFHIR

The core module provides essential FHIR functionality including the `FHIRStore`, an observable store for managing and organizing FHIR resources by category. The `FHIRResource` type serves as a wrapper for FHIR resources with additional metadata and utilities. Combined, they provide tools for searching, copying, and manipulating FHIR resources that are compatible with both FHIR R4 and DSTU2 specifications.

#### FHIRStore

Configure the `FHIRStore` in your `SpeziAppDelegate` to manage FHIR resources in your application:

```swift
import Spezi
import SpeziFHIR


class ExampleAppDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            FHIRStore()
        }
    }
}
```

Use the `FHIRStore` to manage FHIR resources in your application as well as adding and removing `FHIRResource`s in the `FHIRStore`.

```swift
import SpeziFHIR
import SwiftUI


struct ExampleView: View {
    @Environment(FHIRStore.self) private var fhirStore


    var body: some View {
        List {
            Section("Observations") {
                ForEach(fhirStore.observations) { observation in
                    Text(observation.displayName)
                }
            }

            Section("Conditions") {
                ForEach(fhirStore.conditions) { condition in
                    Text(condition.displayName)
                }
            }
        }
    }
}
```

### SpeziHealthKitFHIR

Seamlessly integrate HealthKit data with FHIR resources including easy ways to add `HKSample`s to the `FHIRStore` while loading attachments from the FHIR resources stored in HealthKit or attached information such as voltage information of symptoms for electrocardiograms.
For more information, review the [SpeziHealthKitFHIR sources](../SpeziHealthKitFHIR).

### SpeziFHIRMockPatients

The target offers easily loadable mock patient data for testing and development.
For more information, review the [SpeziFHIRMockPatients sources](../SpeziFHIRMockPatients).

## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing%20Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
