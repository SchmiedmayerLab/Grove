# Logger

<!--
                  
This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
             
-->

A unified logging API that works consistently across both Apple platforms and non-Apple platforms.

GroveFoundation exposes a single `Logger` API that mirrors the behavior of the system-provided `os.Logger` on Apple platforms, while providing an equivalent implementation powered by [`swift-log`](https://github.com/apple/swift-log) on platforms where the `os` module is unavailable.

---

## Platform Behavior

### Apple Platforms

On Apple platforms (`macOS`, `iOS`, `tvOS`, `watchOS`, `visionOS`):

- `Logger` refers to the system type `os.Logger`.
- The initializer  `Logger(subsystem:category:)` is provided natively by the `OSLog` framework.


### Non-Apple Platforms

On platforms where the `os` module is unavailable (such as Linux or Windows):

* `Logger` refers to `Logging.Logger` from `swift-log`.

* GroveFoundation adds a compatibility initializer on non-Apple platforms, so the same source code works everywhere.

* Internally:

    * `subsystem` is mapped to the logger's `label`.

    * `category` is stored as metadata under the `"category"` key.

This enables the same source code to compile and run on all supported platforms without conditional compilation.

---

## Usage

The following example works the same way on Apple platforms and on Linux:

```swift
import GroveFoundation

let logger = Logger(
    subsystem: "edu.stanford.spezi",
    category: "GroveFoundation"
)

logger.info("Logger initialized successfully.")
```
