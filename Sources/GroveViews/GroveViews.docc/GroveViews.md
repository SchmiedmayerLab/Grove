# ``GroveViews``

A Grove framework that provides a common set of SwiftUI views and related functionality used across the Grove ecosystem.

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->
## Overview

GroveViews provides easy-to-use and easily-reusable UI components that makes the everyday life of developing Grove applications easier.

@Row {
    @Column {
        @Image(source: "ViewState", alt: "A SwiftUI alert displayed using the GroveViews ViewState.") {
            Easily manage view state and display erroneous state using ``ViewState``.
        }
    }
    @Column {
        @Image(source: "NameFields", alt: "Three text fields to input your first, middle and last name.") {
            The [GrovePersonalInfo](../../GrovePersonalInfo/GrovePersonalInfo.docc/GrovePersonalInfo.md)
            provides easy to use abstractions for dealing with personal information.
            For example collecting the input for multiple [`PersonNameComponents`](https://developer.apple.com/documentation/foundation/personnamecomponents)
            fields using [`NameFieldRow`](../../GrovePersonalInfo/GrovePersonalInfo.docc/GrovePersonalInfo.md).
        }
    }
    @Column {
        @Image(source: "Validation", alt: "Three different kinds of text fields showing validation errors in red text.") {
            Perform and visualize input validation with ease using [GroveValidation](../../GroveValidation/GroveValidation.docc/GroveValidation.md).
        }
    }
}


## Topics

### Manage and communicate View State

- ``ViewState``
- ``SwiftUICore/View/viewStateAlert(state:)-(Binding<ViewState>)``
- ``SwiftUICore/View/viewStateAlert(state:)-(T)``
- ``OperationState``
- ``SwiftUICore/View/map(state:to:)``
- ``SwiftUICore/View/processingOverlay(isProcessing:overlay:)-(Bool,_)``
- ``SwiftUICore/View/processingOverlay(isProcessing:overlay:)-(ViewState,_)``

### Layout
Default layouts and utilities to automatically adapt your view layouts to dynamic type sizes, device orientation, and device size classes.

- ``SimpleTile``
- ``TileHeader``
- ``CompletedTileHeader``
- ``DynamicHStack``
- ``ListRow``
- ``DescriptionGridRow``
- ``ListHeader``

### Controls

- ``AsyncButton``
- ``SwiftUICore/EnvironmentValues/processingDebounceDuration``
- ``SwiftUICore/View/asyncButtonProcessingStyle(_:)``
- ``CanvasView``
- ``InfoButton``
- ``DismissButton``
- ``CaseIterablePicker``
- ``OptionSetPicker``
- ``SwiftUICore/View/shareSheet(item:)``
- ``SwiftUICore/View/shareSheet(items:)``

### Managed Navigation

- ``ManagedNavigationStack``
- ``ManagedNavigationStack/Path``

### Displaying Text

- ``Label``
- ``LazyText``
- ``MarkdownView``
- ``TextContentType``

### Images

- ``ImageReference``

### Conditional Modifiers

- ``SwiftUICore/View/if(_:transform:)``
- ``SwiftUICore/View/if(condition:transform:)``

### Animations and Visual Effects

- ``SwiftUICore/View/shimmer(repeatInterval:)``
- ``SwiftUICore/View/skeletonLoading(replicationCount:repeatInterval:spacing:)``

### Interact with the View Environment

- ``SwiftUICore/View/focusOnTap()``
- ``SwiftUICore/View/observeOrientationChanges(_:)``

### View Management

- ``ManagedViewUpdate``

### Styles

- ``ReverseLabelStyle``
- ``SwiftUI/LabelStyle/reverse``

### Readers

- ``HorizontalGeometryReader``
- ``WidthPreferenceKey``

### Error Handling

- ``AnyLocalizedError``
- ``SwiftUICore/EnvironmentValues/defaultErrorDescription``

### Modules

- ``ConfigureTipKit``

### System Programming Interfaces
- <doc:SPI>
