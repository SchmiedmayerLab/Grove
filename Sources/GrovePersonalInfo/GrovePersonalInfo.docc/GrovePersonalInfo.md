# ``GrovePersonalInfo``

A GroveViews target that provides a common set of SwiftUI views and related functionality for managing personal information.

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

## Overview

GrovePersonalInfo provides predefined UI components to deal with common cases in visualizing or collecting personal information.

@Column {
    @Image(source: "NameFields", alt: "Three text fields to input your first, middle and last name.") {
        Collect the input for multiple [`PersonNameComponents`](https://developer.apple.com/documentation/foundation/personnamecomponents)
        fields using [`NameFieldRow`](GrovePersonalInfo.md).
    }
}

## Topics

### Person Name

- ``NameTextField``
- ``NameFieldRow``

### User Profile

- ``UserProfileView``
