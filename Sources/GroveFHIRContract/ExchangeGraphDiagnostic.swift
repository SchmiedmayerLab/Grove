//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import ModelsR4


/// Canonicals and terminology for active/retraction event graphs.
public enum GroveLifecycleContract {
    /// Profile required on active conversion Provenance resources.
    public static let conversionProvenanceProfile: FHIRPrimitive<Canonical> =
        "https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-conversion-provenance"
    /// Profile required on retraction assertion Bundles.
    public static let retractionBundleProfile: FHIRPrimitive<Canonical> =
        "https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-retraction-bundle"
    /// Profile required on retraction assertion Provenance resources.
    public static let retractionProvenanceProfile: FHIRPrimitive<Canonical> =
        "https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-retraction-provenance"
    /// Lifecycle activity code asserted by a retraction Provenance.
    public static let sourceRecordRetracted = "source-record-retracted"
}


/// Exact structured producer diagnostic shared with the Grove conformance corpus.
public struct ExchangeGraphDiagnostic: Codable, Hashable, Sendable {
    public enum Severity: String, Codable, Hashable, Sendable {
        /// The record was refused or the graph is invalid.
        case error
        /// The record was accepted and something it carried was lost.
        case warning
    }

    public let code: String
    public let reason: String
    public let location: String
    public let severity: Severity

    public init(
        code: String,
        reason: String,
        location: String,
        severity: Severity = .error
    ) {
        self.code = code
        self.reason = reason
        self.location = location
        self.severity = severity
    }
}
