# ``SpeziVapor``

<!--

This source file is part of the Stanford Spezi open source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
       
-->

Integrate Spezi modules into your Vapor application.

## Overview

SpeziVapor provides seamless integration between the Spezi framework and Vapor web applications, allowing you to leverage Spezi's modular architecture in your server-side Swift code.

## Configuration

Configure Spezi during your Vapor application setup using the `configure` method:

```swift
import SpeziVapor

func configure(_ app: Application) throws {
    app.spezi.configure(standard: MyStandard()) {
        ModuleA()
        ModuleB()
    }
}
```

> Important: Spezi must be configured before accessing any modules. Attempting to access modules before configuration will trigger a `preconditionFailure`.

## Usage

Access configured modules in your route handlers via the `req.spezi` subscript:

```swift
app.get("myRoute") { req async throws -> [MyData] in
    let myModule = req.spezi[MyModule.self]
    return dataModule.getMyData()
}
```

### Required Module Access

Access a module that must be configured:

```swift
let myModule = req.spezi[MyModule.self]
```

If the module is not configured, this triggers a `preconditionFailure`.

### Optional Module Access

Access a module that may or may not be configured:

```swift
if let optionalModule = req.spezi[OptionalModule?.self] {
    // Use the module
}
```

## Thread Safety

All modules accessed through SpeziVapor must conform to `Sendable` to ensure safe concurrent access across Vapor's async request handlers.

> Warning: Loading or unloading modules after initial configuration can lead to data races and is not recommended. Configure all modules once during application startup.

## Topics

### Essentials

- ``Vapor/Application``
- ``Vapor/Request``
