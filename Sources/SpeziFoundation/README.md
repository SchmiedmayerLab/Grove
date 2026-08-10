<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# SpeziFoundation


Spezi Foundation provides a base layer of functionality useful in many applications, including fundamental types, algorithms, extensions, and data structures.


## Components

The SpeziFoundation package consists of 2 targets:
- SpeziFoundation:
    - Extensions related to concurrency, collection, etc;
    - Data structures;
    - Markdown processing
    - See the docs for an exhaustive list.
- SpeziLocalization:
    - Localization-related utilities, for working with both string and file-level localization


## Installation

Add the Spezi monorepo package to your app and select the `SpeziFoundation` and `SpeziLocalization` products.

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
        .product(name: "SpeziFoundation", package: "Spezi"),
        .product(name: "SpeziLocalization", package: "Spezi")
    ]
)
```

## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing-Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## Testing on Linux

You can test SpeziFoundation on Linux using Docker. To do this, run the following command:

```bash
docker build -t spezi-foundation .
```

This will build the container and run the tests.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
