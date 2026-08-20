//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

// ECG negative vectors stay colocated so the complete fail-closed evidence matrix is reviewable together.
// swiftlint:disable function_body_length type_body_length

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
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
    func sampledDataUsesPlainDecimalWithoutChangingTheSuppliedDouble() throws {
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

    @Test(
        "Incomplete or nonuniform ECG evidence fails closed",
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
                points: [
                    .init(timeSinceSampleStart: -0.002, millivolts: 0),
                    .init(timeSinceSampleStart: 0, millivolts: 1)
                ],
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
                points: [
                    validPoints[0],
                    validPoints[1],
                    .init(timeSinceSampleStart: 0.255, millivolts: 2)
                ],
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
                testDescription: "sampling frequency disagrees with offsets",
                reportedCount: 4,
                samplingFrequencyHertz: 256,
                points: validPoints,
                expected: .samplingFrequencyMismatch
            ),
            InvalidCase(
                testDescription: "nonfinite voltage",
                reportedCount: 2,
                samplingFrequencyHertz: 500,
                points: [
                    validPoints[0],
                    .init(timeSinceSampleStart: 0.252, millivolts: .nan)
                ],
                expected: .invalidLeadVoltage(index: 1)
            )
        ]
    )
    func rejectsInvalidEvidence(testCase: InvalidCase) {
        #expect(throws: GroveHealthKitFHIRError.invalidECGEvidence(testCase.expected)) {
            try HealthKitECGEvidenceValidator.validateWaveform(
                reportedCount: testCase.reportedCount,
                samplingFrequencyHertz: testCase.samplingFrequencyHertz,
                points: testCase.points
            )
        }
    }

    @Test
    func correlatedSymptomRetainsIdentityPeriodTypeSeverityAndSourceRevision() throws {
        let symptom = symptom(.dizziness, severity: .moderate)

        let validated = try HealthKitFHIRConverter.validatedSymptomEvidence([symptom], status: .present)
        let extensionValue = try HealthKitFHIRConverter.symptomExtension(try #require(validated.first))
        let children = try #require(extensionValue.extension)
        let source = try #require(children.first { $0.url.value?.url.absoluteString == "sourceIdentifier" })
        let period = try #require(children.first { $0.url.value?.url.absoluteString == "effectivePeriod" })
        let type = try #require(children.first { $0.url.value?.url.absoluteString == "symptomType" })
        let severity = try #require(children.first { $0.url.value?.url.absoluteString == "severity" })
        let sourceName = try #require(children.first { $0.url.value?.url.absoluteString == "sourceName" })
        let sourceBundleIdentifier = try #require(children.first {
            $0.url.value?.url.absoluteString == "sourceBundleIdentifier"
        })
        let majorVersion = try #require(children.first {
            $0.url.value?.url.absoluteString == "sourceOperatingSystemMajorVersion"
        })
        let minorVersion = try #require(children.first {
            $0.url.value?.url.absoluteString == "sourceOperatingSystemMinorVersion"
        })
        let patchVersion = try #require(children.first {
            $0.url.value?.url.absoluteString == "sourceOperatingSystemPatchVersion"
        })

        guard case .identifier(let sourceIdentifier) = source.value,
              case .period(let effectivePeriod) = period.value,
              case .code(let typeCode) = type.value,
              case .code(let severityCode) = severity.value,
              case .string(let sourceNameValue) = sourceName.value,
              case .string(let sourceBundleIdentifierValue) = sourceBundleIdentifier.value,
              case .integer(let majorVersionValue) = majorVersion.value,
              case .integer(let minorVersionValue) = minorVersion.value,
              case .integer(let patchVersionValue) = patchVersion.value else {
            Issue.record("Correlated symptom extension has the wrong typed child shape")
            return
        }
        #expect(extensionValue.url == GroveFHIRHealthKitCatalog.electrocardiogramCorrelatedSymptomExtension)
        #expect(sourceIdentifier.system == GroveFHIRCanonical.healthKitObjectIdentifier)
        #expect(sourceIdentifier.value?.value?.string == symptom.sourceUUID.uuidString.lowercased())
        #expect(effectivePeriod.start != nil)
        #expect(effectivePeriod.end != nil)
        #expect(typeCode.value?.string == HKCategoryTypeIdentifier.dizziness.rawValue)
        #expect(severityCode.value?.string == "moderate")
        #expect(sourceNameValue.value?.string == symptom.sourceName)
        #expect(sourceBundleIdentifierValue.value?.string == symptom.sourceBundleIdentifier)
        #expect(majorVersionValue.value?.integer == Int32(exactly: symptom.sourceOperatingSystemMajorVersion))
        #expect(minorVersionValue.value?.integer == Int32(exactly: symptom.sourceOperatingSystemMinorVersion))
        #expect(patchVersionValue.value?.integer == Int32(exactly: symptom.sourceOperatingSystemPatchVersion))

        let sourceVersion = children.first { $0.url.value?.url.absoluteString == "sourceVersion" }
        if let exactVersion = symptom.sourceVersion {
            guard case .string(let sourceVersionValue) = try #require(sourceVersion?.value) else {
                Issue.record("Expected sourceVersion as valueString")
                return
            }
            #expect(sourceVersionValue.value?.string == exactVersion)
        } else {
            #expect(sourceVersion == nil)
        }

        let sourceProductType = children.first { $0.url.value?.url.absoluteString == "sourceProductType" }
        if let exactProductType = symptom.sourceProductType {
            guard case .string(let sourceProductTypeValue) = try #require(sourceProductType?.value) else {
                Issue.record("Expected sourceProductType as valueString")
                return
            }
            #expect(sourceProductTypeValue.value?.string == exactProductType)
        } else {
            #expect(sourceProductType == nil)
        }
    }

    @Test
    func distinctSymptomsOfTheSameTypeRemainDistinct() throws {
        let first = symptom(.dizziness, severity: .mild)
        let secondOfSameType = symptom(.dizziness, severity: .severe)
        let validated = try HealthKitFHIRConverter.validatedSymptomEvidence(
            [secondOfSameType, first],
            status: .present
        )

        #expect(first.sourceUUID != secondOfSameType.sourceUUID)
        #expect(validated.map(\.sourceUUID) == [first.sourceUUID, secondOfSameType.sourceUUID].sorted {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        })
    }

    @Test
    func correlatedSymptomSourceRevisionRequiresExplicitDisclosureAuthorization() throws {
        try HealthKitFHIRConverter.validateSymptomSourceDisclosure(
            symptomCount: 0,
            policy: .omit
        )
        try HealthKitFHIRConverter.validateSymptomSourceDisclosure(
            symptomCount: 1,
            policy: .authorized
        )
        #expect(throws: GroveHealthKitFHIRError.invalidECGEvidence(
            .symptomSourceDisclosureNotAuthorized
        )) {
            try HealthKitFHIRConverter.validateSymptomSourceDisclosure(
                symptomCount: 1,
                policy: .omit
            )
        }
    }

    @Test
    func symptomStateAndUUIDUniquenessRulesFailClosed() throws {
        let first = symptom(.dizziness, severity: .mild)
        let unsupported = symptom(.sleepAnalysis, severity: .mild)

        #expect(throws: GroveHealthKitFHIRError.invalidECGEvidence(.symptomsRequired)) {
            try HealthKitFHIRConverter.validatedSymptomEvidence([], status: .present)
        }
        #expect(throws: GroveHealthKitFHIRError.invalidECGEvidence(.unexpectedSymptoms)) {
            try HealthKitFHIRConverter.validatedSymptomEvidence([first], status: .none)
        }
        #expect(throws: GroveHealthKitFHIRError.invalidECGEvidence(.duplicateSymptomSource(first.sourceUUID))) {
            try HealthKitFHIRConverter.validatedSymptomEvidence([first, first], status: .present)
        }
        #expect(throws: GroveHealthKitFHIRError.invalidECGEvidence(
            .unsupportedSymptomType(HKCategoryTypeIdentifier.sleepAnalysis.rawValue)
        )) {
            try HealthKitFHIRConverter.validatedSymptomEvidence([unsupported], status: .present)
        }
        #expect(throws: GroveHealthKitFHIRError.invalidECGEvidence(.tooManySymptoms(8))) {
            try HealthKitFHIRConverter.validatedSymptomEvidence(
                (0..<8).map { _ in symptom(.dizziness, severity: .mild) },
                status: .present
            )
        }
    }

    private func symptom(
        _ type: HKCategoryTypeIdentifier,
        severity: HKCategoryValueSeverity
    ) -> HealthKitECGSymptomEvidence {
        HealthKitECGSymptomEvidence(
            sourceUUID: UUID(),
            typeIdentifier: type.rawValue,
            severityValue: severity.rawValue,
            startDate: Date(timeIntervalSince1970: 1_787_148_600.123_456),
            endDate: Date(timeIntervalSince1970: 1_787_148_612.373_456),
            timeZone: TimeZone(secondsFromGMT: -7 * 60 * 60) ?? .gmt,
            sourceName: "Grove Health",
            sourceBundleIdentifier: "org.grovealliance.health",
            sourceVersion: "2.0.0",
            sourceProductType: "Watch6,4",
            sourceOperatingSystemMajorVersion: 12,
            sourceOperatingSystemMinorVersion: 0,
            sourceOperatingSystemPatchVersion: 1
        )
    }
}

#endif
