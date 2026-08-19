# System Programming Interfaces

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#       
-->

An overview of System Programming Interfaces (SPIs) provided by Grove Foundation.

## Overview

A [System Programming Interface](https://blog.eidinger.info/system-programming-interfaces-spi-in-swift-explained) is a subset of API
that is targeted only for certain users (e.g., framework developers) and might not be necessary or useful for app development.
Therefore, these interfaces are not visible by default and need to be explicitly imported.
This article provides an overview of supported SPI provided by GroveFoundation

### TestingSupport

The `TestingSupport` SPI provides additional interfaces that are useful for unit and UI testing.
Annotate your import statement as follows.

```swift
@_spi(TestingSupport) import GroveFoundation
```

- Note: As of Swift 5.8, you can solely import the SPI target without any other interfaces of the SPM target
by setting the `-experimental-spi-only-imports` Swift compiler flag and using `@_spiOnly`.

```swift
@_spiOnly import GroveFoundation
```

#### RuntimeConfig

The `RuntimeConfig` stores configurations of the current runtime environment for testing support.

- `RuntimeConfig/testMode`: Holds `true` if the `--testMode` command line flag was supplied to indicate to enable additional testing functionalities. 
