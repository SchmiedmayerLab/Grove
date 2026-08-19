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

An overview of System Programming Interfaces (SPIs) provided by GroveViews.

## Overview

A [System Programming Interface](https://blog.eidinger.info/system-programming-interfaces-spi-in-swift-explained) is a subset of API
that is targeted only for certain users (e.g., framework developers) and might not be necessary or useful for app development.
Therefore, these interfaces are not visible by default and need to be explicitly imported.
This article provides an overview of supported SPI provided by GroveFoundation

### TestingSupport

The `TestingSupport` SPI provides additional interfaces that are useful for unit and UI testing.
Annotate your import statement as follows.

```swift
@_spi(TestingSupport) import GroveViews
```

#### RuntimeConfig

[`RuntimeConfig`](../../GroveFoundation/GroveFoundation.docc/SPI.md#RuntimeConfig) is provided by
[GroveFoundation](../../GroveFoundation/GroveFoundation.docc/GroveFoundation.md) for a central place to
provide runtime configurations.

GroveViews adds the following extensions:

- `RuntimeConfig/testingTips`: Holds `true` if the `--testTips` command line flag was supplied to indicate to always show Tips when using
    ``ConfigureTipKit``.
