# ``SpeziNumerics``

Additional numeric types in Swift.

<!--
#
# This source file is part of the Stanford Spezi open-source project
#
# SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

## Overview

SpeziNumerics provides implementation of numeric types that are not supported out of the box in the standard library
or are only found in networking protocols.

## Topics

### Health Data Types

- ``MedFloat16``
- ``MedFloat32``

### 24 Bit Integer Support

- ``NIOCore/ByteBuffer/getUInt24(at:endianness:)``
- ``NIOCore/ByteBuffer/readUInt24(endianness:)``
- ``NIOCore/ByteBuffer/setUInt24(_:at:endianness:)``
- ``NIOCore/ByteBuffer/writeUInt24(_:endianness:)``
- ``NIOCore/ByteBuffer/getInt24(at:endianness:)``
- ``NIOCore/ByteBuffer/readInt24(endianness:)``
- ``NIOCore/ByteBuffer/setInt24(_:at:endianness:)``
- ``NIOCore/ByteBuffer/writeInt24(_:endianness:)``
