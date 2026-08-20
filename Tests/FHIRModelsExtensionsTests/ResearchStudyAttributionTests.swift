//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import FHIRModelsExtensions
import ModelsR4
import Testing


@Suite
struct ResearchStudyAttributionTests {
    private static let studyURL = "http://hl7.org/fhir/StructureDefinition/workflow-researchStudy"

    private func attributed(_ attribution: ResearchStudyAttribution) throws -> Observation {
        var observation = Observation(code: CodeableConcept(), status: FHIRPrimitive(.final))
        try FHIRExtensionBuilder.researchStudy.apply(input: attribution, to: &observation)
        return observation
    }

    private func value(_ url: String, in observation: Observation) -> Extension.ValueX? {
        observation.extension?.first { $0.url.value?.url.absoluteString == url }?.value
    }

    @Test
    func theStudyIsReferencedWithANarrativeLabel() throws {
        let observation = try attributed(.init(studyId: "heart-counts", display: "My Heart Counts"))

        guard case let .reference(reference)? = value(Self.studyURL, in: observation) else {
            Issue.record("Expected a study reference")
            return
        }
        #expect(reference.reference?.value?.string == "ResearchStudy/heart-counts")
        #expect(reference.display?.value?.string == "My Heart Counts")
    }

    @Test
    func aStudyWritesOnlyTheStandardReferenceExtension() throws {
        let observation = try attributed(.init(studyId: "heart-counts"))

        #expect(value(Self.studyURL, in: observation) != nil)
        #expect(observation.extension?.count == 1)
    }

    /// Re-running the conversion over an already-attributed resource must not accumulate
    /// copies of either extension.
    @Test
    func reapplyingReplacesRatherThanAppends() throws {
        var observation = try attributed(.init(studyId: "heart-counts"))
        try FHIRExtensionBuilder.researchStudy.apply(
            input: .init(studyId: "heart-counts-2"),
            to: &observation
        )

        #expect(observation.extension?.count == 1)
        guard case let .reference(reference)? = value(Self.studyURL, in: observation) else {
            Issue.record("Expected a study reference")
            return
        }
        #expect(reference.reference?.value?.string == "ResearchStudy/heart-counts-2")
    }
}
