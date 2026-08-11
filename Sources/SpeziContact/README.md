<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Spezi Contact


Views to display contact information.

## Overview

The Spezi Contact Swift Package provides views and infrastructure to display contact information in an application.

| ![Screenshot showing a ContactsList rendered within the Spezi Template Application.](SpeziContact.docc/Resources/Overview.png#gh-light-mode-only) ![Screenshot showing a ContactsList rendered within the Spezi Template Application.](SpeziContact.docc/Resources/Overview~dark.png#gh-dark-mode-only) |
 |:---:|
 | A `ContactsList` rendered in the Spezi Template Application. |

## Setup

### Add Spezi Contact as a Dependency

Add the Spezi monorepo package to your app and select the `SpeziContact` product.

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
        .product(name: "SpeziContact", package: "Spezi")
    ]
)
```

## Example

The Contact module enables displaying contact information in an application.
Information can be encoded in `Contact` and `ContactOption` to configure the contact views.
The `ContactView` and `ContactsList` can display the contact information in a card-like layout and list.

The following example shows how `Contact`s can be created to encode an individual's contact information and displayed in a `ContactsList` within a SwiftUI [`View`](https://developer.apple.com/documentation/swiftui/view).

```swift
import SpeziContact
import SwiftUI


struct ContactsExample: View {
    let contact = Contact(
        name: PersonNameComponents(givenName: "Leland", familyName: "Stanford"),
        image: Image(systemName: "figure.wave.circle"),
        title: "Founder",
        description: """
        Leland Stanford is the founder of Stanford University.
        """,
        organization: "Stanford University",
        address: {
            let address = CNMutablePostalAddress()
            address.country = "USA"
            address.state = "CA"
            address.postalCode = "94305"
            address.city = "Stanford"
            address.street = "450 Serra Mall"
            return address
        }(),
        contactOptions: [
            .call("+1 (650) 123-4567"),
            .text("+1 (650) 123-4567"),
            .email(addresses: ["example@stanford.edu"], subject: "Hi!")
        ]
    )

    var body: some View {
        ContactsList(contacts: [contact])
    }
}
```

For more information, please refer to the [API documentation](SpeziContact.docc/SpeziContact.md).


## The Spezi Template Application

The Spezi Template Application provides a great starting point and example using the `SpeziContact` module.


## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing-Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
