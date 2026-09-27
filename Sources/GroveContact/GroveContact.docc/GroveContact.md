# ``GroveContact``

<!--
                  
This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
             
-->

Views to display contact information.


## Overview

The Grove Contact Swift Package provides views and infrastructure to display contact information in an application.

@Row {
    @Column {
        @Image(source: "ContactsList", alt: "A list of contact cards, each with a name, title, organization, description, a row of call, text, email and website buttons, and a postal address.") {
            A ``ContactsList`` stacks one ``ContactView`` card per ``Contact``, each with its contact options and postal address.
        }
    }
}

## Setup

### Add Grove Contact as a Dependency

You need to add the GroveContact Swift package to
[your app in Xcode](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app#) or
[Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package).

## Example

The Contact module enables displaying contact information in an application. 
Information can be encoded in ``Contact`` and ``ContactOption`` to configure the contact views.
The ``ContactView`` and ``ContactsList`` can display the contact information in a card-like layout and list.

The following example shows how ``Contact``s can be created to encode an individual's contact information and displayed in a ``ContactsList`` within a SwiftUI View.

```swift
import GroveContact
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


## Topics

### Views

The contact views that can be used to display contact information.

- ``ContactView``
- ``ContactsList``

### Models

Use the `Contact` and `ContactOption` to configure the contact views.

- ``Contact``
- ``ContactOption``
