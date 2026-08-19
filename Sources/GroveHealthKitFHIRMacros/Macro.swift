//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Synthesizes the FHIR coding members of a platform enum: `display` and `code` (both derived from the enum case
/// names), plus the static `fhirSystemName`, `fhirSystemTitle`, `fhirPlatformTypeName` and `fhirPublishedCodes`
/// the vocabulary generator reads to publish the type's code system.
///
/// A value the platform reports but this build does not know is coded as
/// `unrecognized-platform-value` — a code the published system defines, so it stays distinguishable from an
/// `unknown` case Apple declares itself.
///
/// ## Example:
/// ```swift
/// @SynthesizeDisplayProperty(HKDevicePlacementSide.self, .unknown, .left, .right, .central)
/// extension HKDevicePlacementSide {}
/// ```
///
/// - parameter type: The type the macro should operate on.
/// - parameter cases: The enum's cases.
/// - parameter additionalCases: Additional cases not listed in `cases`. This property exists to support cases whose availability is newer than the package's deployment target.
@attached(
    member,
    names: named(display), named(code), named(fhirSystemName), named(fhirSystemTitle),
    named(fhirPlatformTypeName), named(fhirPublishedCodes)
)
public macro SynthesizeDisplayProperty<T>(
    _ type: T.Type,
    _ cases: T...,
    additionalCases: StaticString...
) = #externalMacro(module: "GroveHealthKitFHIRMacrosImpl", type: "SynthesizeDisplayPropertyMacro")
