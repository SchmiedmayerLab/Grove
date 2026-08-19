# ``GroveStorage``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

On-disk storage for a Grove application, encrypted or otherwise.

## Overview

Two modules cover the two cases. Values that need no protection go to the local store; credentials,
keys and anything else sensitive belong in the keychain.

`GroveStorage` itself declares no API. It groups the family below so the package can be added as a
single dependency; import the individual products you need.

- term `GroveLocalStorage`: File-backed storage for values that do not need encrypting.
- term `GroveKeychainStorage`: Credentials and cryptographic keys, held in the system keychain.

### Adding a product

Select the products you need from the Grove package and import them where you use them.
The core Grove infrastructure has to be configured first; see the `Grove` module documentation.
