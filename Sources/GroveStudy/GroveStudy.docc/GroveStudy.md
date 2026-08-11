# ``GroveStudy``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Define and conduct scientific/clinical studies using the Grove ecosystem.

## Overview

The GroveStudy module enables apps to integrate with Apple's HealthKit system, fetch data, set up long-lived background data collection, and visualize Health-related data.

### Setup

You need to add the GroveStudy Swift package to
 [your app in Xcode](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) or
 [your SPM package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package).

> Important: If your application is not yet configured to use Grove, follow the
 [Grove setup article](../../Grove/Grove.docc/Initial%20Setup.md) and set up the core Grove infrastructure.

### Architecture

The GroveStudy package consists of two targets:
- [GroveStudyDefinition](../../GroveStudyDefinition/GroveStudyDefinition.docc/GroveStudyDefinition.md), which defines the [`StudyDefinition`](../../GroveStudyDefinition/GroveStudyDefinition.docc/GroveStudyDefinition.md) type;
- ``GroveStudy``, which implements the ``StudyManager`` providing study-related logic and infrastructure, such as on-device persistence of study enrollments, scheduling of study-related tasks, automatic configuration of background Health data collection, etc.

> Tip: If your app is only interested in the [`StudyDefinition`](../../GroveStudyDefinition/GroveStudyDefinition.docc/GroveStudyDefinition.md), you don't need to import the ``GroveStudy`` target at all.

### Example

You enable and configure the ``StudyManager`` by including it in your app's `GroveAppDelegate`:
```swift
class ExampleAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration(standard: ExampleStandard()) {
            StudyManager()
        }
    }
}
```

> Note: Make sure your `Standard` conforms to GroveHealthKit's `HealthKitConstraint`; this is required for the ``StudyManager`` to work, even if your studies don't perform any Health data collection.

See the ``StudyManager`` documentation for more information and examples.

## Topics

### The Study Manager
- ``StudyManager``
