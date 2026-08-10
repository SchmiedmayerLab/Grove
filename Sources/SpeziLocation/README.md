<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Spezi Location

## Overview

The Spezi Location Module allows you to access location data from within your [Stanford Spezi](../Spezi/README.md) app via Apple's [CoreLocation](https://developer.apple.com/documentation/corelocation) service using a simple asynchronous API.

## Setup

### 1. Add Spezi Location as a Dependency

Add the Spezi monorepo package to your app and select the `SpeziLocation` product.

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
        .product(name: "SpeziLocation", package: "Spezi")
    ]
)
```

> [!IMPORTANT]
> If your application is not yet configured to use Spezi, follow the [Spezi setup article](../Spezi/Spezi.docc/Initial-Setup.md) to set up the core Spezi infrastructure.

### 2. Configure the SpeziLocation module in the `SpeziAppDelegate`.

```swift
import Spezi
import SpeziLocation

class ExampleDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            SpeziLocation()
        }
    }
}
```

### 3. Configure your Xcode project for Location Access

Before requesting permissions for location access from your user, you will need to provide descriptions of how your app uses location services in your `Info.plist` file:

- Open your project settings in Xcode by selecting *PROJECT_NAME > TARGET_NAME > Info* tab.
- Under `Custom iOS Target Properties` (the `Info.plist` file), add one or more of the following keys depending on the level of location access you are requesting and add a description for your usage in the `Value` column which will be shown to the user when you request access:

| Property | Description |
|----------|-------------|
| `Privacy - Location When In Use Usage Description` | Access to location while the app is in use (in the foreground). |
| `Privacy - Location Always and When In Use Usage Description` | Access to location both when the app is in use and in the background. |


## Usage

### Request the User's Current Location

The following example demonstrates how you can use SpeziLocation in a SwiftUI view to request access to the user's current location.

```swift
import CoreLocation
import SpeziLocation
import SwiftUI


struct LocationPermissionsView: View {
    @Environment(SpeziLocation.self) private var speziLocation

    var body: some View {
        Button("Request Location Access") {
            Task {
                do {
                    // Request permission to access location while the app is in use
                    let result = await speziLocation.requestWhenInUseAuthorization()

                    // Check if permission was granted
                    if (result == .authorizedWhenInUse) {

                        // Get the user's latest location
                        let location = try await speziLocation.getLatestLocation()

                        // Extract the latitude and longitude
                        let latitude = location.coordinate.latitude
                        let longitude = location.coordinate.longitude
                    }
                } catch {
                    // Handle error...
                }
            }
        }
    }
}
```

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
