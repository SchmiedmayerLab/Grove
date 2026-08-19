# ``GroveFileFormats``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Readers and writers for the file formats Grove applications exchange.

## Overview

Health and research data leaves a device in standard formats. This family holds the ones Grove
writes directly, rather than through a service SDK.

`GroveFileFormats` itself declares no API. It groups the family below so the package can be added as a
single dependency; import the individual products you need.

- term `EDFFormat`: Writes European Data Format (EDF/EDF+) recordings, the standard for biosignal data.

### Adding a product

Select the products you need from the Grove package and import them where you use them.
The core Grove infrastructure has to be configured first; see the `Grove` module documentation.
