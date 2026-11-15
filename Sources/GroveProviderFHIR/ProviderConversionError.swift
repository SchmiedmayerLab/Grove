//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public enum ProviderConversionError: Error, Equatable, Sendable {
    case invalidSourceType
    case invalidScope
    case invalidNativeIdentifier
    case invalidInterval
    case invalidCivilDay
    case decimalOverflow
    case conflictingMeasurement(Int)
    case invalidQuantity(String)
    case invalidContract(String)
}
