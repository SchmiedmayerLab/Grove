# ``GroveValidation``

Perform input validation and visualize it to the user.

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

## Overview

`GroveValidation` can be used to perform input validation on `String`-based inputs and provides easy-to-use
mechanism to communicate validation feedback back to the user.
The library is based on a rule-based approach using ``ValidationRule``s.
Failed input is marked the way every Grove module marks what still needs attention: the row or card holding the field takes the shared red tint that questionnaires put on an unanswered question and consent forms on a missing choice, so a participant learns one signal and recognises it everywhere. The field only reports that it blocks (`reportsBlocking(_:)` from GroveViews); a form row paints itself, and a card paints its own shape through `highlightsBlockingContent(in:)`.

@Row {
    @Column {
        @Image(source: "Validation", alt: "A signup form whose email, password and username fields are marked red, each with the failed rule below the input.") {
            A ``VerifiableTextField`` that fails a ``ValidationRule`` is marked in the same red as an unanswered question or consent element, with the rule's message below the input, until the input passes.
        }
    }
}

### Performing Validation

The only thing you have to do, is to set up the ``SwiftUICore/View/validate(input:rules:)-(_,ValidationRule...)`` modifier for your
text input.
Supply your input and validation rules.

The below code example shows a basic validation setup.
Note that we are using the ``VerifiableTextField`` to automatically visualize validation errors to the user.

```swift
@State var phrase: String = ""

var body: some View {
    Form {
        VerifiableTextField("your favorite phrase", text: $phrase)
            .validate(input: phrase, rules: .nonEmpty)
    }
}
```

> Note: The inner views can access the ``ValidationEngine`` using the [Environment](<https://developer.apple.com/documentation/swiftui/environment/init(_:)-8slkf>)
property wrapper.

### Managing Validation

Parent views can access the validation state of their child views using the ``ValidationState`` property wrapper
and the ``SwiftUICore/View/receiveValidation(in:)`` modifier.

The code example below shows
how you can use the validation state of your subview to perform final validation on a button press.

```swift
@ValidationState var validation

var body: some View {
    Form {
        // all subviews that collect data ...

        Button("Submit") {
            guard validation.validateSubviews() else {
                return
            }

            // save data ...
        }
    }
        .receiveValidation(in: $validation)
}
```

## Topics

### Performing Validation

- ``ValidationRule``
- ``SwiftUICore/View/validate(input:rules:)-(_,ValidationRule...)``
- ``SwiftUICore/View/validate(input:rules:)-(_,[ValidationRule])``
- ``SwiftUICore/View/validate(_:message:)``

### Managing Validation

- ``ValidationState``
- ``SwiftUICore/View/receiveValidation(in:)``

### Configuration

- ``SwiftUICore/EnvironmentValues/validationConfiguration``
- ``SwiftUICore/EnvironmentValues/validationDebounce``

### Visualizing Validation

- ``VerifiableTextField``
- ``ValidationResultsView``
- ``FailedValidationResult``
