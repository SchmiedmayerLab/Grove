//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
@testable import GroveSensorKitFHIR
import ModelsR4
import Testing


/// The converter refuses a context whose references cannot mean what the graph needs them to mean.
@Suite
struct SensorFHIRContextValidationTests {
    private static let start = Date(timeIntervalSince1970: 1_787_009_400)

    private static func context(
        subject: Reference,
        researchStudies: [Reference] = []
    ) throws -> SensorConversionContext {
        SensorConversionContext(
            subject: subject,
            converter: SensorApplication(
                sourceDeviceToken: "org.grovealliance.conformance-fixture",
                name: "Grove Conformance Fixture",
                version: "0.5.0"
            ),
            graphIdentifierSystem: "https://study.example.org/fhir/identifiers/sensor-graph",
            recordedAt: start.addingTimeInterval(20),
            researchStudies: researchStudies
        )
    }

    private static func record() throws -> SensorRecord {
        .recordingDocument(try SensorRecordingDocument(
            identifier: BusinessIdentifier(
                system: "https://study.example.org/fhir/identifiers/sensorkit-record",
                value: "ambient-light-1"
            ),
            sourceTypeIdentifier: "SRSensor.ambientLightSensor",
            type: SensorCode(
                system: "https://grovealliance.org/fhir/sensor/CodeSystem/grove-sensor-recording",
                code: "ambient-light",
                display: "Ambient light"
            ),
            title: "Ambient light recording",
            format: .ambientLightSamples,
            payload: .inline(Data("t,lux\n0,120\n".utf8)),
            rawPayloadAdmission: .verifiedSanitizedInput
        ))
    }

    @Test("A subject that is not a Patient reference is rejected")
    func rejectsNonPatientSubject() throws {
        let context = try Self.context(subject: SensorFHIRIdentityTestSupport.logicalReference(
            resourceType: .group,
            value: "cohort-1"
        ))
        #expect(throws: SensorConversionError.invalidReference(
            field: "subject",
            expectedResourceType: .patient
        )) {
            try SensorConverter().convert(Self.record(), context: context)
        }
    }

    @Test("A study reference pointing at the wrong resource type is rejected")
    func rejectsNonStudyReference() throws {
        let context = try Self.context(
            subject: SensorFHIRIdentityTestSupport.subject,
            researchStudies: [
                SensorFHIRIdentityTestSupport.logicalReference(
                    resourceType: .patient,
                    value: "example"
                )
            ]
        )
        #expect(throws: SensorConversionError.invalidReference(
            field: "researchStudies",
            expectedResourceType: .researchStudy
        )) {
            try SensorConverter().convert(Self.record(), context: context)
        }
    }

    @Test("The same study listed twice would create an ambiguous graph and is rejected")
    func rejectsDuplicateStudy() throws {
        let study = try SensorFHIRIdentityTestSupport.logicalReference(
            resourceType: .researchStudy,
            value: "heart-counts"
        )
        let context = try Self.context(
            subject: SensorFHIRIdentityTestSupport.subject,
            researchStudies: [study, study]
        )
        #expect(throws: SensorConversionError.duplicateReference(field: "researchStudies")) {
            try SensorConverter().convert(Self.record(), context: context)
        }
    }

    @Test("A batch reports the typed reason for each rejected record rather than relabelling it")
    func batchReportsTypedReasons() throws {
        let context = try Self.context(subject: SensorFHIRIdentityTestSupport.logicalReference(
            resourceType: .group,
            value: "cohort-1"
        ))
        let result = SensorConverter().convert([try Self.record()], context: context)
        #expect(result.conversions.isEmpty)
        #expect(result.failures.map(\.reason) == [
            .invalidReference(field: "subject", expectedResourceType: .patient)
        ])
    }
}
