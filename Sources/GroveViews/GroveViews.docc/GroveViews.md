# ``GroveViews``

A Grove framework that provides a common set of SwiftUI views and related functionality used across the Grove ecosystem.

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->
## Overview

GroveViews provides reusable UI components that make everyday Grove app development easier.
It also holds the page shell that onboarding, account, consent and questionnaire pages share: a title that rises into the
navigation bar, and actions that float over content fading out beneath them.

@Row {
    @Column {
        @Image(source: "ViewState", alt: "An alert titled Failed Password Reset presented on a form via a ViewState.") {
            Drive a view's idle, processing and error states with ``ViewState``; an error state turns into an alert with `viewStateAlert(state:)`.
        }
    }
    @Column {
        @Image(source: "NameFields", alt: "A form with first, middle and last name rows; first and last name are filled in.") {
            Collect [`PersonNameComponents`](https://developer.apple.com/documentation/foundation/personnamecomponents) row by row
            with `NameFieldRow` from [GrovePersonalInfo](../../GrovePersonalInfo/GrovePersonalInfo.docc/GrovePersonalInfo.md).
        }
    }
    @Column {
        @Image(source: "Validation", alt: "A signup form whose email, password and username fields each show a red validation message.") {
            Validate input as it is typed and surface the failing rule under each field with [GroveValidation](../../GroveValidation/GroveValidation.docc/GroveValidation.md).
        }
    }
}

@Row {
    @Column {
        @Image(source: "Tiles", alt: "Three book recommendation tiles with their headers aligned leading, center and trailing.") {
            ``SimpleTile`` and ``TileHeader`` lay out a card with an icon, a title, a body and an action, aligned the way the page needs.
        }
    }
    @Column {
        @Image(source: "SkeletonLoading", alt: "A list whose rows are gray placeholder shapes that shimmer while content loads.") {
            `skeletonLoading(replicationCount:repeatInterval:spacing:)` stands in for content that is still on its way.
        }
    }
}

@Row {
    @Column {
        @Image(source: "Welcome", alt: "A page with a title, information areas and a floating primary button.") {
            ``PageView`` is the page every full-page step is built on; its title rises into the navigation bar and its actions float over the content.
        }
    }
    @Column {
        @Image(source: "ImageHeader", alt: "A permission page with a large tinted symbol above its title.") {
            ``PageHeader`` can head a page with a symbol, the way the system's own permission pages do.
        }
    }
}

@Row {
    @Column {
        @Image(source: "ListRow", alt: "A list row reading San Francisco on the left and 20 °C, Sunny on the right.") {
            ``ListRow`` pairs a label with its value and reflows for larger type sizes.
        }
    }
    @Column {
        @Image(source: "DescriptionGridRow", alt: "A grid with three rows, each a description label beside its content.") {
            ``DescriptionGridRow`` lines up a description beside its content inside a `Grid`.
        }
    }
    @Column {
        @Image(source: "OptionSetPicker", alt: "An inline picker titled Code with Option 1 and Option 2 both checked.") {
            ``OptionSetPicker`` lets the user check any number of an `OptionSet`'s values, inline or in a menu.
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

### Pages

The scaffold every full-page step is built on: onboarding, account, consent and questionnaire pages alike. Apply the
modifiers on their own to give a page of your own the same title, footer and edges.

- ``PageView``
- ``PageHeader``
- ``PageActions``
- ``ActionButtonRole``
- ``SwiftUICore/View/actionButtonStyle(_:)``
- ``SwiftUICore/View/actionButtonDisabled(_:_:)``
- ``SwiftUICore/View/floatingActions(_:)``
- ``SwiftUICore/View/fadesIntoBottomEdge()``
- ``SwiftUICore/View/risesIntoNavigationBar(_:subtitle:)``
- ``SwiftUICore/View/acceptsRisingTitle()``
- ``SwiftUICore/View/softScrollEdge()``

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

### Blocking Feedback

What still needs the participant looks the same in every module: a red tint on the element and a short message under it.
A control reports that it blocks; the row or card around it paints the tint in its own shape, so the mark always matches the form.

- ``BlockingMessage``
- ``SwiftUICore/View/reportsBlocking(_:)``
- ``SwiftUICore/View/highlightsBlockingContent(in:)``
- ``SwiftUICore/View/blockingHighlight(_:in:)``
- ``SwiftUICore/Color/blockingTint(for:)``
- ``SwiftUICore/Animation/revisit``

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
