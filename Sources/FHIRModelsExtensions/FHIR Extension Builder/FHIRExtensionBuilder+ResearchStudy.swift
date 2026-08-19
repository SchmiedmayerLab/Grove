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
    /// The study-definition revision in force when the resource was produced.
    public let revision: String?
    /// A human-readable label for the study, carried as the reference's display.
    public let display: String?

    public init(studyId: String, revision: String? = nil, display: String? = nil) {
        self.studyId = studyId
        self.revision = revision
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
            let revisionURL: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/core/StructureDefinition/grove-study-revision"
            let reference = Reference(
                display: attribution.display?.asFHIRStringPrimitive(),
                reference: "ResearchStudy/\(attribution.studyId)".asFHIRStringPrimitive()
            )
            var studyExtension = Extension(url: url)
            studyExtension.value = .reference(reference)
            resource.extension?.removeAll { $0.url == url || $0.url == revisionURL }
            resource.extension = (resource.extension ?? []) + [studyExtension]
            // `Reference.display` is narrative for a reader; the revision is machine-read,
            // and a study bundle is revised independently of any server that stores it, so
            // a versioned reference would assert a resource version that does not exist.
            if let revision = attribution.revision {
                var revisionExtension = Extension(url: revisionURL)
                revisionExtension.value = .string(revision.asFHIRStringPrimitive())
                resource.extension = (resource.extension ?? []) + [revisionExtension]
            }
        }
    }
}
