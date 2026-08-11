<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Spezi Firebase


Integrate Google Firebase services into your Spezi application.

## Overview

This Module allows you to use the [Google Firebase](https://firebase.google.com/) platform as a managed backend for
authentication and data storage in your apps built with the [Spezi framework](../Spezi/README.md).

We currently implement support for Authentication, Storage, and Firestore services.

## Setup

Add the Spezi monorepo package to your app and select the products you need, such as `SpeziFirebaseAccount`, `SpeziFirebaseConfiguration`, `SpeziFirestore`, `SpeziFirebaseStorage`, or `SpeziFirebaseAccountStorage`.

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
        .product(name: "SpeziFirebaseAccount", package: "Spezi"),
        .product(name: "SpeziFirebaseConfiguration", package: "Spezi"),
        .product(name: "SpeziFirestore", package: "Spezi"),
        .product(name: "SpeziFirebaseStorage", package: "Spezi"),
        .product(name: "SpeziFirebaseAccountStorage", package: "Spezi")
    ]
)
```

> [!IMPORTANT]
> If your application is not yet configured to use Spezi, follow the [Spezi setup article](../Spezi/Spezi.docc/Initial-Setup.md) to set up the core Spezi infrastructure.


## Examples

The below section walks you through the necessary steps to set up the Spezi Firebase Module for your application.

### 1. Set up your Firebase Account

To connect your app to the Firebase cloud platform, you will need to first create an account at
[firebase.google.com](https://firebase.google.com) then start the process to
[register a new iOS app](https://firebase.google.com/docs/ios/setup).

Once your Spezi app is registered with Firebase, place the generated `GoogleService-Info.plist` configuration file
into the root of your Xcode project.
You do not need to add the Firebase SDKs to your app or initialize Firebase in your app,
since the Spezi Firebase Module will handle these tasks for you.

You can also install and run the Firebase Local Emulator Suite for local development.
To do this, please follow the [installation instructions](https://firebase.google.com/docs/emulator-suite/install_and_configure).

### 2. Add Spezi Firebase as a Dependency

If you have not already done so, add the Spezi monorepo package and select the Firebase products listed in [Setup](#setup).

### 3. Register the Spezi Firebase Modules

In the example below, we configure our Spezi application to use Firebase Authentication with both email & password login
and Sign in With Apple, and Cloud Firestore for data storage.

```swift
import Spezi
import SpeziAccount
import SpeziFirebaseAccount
import SpeziFirebaseStorage
import SpeziFirestore
import SwiftUI


class ExampleDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            AccountConfiguration(configuration: [
                .requires(\.userId),
                .collects(\.name)
            ])
            Firestore()
            FirebaseAccountConfiguration[
                authenticationMethods: [.emailAndPassword, .signInWithApple]
            ]
        }
    }
}
```

For more information, please refer to the [SpeziFirebaseAccount](../SpeziFirebaseAccount/SpeziFirebaseAccount.docc/SpeziFirebaseAccount.md), [SpeziFirebaseConfiguration](../SpeziFirebaseConfiguration/FirebaseConfiguration.docc/FirebaseConfiguration.md), [SpeziFirestore](../SpeziFirestore/SpeziFirestore.docc/SpeziFirestore.md), [SpeziFirebaseStorage](../SpeziFirebaseStorage/SpeziFirebaseStorage.docc/SpeziFirebaseStorage.md), and [SpeziFirebaseAccountStorage](../SpeziFirebaseAccountStorage/SpeziFirebaseAccountStorage.docc/SpeziFirebaseAccountStorage.md) documentation.


## The Spezi Template Application

The Spezi Firebase Module comes pre-configured in the Spezi Template Application,
which is a great way to get started on your Spezi Application.


## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing-Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
