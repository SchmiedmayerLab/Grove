<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Spezi Storage


The Spezi Storage framework provides two Modules that enable on-disk storage of information.
The  `LocalStorage` module can be used to store information that does not need to be encrypted.
Credentials, keys, and other sensitive information that needs to be encrypted may be stored by using the `KeychainStorage` module.


## Setup

Add the Spezi monorepo package to your app and select the `SpeziLocalStorage` and `SpeziKeychainStorage` products.

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
        .product(name: "SpeziLocalStorage", package: "Spezi"),
        .product(name: "SpeziKeychainStorage", package: "Spezi")
    ]
)
```

> [!IMPORTANT]
> If your application is not yet configured to use Spezi, follow the [Spezi setup article](../Spezi/Spezi.docc/Initial%20Setup.md) to set up the core Spezi infrastructure.

You can configure the `LocalStorage` or `KeychainStorage` module in the `SpeziAppDelegate`.

> [!IMPORTANT]
> If you use SpeziStorage on the macOS platform, ensure to add the [`Keychain Access Groups` entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/keychain-access-groups) to the enclosing Xcode project via *PROJECT_NAME > Signing&Capabilities > + Capability*. The array of keychain groups can be left empty, only the base entitlement is required.

```swift
import Spezi
import SpeziLocalStorage
import SpeziKeychainStorage

class ExampleDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            LocalStorage()
            KeychainStorage()
            // ...
        }
    }
}
```

You can then use the `LocalStorage` or `KeychainStorage` class in any SwiftUI view.

```swift
struct ExampleStorageView: View {
    @Environment(LocalStorage.self) var localStorage
    @Environment(KeychainStorage.self) var keychainStorage

    var body: some View {
        // ...
    }
}
```

Alternatively, it is common to use the `LocalStorage` or `KeychainStorage` module in other modules as a dependency: [Spezi Module dependencies](../Spezi/Spezi.docc/Module/Module%20Dependency.md).


## Local Storage

The `LocalStorage` module enables the on-disk storage of data in mobile applications.

The `LocalStorage` module defaults to storing data encrypted supported by the `KeychainStorage` module.
The `LocalStorageKey` type is used to define storage entries, and specify how data should be persisted.


## Keychain Storage

The `KeychainStorage` module allows for the encrypted storage of small chunks of sensitive user data, such as usernames and passwords for internet services, or cryptographic keys, using Apple's [Keychain documentation](https://developer.apple.com/documentation/security/keychain_services/keychain_items/using_the_keychain_to_manage_user_secrets).

Credentials can be stored in the Secure Enclave (if available) or the Keychain. Credentials stored in the Keychain can be made synchronizable between different instances of user devices.

### Handling Credentials

Use the `KeychainStorage` module to store a set of `Credentials` instances in the Keychain associated with a server that is synchronizable between different devices.



### Handling Keys

Similar to `Credentials` instances, you can also use the `KeychainStorage` module to interact with cryptographic keys.



For more information, please refer to the [SpeziLocalStorage](../SpeziLocalStorage/SpeziLocalStorage.docc/SpeziLocalStorage.md) and [SpeziKeychainStorage](../SpeziKeychainStorage/KeychainStorage.docc/KeychainStorage.md) documentation.


## The Spezi Template Application

The Spezi Template Application provides a great starting point and example using the Spezi Storage module.


## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing%20Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
