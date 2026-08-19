# ``GroveFirebase``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Firebase-backed account, storage and Firestore integration for Grove.

## Overview

Wires a Grove application to a Firebase project: authentication, account detail persistence, file
storage and Firestore access, each behind the matching Grove abstraction so app code stays
provider-agnostic.

`GroveFirebase` itself declares no API. It groups the family below so the package can be added as a
single dependency; import the individual products you need.

- term `GroveFirebaseConfiguration`: Configures the Firebase app; required by the other modules.
- term `GroveFirebaseAccount`: An account service backed by Firebase Authentication.
- term `GroveFirebaseAccountStorage`: Persists account details that Firebase Auth itself cannot hold.
- term `GroveFirebaseStorage`: File storage backed by Cloud Storage for Firebase.
- term `GroveFirestore`: A standard that writes exported data into Firestore.

### Adding a product

Select the products you need from the Grove package and import them where you use them.
The core Grove infrastructure has to be configured first; see the `Grove` module documentation.
