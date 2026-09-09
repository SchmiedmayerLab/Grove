# ``GroveAccount``

A Grove framework that provides account-related functionality including login, sign up and password reset.

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

## Overview

The `GroveAccount` framework fully abstracts setup and management of user account functionality for the
[Grove](../../Grove/Grove.docc/Grove.md) framework ecosystem.

@Row {
    @Column {
        @Image(source: "AccountSetup", alt: "The account setup page with e-mail and password fields, a Sign In button, a Create Account button, and Sign in with Apple.") {
            ``AccountSetup`` is the entry point: it lists every configured login option, here e-mail and password next to Sign in with Apple, with account creation one tap away.
        }
    }
    @Column {
        @Image(source: "SignUp", alt: "The signup form with credentials, name, gender identity, and date of birth sections.") {
            The signup form asks for exactly the values your ``AccountValueConfiguration`` collects, grouped by category.
        }
    }
    @Column {
        @Image(source: "AccountOverview", alt: "The account overview with the user's initials, name, e-mail address, and personal details.") {
            ``AccountOverview`` shows the signed-in account with its stored details and the sign-in and security settings.
        }
    }
    @Column {
        @Image(source: "AccountEdit", alt: "The account overview in edit mode with remove buttons next to each detail and an option to add a biography.") {
            Tapping Edit turns the overview into a form where users change, remove, or add details.
        }
    }
}

The ``AccountSetup`` and ``AccountOverview`` views are central to `GroveAccount`.
You use the ``AccountDetails`` collection within your views to visualize account information of the associated user account.

The setup, sign-up and follow-up pages sit on the page shell from [GroveViews](../../GroveViews/GroveViews.docc/GroveViews.md), and their
buttons never lock: tapping Sign Up with something missing marks the field, says what is missing, and moves the focus there, the same way
a questionnaire or a consent form does.

@Row(numberOfColumns: 4) {
    @Column {
        @Image(source: "IncompleteSignUp", alt: "The sign-up form after tapping Sign Up with empty fields; the e-mail, password and name fields are tinted red with a message under each.") {
            Every rule comes from [GroveValidation](../../GroveValidation/GroveValidation.docc/GroveValidation.md); the form only shows where it fails.
        }
    }
    @Column {
        @Image(source: "AccountDetails", alt: "The name and e-mail address page of the account overview.") {
            The overview's first section opens the name and e-mail address page, where each value is edited on its own.
        }
    }
    @Column {
        @Image(source: "ChangePassword", alt: "The change-password sheet with a new password that passes the rules and a repeat that does not match yet.") {
            Changing the password checks the service's rules as the user types and only lets a matching repeat through.
        }
    }
}

A forgotten password is reset from the setup page. A signed-in account is greeted with its summary and the app's way
forward; one that is missing required details finishes its setup first.

@Row(numberOfColumns: 4) {
    @Column {
        @Image(source: "ResetPassword", alt: "The reset-password sheet with an e-mail address field and a Reset Password button at the bottom.") {
            ``PasswordResetView`` asks for the account's identifier and hands it to the ``AccountService``.
        }
    }
    @Column {
        @Image(source: "SignedIn", alt: "The account setup page for a signed-in account: a summary card with initials, name and e-mail address, and Finish and Logout buttons at the bottom.") {
            ``AccountSetup`` with an account already signed in shows a summary and the `continue` button the app passes in, with Logout beneath it.
        }
    }
    @Column {
        @Image(source: "FinishSetup", alt: "The finish-account-setup sheet asking for a biography, with a Complete button at the bottom.") {
            The ``FollowUpInfoSheet`` asks for whatever the ``AccountValueConfiguration`` requires and the account lacks.
        }
    }
}

An ``AccountService`` provides an abstraction layer for managing different types of account management services
(e.g., email address and password-based service combined with an identity provider like Sign in with Apple).

> Note: The [GroveFirebase](../../GroveFirebase/GroveFirebase.docc/GroveFirebase.md)
framework provides the [`FirebaseAccountService`](../../GroveFirebaseAccount/GroveFirebaseAccount.docc/GroveFirebaseAccount.md)
you can use to configure an Account Service based on Firebase.

## Setup

You need to add the Grove Account Swift package to
[your app in Xcode](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app#) or
[Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package).

> Important: If your application is not yet configured to use Grove, follow the [Grove setup article](../../Grove/Grove.docc/Initial-Setup.md) to set up the core Grove infrastructure.

The <doc:Initial-Setup> article provides a quick-start guide to set up `GroveAccount` in your App.

Refer to the <doc:Creating-your-own-Account-Service> article if you plan on implementing your own Account Service.


## Topics

### Configuration

- <doc:Initial-Setup>
- ``AccountConfiguration``
- ``AccountValueConfiguration``

### Account Details

- ``Account``
- ``AccountDetails``
- <doc:Adding-new-Account-Values>

### Account UI

- ``AccountSetup``
- ``AccountOverview``
- ``AccountHeader``
- ``FollowUpInfoSheet``
- ``SwiftUICore/View/accountRequired(_:accountSetupIsComplete:setupSheet:)``
- ``SwiftUICore/EnvironmentValues/accountRequired``

### Environment & Preferences

- ``SwiftUICore/View/preferredAccountSetupStyle(_:)``
- ``SwiftUICore/View/followUpBehaviorAfterSetup(_:)``

### Reacting to Events

- ``AccountNotifyConstraint``
- ``AccountNotifications``

### Account Service

- <doc:Creating-your-own-Account-Service>
- ``AccountService``
- ``IdentityProvider``
- ``SecurityRelatedModifier``
- ``AccountModifications``

### External Storage

- <doc:Custom-Storage-Provider>
- ``AccountStorageProvider``
- ``ExternalAccountStorage``
- ``AccountDetailsCache``

### In Memory Implementations

In memory implementations are useful for SwiftUI Previews and UI testing purposes.
- ``InMemoryAccountService``
- ``InMemoryAccountStorageProvider``
