//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


/// Source document envelope dates, independent of the care described inside the original document.
public enum HealthKitSourceDocumentTime {
    /// The source API's meaning of the document sample dates.
    public enum Basis: String, CaseIterable, Sendable {
        /// When HealthKit downloaded a provider-issued FHIR resource to the device.
        case clinicalRecordDownload = "clinical-record-download"
        /// Document dates supplied by the creator of a HealthKit CDA sample.
        case cdaSourceDocumentPeriod = "cda-source-document-period"
    }

    /// The typed source-entity extension carrying one basis and one complete source period.
    public static let extensionURL = FHIRPrimitive(FHIRURI(stringLiteral: "\(Canonicals.root)/healthkit/StructureDefinition/healthkit-source-document-time"))

    package static func make(basis: Basis, period: Period) -> Extension {
        Extension(
            extension: [
                Extension(url: "basis", value: .code(FHIRPrimitive(FHIRString(basis.rawValue)))),
                Extension(url: "period", value: .period(period))
            ],
            url: extensionURL
        )
    }
}
