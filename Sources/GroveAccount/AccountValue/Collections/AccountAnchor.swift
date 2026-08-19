//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFoundation


/// A `RepositoryAnchor` used for all account details.
///
/// This anchor is used with all ``AccountKey``s or other elements stored in the ``AccountDetails``.
public struct AccountAnchor: RepositoryAnchor, Sendable {}
