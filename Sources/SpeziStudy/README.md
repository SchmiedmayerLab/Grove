<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# SpeziStudy

Reusable study definitions and infrastructure for the Spezi ecosystem



## Overview

The SpeziStudy package consists of the following modules:
- [`SpeziStudyDefinition`](../SpeziStudyDefinition/SpeziStudyDefinition.docc/SpeziStudyDefinition.md): implements the `StudyDefinition` type, used for defining reusable studies that can be used with the Spezi ecosystem.
- [`SpeziStudy`](SpeziStudy.docc/SpeziStudy.md): implements study-enrollment and participation infrastructure, such as e.g. the `StudyManager`.

You enable and configure the ``StudyManager`` by including it in your app's `SpeziAppDelegate`:
```swift
class ExampleAppDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration(standard: ExampleStandard()) {
            StudyManager()
        }
    }
}
```

For more information, please refer to the [SpeziStudy](SpeziStudy.docc/SpeziStudy.md) and [SpeziStudyDefinition](../SpeziStudyDefinition/SpeziStudyDefinition.docc/SpeziStudyDefinition.md) documentation.


## The Spezi Template Application

The Spezi Template Application provides a great starting point and example using the `SpeziStudy` module.


## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing-Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
