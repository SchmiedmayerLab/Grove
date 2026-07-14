# ``XCTSpeziAccount``

Making writing UI Tests for SpeziAccount-related functionality easier.

<!--

This source file is part of the Spezi open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

## Topics

### Login

- ``XCUIAutomation/XCUIApplication/login(email:password:)``
- ``XCUIAutomation/XCUIApplication/login(username:password:)``

### Signup Form

- ``XCUIAutomation/XCUIApplication/fillSignupForm(email:password:name:genderIdentity:supplyDateOfBirth:)``
- ``XCUIAutomation/XCUIApplication/updateGenderIdentity(from:to:file:line:)``
- ``XCUIAutomation/XCUIApplication/changeDateOfBirth()``
- ``XCUIAutomation/XCUIApplication/closeSignupForm(discardChangesIfAsked:)``
