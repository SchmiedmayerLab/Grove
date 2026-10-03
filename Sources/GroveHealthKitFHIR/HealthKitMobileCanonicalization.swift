//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
import ModelsR4


/// Numeric serialization rules shared by Mobile scalar and aggregate producers.
///
/// Sensor and ECG timing use their separate exact Decimal contracts and never call this helper.
enum HealthKitMobileCanonicalization {
    /// Produces the exact Decimal value Grove will place on the wire for a binary64 scalar.
    static func scalarDecimalValue(_ value: Double) throws -> Decimal {
        do {
            return try GroveFHIRDecimal(value).decimal
        } catch {
            throw HealthKitValueFailure.shapeInvalid
        }
    }

    /// Produces a stable FHIR decimal without exposing Foundation's expanded IEEE-754 artifact.
    static func scalarDecimal(_ value: Double) throws -> FHIRPrimitive<FHIRDecimal> {
        FHIRPrimitive(FHIRDecimal(try scalarDecimalValue(value)))
    }
}

#endif
