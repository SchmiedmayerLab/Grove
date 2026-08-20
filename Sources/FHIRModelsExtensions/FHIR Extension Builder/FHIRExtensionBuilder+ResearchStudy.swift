//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ModelsR4


/// Identifies the research study a resource was collected for.
public struct ResearchStudyAttribution: Sendable {
    /// The study's identifier, referenced as `ResearchStudy/<id>`.
    public let studyId: String
    /// A human-readable label for the study, carried as the reference's display.
    public let display: String?

    public init(studyId: String, display: String? = nil) {
        self.studyId = studyId
        self.display = display
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRExtensionBuilderProtocol where Self == FHIRExtensionBuilder<ResearchStudyAttribution> {
    /// Attributes a resource to a research study via the HL7 `workflow-researchStudy`
    /// extension, replacing app-specific study-enrollment extensions.
    public static var researchStudy: Self {
        .init { (attribution: ResearchStudyAttribution, resource) in
            let url: FHIRPrimitive<FHIRURI> = "http://hl7.org/fhir/StructureDefinition/workflow-researchStudy"
            let reference = Reference(
                display: attribution.display?.asFHIRStringPrimitive(),
                reference: "ResearchStudy/\(attribution.studyId)".asFHIRStringPrimitive()
            )
            var studyExtension = Extension(url: url)
            studyExtension.value = .reference(reference)
            resource.extension?.removeAll { $0.url == url }
            resource.extension = (resource.extension ?? []) + [studyExtension]
        }
    }
}
