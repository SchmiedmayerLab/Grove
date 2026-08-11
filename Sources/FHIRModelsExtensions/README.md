<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# FHIRModelsExtensions


Reusable utilies when working with the [apple/FHIRModels](https://github.com/apple/FHIRModels) package.

> [!NOTE]
> The name here might be a bit misleading; this package both extends the FHIR types, and also provides facilitis for working with [FHIR Extensions](https://build.fhir.org/extensibility.html).


## Components

Package targets:
- FHIRModelsExtensions:
    - Utility functions on R4 types
    - [FHIR Extension](https://build.fhir.org/extensibility.html) facilities
- FHIRPathParser
    - [FHIRPath](https://hl7.org/fhirpath/) utilities



## Installation

Add the Spezi monorepo package to your app and select the products you need, such as `FHIRModelsExtensions`, `FHIRPathParser`, or `FHIRQuestionnaires`.

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
        .product(name: "FHIRModelsExtensions", package: "Spezi"),
        .product(name: "FHIRPathParser", package: "Spezi"),
        .product(name: "FHIRQuestionnaires", package: "Spezi")
    ]
)
```

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
