# ``ThreadLocal``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Thread-local storage with a value-typed interface.

## Overview

A property wrapper over the platform's thread-local slots. Each thread reading a ``ThreadLocal``
property sees its own value, initialised on first access and torn down with the thread.

Reach for it where a value must not be shared across threads and passing it explicitly is not
practical — a re-entrancy guard, or a depth counter inside a recursive encoder.

## Topics

### Declaring Storage

- ``ThreadLocal``
