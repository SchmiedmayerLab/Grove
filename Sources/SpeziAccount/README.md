<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Spezi Account


A Spezi framework that provides account-related functionality including login, sign up and password reset.

## Overview

The `SpeziAccount` framework fully abstracts setup and management of user account functionality for the
[Spezi](../Spezi/README.md) framework ecosystem.

|![Screenshot displaying the account setup view with an email and password prompt and a Sign In with Apple button.](SpeziAccount.docc/Resources/AccountSetup.png#gh-light-mode-only) ![Screenshot displaying the account setup view with an email and password prompt and a Sign In with Apple button.](SpeziAccount.docc/Resources/AccountSetup~dark.png#gh-dark-mode-only)|![Screenshot displaying the Signup Form for Account setup.](SpeziAccount.docc/Resources/SignupForm.png#gh-light-mode-only) ![Screenshot displaying the Signup Form for Account setup.](SpeziAccount.docc/Resources/SignupForm~dark.png#gh-dark-mode-only)|![Screenshot displaying the Account Overview.](SpeziAccount.docc/Resources/AccountOverview.png#gh-light-mode-only) ![Screenshot displaying the Account Overview.](SpeziAccount.docc/Resources/AccountOverview~dark.png#gh-dark-mode-only)|
|:--:|:--:|:--:|
|The `AccountSetup` is the central view for account onboarding, facilitating account login and creation. |The `SignupForm` is used by email-password-based AccountServices by default. |The `AccountOverview` is used to view and modify the user details of the currently associated account.|


The ``AccountSetup`` and ``AccountOverview`` views are central to `SpeziAccount`.
You use the ``AccountDetails`` collection within your views to visualize account information of the associated user account.

An ``AccountService`` provides an abstraction layer for managing different types of account management services
(e.g., email address and password-based service combined with an identity provider like Sign in with Apple).

For more information, please refer to the [API documentation](SpeziAccount.docc/SpeziAccount.md).

> [!NOTE]
> The [SpeziFirebase](../SpeziFirebase/README.md)
framework provides the `FirebaseAccountService`
you can use to configure an Account Service base on the Google Firebase service.


### Setup

Add the Spezi monorepo package to your app and select the `SpeziAccount` product.

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
        .product(name: "SpeziAccount", package: "Spezi")
    ]
)
```

> [!IMPORTANT]
> If your application is not yet configured to use Spezi, follow the [Spezi setup article](../Spezi/Spezi.docc/Initial%20Setup.md) to set up the core Spezi infrastructure.

[Initial Setup](SpeziAccount.docc/Setup%20Guides/Initial%20Setup.md)
article provides a quick-start guide to set up `SpeziAccount` in your App.
Refer to the
[Implementing an Account Service](SpeziAccount.docc/AccountService/Creating%20your%20own%20Account%20Service.md)
article if you plan on implementing your own Account Service.

The Spezi Template Application provides a great starting point and example using the Spezi Account module.

## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing%20Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
