# ``SpeziFirebaseAccount``

<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Firebase Auth support for SpeziAccount.

## Overview

This Module adds support for Firebase Auth for SpeziAccount by implementing an
 [`AccountService`](../../SpeziAccount/SpeziAccount.docc/SpeziAccount.md).

Configure the account service by supplying it to the
 [`AccountConfiguration`](../../SpeziAccount/SpeziAccount.docc/SpeziAccount.md).

> Note: For more information refer to the
[Account Configuration](../../SpeziAccount/SpeziAccount.docc/Setup-Guides/Initial-Setup.md#Account-Configuration) article.

```swift
import SpeziAccount
import SpeziFirebaseAccount

class ExampleAppDelegate: SpeziAppDelegate {
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

- ``SpeziAccount/AccountDetails/creationDate``
- ``SpeziAccount/AccountDetails/lastSignInDate``

### Errors

- ``FirebaseAccountError``
