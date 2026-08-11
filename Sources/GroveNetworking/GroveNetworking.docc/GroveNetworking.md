# ``GroveNetworking``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Binary encoding and numeric helpers for wire and file formats.

## Overview

Types for moving structured values across a byte boundary — a Bluetooth characteristic, a file
header, a network frame — with the testing helpers that keep an encoding honest.

`GroveNetworking` itself declares no API. It groups the family below so the package can be added as a
single dependency; import the individual products you need.

- term `ByteCoding`: Encode and decode values to and from a byte buffer.
- term `ByteCodingTesting`: Round-trip and identity assertions for `ByteCodable` conformances.
- term `GroveNumerics`: Numeric types and conversions shared by the encoders.

### Adding a product

Select the products you need from the Grove package and import them where you use them.
The core Grove infrastructure has to be configured first; see the `Grove` module documentation.
