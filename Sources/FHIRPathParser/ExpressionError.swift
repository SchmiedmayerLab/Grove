//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@preconcurrency import Antlr4


public struct ExpressionError: Error {
    // periphery:ignore - parse-position payload surfaced when the error is string-interpolated or reflected
    let token: Token?
    let underlyingError: Error
}
