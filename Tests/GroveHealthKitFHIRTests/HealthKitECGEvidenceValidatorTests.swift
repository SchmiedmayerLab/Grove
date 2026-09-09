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
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


@Suite
struct HealthKitECGEvidenceValidatorTests {
    struct InvalidCase: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let reportedCount: Int
        let samplingFrequencyHertz: Double?
        let points: [HealthKitECGVoltagePoint]
        let expected: HealthKitECGEvidenceFailure
    }

    private static let validPoints = [
        HealthKitECGVoltagePoint(timeSinceSampleStart: 0.250, millivolts: 0),
        HealthKitECGVoltagePoint(timeSinceSampleStart: 0.252, millivolts: 1),
        HealthKitECGVoltagePoint(timeSinceSampleStart: 0.254, millivolts: -2),
        HealthKitECGVoltagePoint(timeSinceSampleStart: 0.256, millivolts: 3)
    ]

    @Test("ECG symptom companions must share the exact patient and repository scope")
    func symptomCompanionScopeValidation() throws {
        let context = HealthKitConversionContext(subject: .testPatient)
        let otherSubject = Reference.testLogicalReference(resourceType: .patient, value: "other")
        let otherSubjectIdentity = try BusinessIdentifier(
            system: context.subjectIdentity.system,
            value: "other"
        )
        let otherRepository = try BusinessIdentifier(
            system: context.repositoryScope.system,
            value: "secondary"
        )
        let expected = HealthKitConversionError.invalidECGEvidence(.mismatchedSymptomContext)

        #expect(throws: expected) {
            try HealthKitConverter.validateSymptomConversionContext(
                subject: otherSubject,
                subjectIdentity: context.subjectIdentity,
                repositoryScope: context.repositoryScope,
                expectedContext: context
            )
        }
        #expect(throws: expected) {
            try HealthKitConverter.validateSymptomConversionContext(
                subject: context.subject,
                subjectIdentity: otherSubjectIdentity,
                repositoryScope: context.repositoryScope,
                expectedContext: context
            )
        }
        #expect(throws: expected) {
            try HealthKitConverter.validateSymptomConversionContext(
                subject: context.subject,
                subjectIdentity: context.subjectIdentity,
                repositoryScope: otherRepository,
                expectedContext: context
            )
        }

        try HealthKitConverter.validateSymptomConversionContext(
            subject: context.subject,
            subjectIdentity: context.subjectIdentity,
            repositoryScope: context.repositoryScope,
            expectedContext: context
        )
    }

    @Test
    func completeUniformEnumerationRetainsFirstOffsetAndExactPeriod() throws {
        let waveform = try HealthKitECGEvidenceValidator.validateWaveform(
            reportedCount: 4,
            samplingFrequencyHertz: 500,
            points: Self.validPoints
        )

        #expect(waveform.firstOffsetSeconds == Decimal(string: "0.250"))
        #expect(waveform.lastOffsetSeconds == Decimal(string: "0.256"))
        #expect(waveform.periodMilliseconds == 2)
        #expect(waveform.data == "0 1 -2 3")
    }

    @Test
    func sampledDataUsesPlainRoundTripDecimals() throws {
        let values = [0.123_456_789_012_345_66, 1e-16]
        let waveform = try HealthKitECGEvidenceValidator.validateWaveform(
            reportedCount: 2,
            samplingFrequencyHertz: 2,
            points: [
                .init(timeSinceSampleStart: 0, millivolts: values[0]),
                .init(timeSinceSampleStart: 0.5, millivolts: values[1])
            ]
        )
        let encoded = waveform.data.split(separator: " ")

        #expect(encoded.count == values.count)
        #expect(encoded.allSatisfy { !$0.contains("e") && !$0.contains("E") })
        #expect(Double(encoded[0])?.bitPattern == values[0].bitPattern)
        #expect(Double(encoded[1])?.bitPattern == values[1].bitPattern)
    }

    @Test("Reported ECG frame counts are not constrained by a removed wire integer field")
    func reportedCountHasNoArtificialInt32Limit() throws {
        let count = Int(Int32.max) + 1
        try HealthKitECGEvidenceValidator.validateCount(reported: count, supplied: count)
        #expect(throws: HealthKitConversionError.invalidECGEvidence(.voltageCountMismatch(
            reported: count,
            supplied: count - 1
        ))) {
            try HealthKitECGEvidenceValidator.validateCount(reported: count, supplied: count - 1)
        }
    }

    @Test(
        "Incomplete, contradictory, or nonuniform ECG evidence fails closed",
        arguments: [
            InvalidCase(
                testDescription: "reported count is not positive",
                reportedCount: 0,
                samplingFrequencyHertz: 500,
                points: [],
                expected: .invalidReportedVoltageCount(0)
            ),
            InvalidCase(
                testDescription: "supplied count differs from HealthKit count",
                reportedCount: 5,
                samplingFrequencyHertz: 500,
                points: validPoints,
                expected: .voltageCountMismatch(reported: 5, supplied: 4)
            ),
            InvalidCase(
                testDescription: "one point cannot prove a period",
                reportedCount: 1,
                samplingFrequencyHertz: 500,
                points: [validPoints[0]],
                expected: .insufficientVoltageMeasurements
            ),
            InvalidCase(
                testDescription: "negative first offset",
                reportedCount: 2,
                samplingFrequencyHertz: 500,
                points: [.init(timeSinceSampleStart: -0.002, millivolts: 0), validPoints[0]],
                expected: .invalidOffset(index: 0)
            ),
            InvalidCase(
                testDescription: "duplicate offset",
                reportedCount: 2,
                samplingFrequencyHertz: 500,
                points: [validPoints[0], validPoints[0]],
                expected: .invalidOffset(index: 1)
            ),
            InvalidCase(
                testDescription: "out-of-order offset",
                reportedCount: 2,
                samplingFrequencyHertz: 500,
                points: [validPoints[1], validPoints[0]],
                expected: .invalidOffset(index: 1)
            ),
            InvalidCase(
                testDescription: "nonuniform third offset",
                reportedCount: 3,
                samplingFrequencyHertz: nil,
                points: [validPoints[0], validPoints[1], .init(timeSinceSampleStart: 0.255, millivolts: 2)],
                expected: .nonUniformOffset(index: 2)
            ),
            InvalidCase(
                testDescription: "sampling frequency is invalid",
                reportedCount: 4,
                samplingFrequencyHertz: 0,
                points: validPoints,
                expected: .invalidSamplingFrequency
            ),
            InvalidCase(
                testDescription: "sampling frequency disagrees with SampledData period",
                reportedCount: 4,
                samplingFrequencyHertz: 256,
                points: validPoints,
                expected: .samplingFrequencyMismatch
            ),
            InvalidCase(
                testDescription: "nonfinite voltage",
                reportedCount: 2,
                samplingFrequencyHertz: 500,
                points: [validPoints[0], .init(timeSinceSampleStart: 0.252, millivolts: .nan)],
                expected: .invalidLeadVoltage(index: 1)
            )
        ]
    )
    func rejectsInvalidEvidence(testCase: InvalidCase) {
        #expect(throws: HealthKitConversionError.invalidECGEvidence(testCase.expected)) {
            try HealthKitECGEvidenceValidator.validateWaveform(
                reportedCount: testCase.reportedCount,
                samplingFrequencyHertz: testCase.samplingFrequencyHertz,
                points: testCase.points
            )
        }
    }

    @Test
    func correlatedSymptomRelationshipPreservesDistinctSourceSamples() throws {
        let first = symptom(.dizziness)
        let second = symptom(.dizziness)
        let validated = try HealthKitConverter.validatedSymptomSamples(
            [second, first],
            status: .present
        )

        #expect(first.uuid != second.uuid)
        #expect(validated.map(\.uuid) == [first.uuid, second.uuid].sorted {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        })
    }

    @Test
    func symptomRelationshipRulesFailClosed() throws {
        let first = symptom(.dizziness)
        let unsupported = symptom(.sleepAnalysis)

        #expect(throws: HealthKitConversionError.invalidECGEvidence(.symptomsRequired)) {
            try HealthKitConverter.validatedSymptomSamples([], status: .present)
        }
        #expect(throws: HealthKitConversionError.invalidECGEvidence(.unexpectedSymptoms)) {
            try HealthKitConverter.validatedSymptomSamples([first], status: .none)
        }
        #expect(throws: HealthKitConversionError.invalidECGEvidence(.duplicateSymptomSource(first.uuid))) {
            try HealthKitConverter.validatedSymptomSamples([first, first], status: .present)
        }
        #expect(throws: HealthKitConversionError.invalidECGEvidence(
            .unsupportedSymptomType(HKCategoryTypeIdentifier.sleepAnalysis.rawValue)
        )) {
            try HealthKitConverter.validatedSymptomSamples([unsupported], status: .present)
        }
        let repeatedTypeSamples = (0..<8).map { _ in symptom(.dizziness) }
        let repeatedTypeValidated = try HealthKitConverter.validatedSymptomSamples(
            repeatedTypeSamples,
            status: .present
        )
        #expect(repeatedTypeValidated.count == repeatedTypeSamples.count)
    }

    private func symptom(_ type: HKCategoryTypeIdentifier) -> HKCategorySample {
        HKCategorySample(
            type: HKCategoryType(type),
            value: HKCategoryValueSeverity.moderate.rawValue,
            start: Date(timeIntervalSince1970: 1_787_148_600),
            end: Date(timeIntervalSince1970: 1_787_148_612)
        )
    }
}

#endif
