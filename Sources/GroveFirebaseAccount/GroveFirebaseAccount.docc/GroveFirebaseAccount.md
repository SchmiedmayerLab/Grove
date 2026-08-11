# ``GroveFirebaseAccount``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Firebase Auth support for GroveAccount.

## Overview

This Module adds support for Firebase Auth for GroveAccount by implementing an
 [`AccountService`](../../GroveAccount/GroveAccount.docc/GroveAccount.md).

Configure the account service by supplying it to the
 [`AccountConfiguration`](../../GroveAccount/GroveAccount.docc/GroveAccount.md).

> Note: For more information refer to the
[Account Configuration](../../GroveAccount/GroveAccount.docc/Setup%20Guides/Initial%20Setup.md#Account-Configuration) article.

```swift
import GroveAccount
import GroveFirebaseAccount

class ExampleAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration {
            AccountConfiguration(
                service: FirebaseAccountService()
                configuration: [/* ... */]
            )
        }
    }
}
```

> Note: Use the ``FirebaseAccountService/init(providers:emulatorSettings:passwordValidation:)`` to customize the enabled
    ``FirebaseAuthProviders`` or supplying Firebase Auth emulator settings.

## Topics

### Configuration

- ``FirebaseAccountService``
- ``FirebaseAuthProviders``

### Account Details

- ``GroveAccount/AccountDetails/creationDate``
- ``GroveAccount/AccountDetails/lastSignInDate``

### Errors

- ``FirebaseAccountError``
