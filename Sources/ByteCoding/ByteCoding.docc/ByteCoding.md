# ``ByteCoding``

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Encode and decode types from and to their byte representation.

## Overview

This library provides a standardized approach of encoding and decoding types from and to their byte representation.

## Topics

### Codable Types

Byte Codable types that are composed of other codable types that have a fixed byte representation.

- ``ByteCodable``
- ``ByteEncodable``
- ``ByteDecodable``

### Primitive Codable Types

Byte Codable types which are not composed out of other types and which might be represented in little or big endian representation.

- ``PrimitiveByteCodable``
- ``PrimitiveByteEncodable``
- ``PrimitiveByteDecodable``
