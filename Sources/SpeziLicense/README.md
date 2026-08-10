<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# SpeziLicense



Provides a view that renders a list of third-party libraries used in an iOS app.

<table style="width: 80%">
  <tr>
    <td align="center" width="50%">
      <img src="SpeziLicense.docc/Resources/Overview.png#gh-light-mode-only" width="80%"/>
      <img src="SpeziLicense.docc/Resources/Overview~dark.png#gh-dark-mode-only" width="80%"/>
    </td>
    <td align="center" width="50%">
      <img src="SpeziLicense.docc/Resources/License.png#gh-light-mode-only" width="80%"/>
      <img src="SpeziLicense.docc/Resources/License~dark.png#gh-dark-mode-only" width="80%"/>
    </td>
  </tr>
  <tr>
    <td align="center">Acknowledgements List</td>
    <td align="center">Dependency License Text</td>
  </tr>
</table>

## Overview

The Spezi License module provides a quick way to inform users about the tools and packages you have leveraged in your project including their license information.
You use the ``ContributionsList`` abstraction within your views to visualize a list of all Swift package dependecies used in your Xcode project.

This package builds on Felix Hermann's' [SwiftPackageList](https://github.com/FelixHerrmann/swift-package-list) library under the hood.


## Setup

### 1. Add Spezi License as a Dependency

Add the Spezi monorepo package to your app and select the `SpeziLicense` product.

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
        .product(name: "SpeziLicense", package: "Spezi")
    ]
)
```

### 2. Add the SwiftPackageListPlugin to your Xcode Project

Add the SwiftPackageListPlugin to the "Run Build Tool Plug-ins" in your Build Phases settings of your Xcode project as described in the [SwiftPackageList](https://github.com/FelixHerrmann/swift-package-list?tab=readme-ov-file#build-tool-plugin) documentation.


## Example

### Contributions List

The ContributionsList allows you to render a list containing all used Swift packages in your Xcode project including license infromation.
The code example below showcases how to render a simple list view with all used package dependencies.


```swift
import SpeziLicense
import SwiftUI

struct ExamplePackageDependenciesView: View {

    var body: some View {
        ContributionsList(projectLicense: .mit)
    }
}
```


## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing-Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
