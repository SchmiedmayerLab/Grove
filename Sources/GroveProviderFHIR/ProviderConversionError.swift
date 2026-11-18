//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Why a provider record could not be converted.
public enum ProviderConversionError: Error, Equatable, Sendable {
    /// The source token is not in the pinned provider catalog.
    case invalidSourceType
    /// The scope is not the provider's: an account for Withings and Google Health, the global one for Oura.
    case invalidScope
    /// The native identifier is empty.
    case invalidNativeIdentifier
    /// An interval's end is not after its start.
    case invalidInterval
    /// A civil day or its source-defined boundary doesn't exist in its time zone.
    case invalidCivilDay
    /// A decimal value overflows when its unit exponent is applied.
    case decimalOverflow
    /// A measure group states this measure type twice.
    case conflictingMeasurement(Int)
    /// A value is outside the domain of the quantity with this unit code or measurement identifier.
    case invalidQuantity(String)
    /// The source doesn't match the temporal shape or method of the measurement with this identifier.
    case invalidContract(String)
}
