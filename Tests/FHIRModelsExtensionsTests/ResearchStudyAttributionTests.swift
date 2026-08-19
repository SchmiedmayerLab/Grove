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
    private static let revisionURL = "https://grovealliance.org/fhir/core/StructureDefinition/grove-study-revision"

    private func attributed(_ attribution: ResearchStudyAttribution) throws -> Observation {
        var observation = Observation(code: CodeableConcept(), status: FHIRPrimitive(.final))
        try FHIRExtensionBuilder.researchStudy.apply(input: attribution, to: &observation)
        return observation
    }

    private func value(_ url: String, in observation: Observation) -> Extension.ValueX? {
        observation.extension?.first { $0.url.value?.url.absoluteString == url }?.value
    }

    @Test
    func theStudyIsReferencedAndTheRevisionIsMachineReadable() throws {
        let observation = try attributed(.init(studyId: "heart-counts", revision: "4", display: "My Heart Counts"))

        guard case let .reference(reference)? = value(Self.studyURL, in: observation) else {
            Issue.record("Expected a study reference")
            return
        }
        #expect(reference.reference?.value?.string == "ResearchStudy/heart-counts")
        // The revision used to ride in `display`, which R4 defines as narrative for a
        // reader — a renderer showed the study as "4".
        #expect(reference.display?.value?.string == "My Heart Counts")
        #expect(value(Self.revisionURL, in: observation) == .string("4".asFHIRStringPrimitive()))
    }

    @Test
    func aStudyWithoutARevisionWritesOnlyTheReference() throws {
        let observation = try attributed(.init(studyId: "heart-counts"))

        #expect(value(Self.studyURL, in: observation) != nil)
        #expect(value(Self.revisionURL, in: observation) == nil)
    }

    /// Re-running the conversion over an already-attributed resource must not accumulate
    /// copies of either extension.
    @Test
    func reapplyingReplacesRatherThanAppends() throws {
        var observation = try attributed(.init(studyId: "heart-counts", revision: "4"))
        try FHIRExtensionBuilder.researchStudy.apply(
            input: .init(studyId: "heart-counts", revision: "5"),
            to: &observation
        )

        #expect(observation.extension?.count == 2)
        #expect(value(Self.revisionURL, in: observation) == .string("5".asFHIRStringPrimitive()))
    }
}
