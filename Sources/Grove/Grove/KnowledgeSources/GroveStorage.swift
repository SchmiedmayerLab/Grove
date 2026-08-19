//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFoundation


/// A ``SharedRepository`` implementation that is anchored to ``GroveAnchor``.
///
/// This represents the central ``Grove/Grove`` storage module.
@_documentation(visibility: internal)
public typealias GroveStorage = ValueRepository<GroveAnchor>
