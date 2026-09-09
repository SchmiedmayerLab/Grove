# ``GrovePersonalInfo``

SwiftUI views for collecting and displaying personal information.

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

## Overview

GrovePersonalInfo provides predefined UI components to deal with common cases in visualizing or collecting personal information.

@Row {
    @Column {
        @Image(source: "NameFields", alt: "A form with first, middle and last name fields; first and last name are filled in, the middle name shows its placeholder.") {
            A ``NameFieldRow`` per component writes straight into one [`PersonNameComponents`](https://developer.apple.com/documentation/foundation/personnamecomponents) value.
        }
    }
}

## Topics

### Person Name

- ``NameTextField``
- ``NameFieldRow``

### User Profile

- ``UserProfileView``
