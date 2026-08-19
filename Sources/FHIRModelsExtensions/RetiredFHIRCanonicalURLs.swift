//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveLegacyIdentifiers


/// Extensions this project has stopped writing, declared so that reads keep resolving them.
///
/// The builders behind these are gone: an `HKDevice` and its `HKSourceRevision` are now a contained
/// `Device`, and the absolute time range is `effective[x]` plus the timezone extension. Resources
/// uploaded before that carry them regardless, and a published canonical never stops being understood
/// — so the declarations stay, with no writer behind them.
///
/// ```swift
/// let start = observation.extensions(for: RetiredFHIRCanonicalURLs.absoluteTimeRangeStart).first
/// ```
public enum RetiredFHIRCanonicalURLs {
    /// Absolute start of an observation's effective period, as seconds since 1970.
    public static let absoluteTimeRangeStart = FHIRCanonicalURL(
        "https://grovealliance.org/fhir/core/StructureDefinition/absoluteTimeRangeStart",
        superseding: SupersededFHIRURLs.absoluteTimeRangeStart
    )

    /// Absolute end of an observation's effective period, as seconds since 1970.
    public static let absoluteTimeRangeEnd = FHIRCanonicalURL(
        "https://grovealliance.org/fhir/core/StructureDefinition/absoluteTimeRangeEnd",
        superseding: SupersededFHIRURLs.absoluteTimeRangeEnd
    )

    /// Encoded `HKDevice` an observation was created from, one sub-extension per property.
    public static let sourceDevice = FHIRCanonicalURL(
        "https://grovealliance.org/fhir/core/StructureDefinition/sourceDevice",
        superseding: SupersededFHIRURLs.sourceDevice
    )

    /// Encoded `HKSourceRevision` an observation was created from, one sub-extension per property.
    public static let sourceRevision = FHIRCanonicalURL(
        "https://grovealliance.org/fhir/core/StructureDefinition/sourceRevision",
        superseding: SupersededFHIRURLs.sourceRevision
    )

    /// Every retired identifier, for a consumer sweeping an archive rather than naming one.
    public static let all: [FHIRCanonicalURL] = [
        absoluteTimeRangeStart, absoluteTimeRangeEnd, sourceDevice, sourceRevision
    ]
}
