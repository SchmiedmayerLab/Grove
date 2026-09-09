# ``GroveLicense``

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#       
-->

Provides a view that renders a list of all package dependencies used in the project.


## Overview

The Grove License module provides a quick way to inform users about the tools and packages you have leveraged in your project including their license information.
You use the ``ContributionsList`` within your views to visualize a list of all Swift package dependencies used in your Xcode project.

@Row {
    @Column {
        @Image(source: "ContributionsList", alt: "A list headed by the app's own license, followed by every Swift package the app depends on with its license and version.") {
            The ``ContributionsList`` opens with the project's own license and lists every package dependency with its license and version.
        }
    }
    @Column {
        @Image(source: "PackageLicense", alt: "The full license text of a single package, with the package name in the navigation bar and a button to open its repository.") {
            Tapping a package shows its full license text and offers to open the repository in the browser.
        }
    }
}

This package builds on Felix Herrmann's [SwiftPackageList](https://github.com/FelixHerrmann/swift-package-list) library under the hood.


## Setup

### 1. Add Grove License and Swift Package List as a Dependency.

You need to add the GroveLicense and [SwiftPackageList](https://github.com/FelixHerrmann/swift-package-list) Swift package to
[your app in Xcode](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app#) or
[Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package).

### 2. Add the SwiftPackageListPlugin to your Xcode Project

Add the SwiftPackageListPlugin to the "Run Build Tool Plug-ins" in your Build Phases settings of your Xcode project as described in the [SwiftPackageList](https://github.com/FelixHerrmann/swift-package-list?tab=readme-ov-file#build-tool-plugin) documentation.


## Example

### Contributions List

The ``ContributionsList`` renders a list of all Swift packages used in your Xcode project including their license information.
The code example below showcases how to render a simple list view with all used package dependencies.


```swift
import GroveLicense
import SwiftUI

struct ExamplePackageDependenciesView: View {

    var body: some View {
        ContributionsList(projectLicense: .mit)
    }
}
```
