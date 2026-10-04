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
        let base = context.event
        let otherRepository = try BusinessIdentifier(system: base.repositoryScope.system, value: "secondary")
        func variant(
            subject: Subject = base.subject,
            repositoryScope: BusinessIdentifier = base.repositoryScope
        ) -> HealthKitConversionContext {
            HealthKitConversionContext(event: ExchangeEventContext(
                subject: subject,
                event: base.event,
                identityScope: base.identityScope,
                repositoryScope: repositoryScope,
                application: base.application,
                host: base.host,
                conversionInstant: base.conversionInstant
            ))
        }
        let expected = HealthKitConversionError.ecgEvidence(.mismatchedSymptomContext)

        #expect(throws: expected) {
            try HealthKitConverter.validateSymptomConversionContext(
                variant(subject: .logical(.test(.patient, "other"))),
                expectedContext: context
            )
        }
        #expect(throws: expected) {
            try HealthKitConverter.validateSymptomConversionContext(
                variant(repositoryScope: otherRepository),
                expectedContext: context
            )
        }

        try HealthKitConverter.validateSymptomConversionContext(variant(), expectedContext: context)
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
        #expect(throws: HealthKitConversionError.ecgEvidence(.voltageCountMismatch(
            reported: count,
            supplied: count - 1
        ))) {
            try HealthKitECGEvidenceValidator.validateCount(reported: count, supplied: count - 1)
        }
    }

    /// The facts the public record path reads off an `HKElectrocardiogram` beside its voltages, field by field.
    @Test("An ECG's source evidence states the sample's own classification, symptoms, rate, algorithm and zone")
    func sourceEvidenceReadsTheSample() throws {
        let start = GoldenFixtures.sampleStart
        let shape = StoredSampleFixtures.SeriesShape(
            uuid: GoldenFixtures.uuid(0xC0),
            start: start,
            end: start.addingTimeInterval(30),
            device: GoldenFixtures.watch,
            metadata: [HKMetadataKeyTimeZone: GoldenFixtures.timeZone, HKMetadataKeyAppleECGAlgorithmVersion: HKAppleECGAlgorithmVersion.version2.rawValue],
            writer: GoldenFixtures.foreignWriter
        )
        let ecg = try StoredSampleFixtures.electrocardiogram(
            shape: shape,
            reading: (privateClassification: 4, classification: .atrialFibrillation),
            symptomsStatus: .present,
            averageHeartRate: HKQuantity(unit: GoldenFixtures.beatsPerMinute, doubleValue: 112)
        )
        let evidence = try HealthKitConverter.ecgSourceEvidence(ecg)
        #expect(evidence.sourceTypeIdentifier == HealthKitContract.electrocardiogramSourceTypeIdentifier)
        #expect(evidence.startDate == start)
        #expect(evidence.endDate == start.addingTimeInterval(30))
        #expect(evidence.timeZone.identifier == GoldenFixtures.timeZone)
        #expect(evidence.classification == .atrialFibrillation)
        #expect(evidence.symptomsStatus == .present)
        #expect(evidence.averageHeartRate == 112)
        #expect(evidence.algorithmVersion == HKAppleECGAlgorithmVersion.version2.rawValue)
        // Unset voltages report no measurements and no sampling frequency.
        #expect(evidence.numberOfVoltageMeasurements == 0)
        #expect(evidence.samplingFrequency == nil)
    }

    /// Every HealthKit classification states its code of the guide's closed code system
    /// (healthkit `terminology.fsh`, `HealthKitECGClassificationCS`).
    @Test(arguments: [
        (HKElectrocardiogram.Classification.notSet, "notSet"),
        (.sinusRhythm, "sinusRhythm"),
        (.atrialFibrillation, "atrialFibrillation"),
        (.inconclusiveLowHeartRate, "inconclusiveLowHeartRate"),
        (.inconclusiveHighHeartRate, "inconclusiveHighHeartRate"),
        (.inconclusivePoorReading, "inconclusivePoorReading"),
        (.inconclusiveOther, "inconclusiveOther"),
        (.unrecognized, "unrecognized")
    ])
    func classificationsStateTheGuideCodes(_ classification: HKElectrocardiogram.Classification, _ code: String) throws {
        let (_, evidence) = try GoldenCase.electrocardiogramEvidence(uuid: 0xC1, symptomsPresent: false)
        let source = evidence.source
        let observation = try HealthKitConverter.ecgObservation(input: HealthKitECGObservationInput(
            source: HealthKitECGSourceEvidence(
                sourceTypeIdentifier: source.sourceTypeIdentifier,
                startDate: source.startDate,
                endDate: source.endDate,
                timeZone: source.timeZone,
                classification: classification,
                symptomsStatus: source.symptomsStatus,
                numberOfVoltageMeasurements: source.numberOfVoltageMeasurements,
                averageHeartRate: source.averageHeartRate,
                samplingFrequency: source.samplingFrequency,
                algorithmVersion: source.algorithmVersion
            ),
            waveform: evidence.waveform,
            symptomOutputIdentifiers: []
        ))
        #expect(observation.interpretation?.first?.coding?.map { $0.code?.value?.string } == [code])
    }

    /// One record states one entry method: the ECG's own metadata marks its waveform and its average heart rate alike.
    @Test("A user-entered ECG states manual entry on the waveform and on its average heart rate")
    func userEnteredECGMarksEveryOutput() throws {
        let start = GoldenFixtures.sampleStart
        let ecg = try StoredSampleFixtures.seriesSample(
            HKElectrocardiogram.self,
            sampleType: HKObjectType.electrocardiogramType(),
            shape: StoredSampleFixtures.SeriesShape(
                uuid: GoldenFixtures.uuid(0xC2),
                start: start,
                end: start.addingTimeInterval(30),
                device: GoldenFixtures.watch,
                metadata: [HKMetadataKeyTimeZone: GoldenFixtures.timeZone, HKMetadataKeyWasUserEntered: true],
                writer: GoldenFixtures.foreignWriter
            )
        )
        let (_, evidence) = try GoldenCase.electrocardiogramEvidence(uuid: 0xC2, symptomsPresent: false)
        let conversion = try HealthKitConverter.convertECG(ecg, evidence: evidence, symptoms: [], context: HealthKitConversionContext(), symptomContexts: [])
        let observations = conversion.bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) } ?? []
        #expect(observations.count == 2)
        for observation in observations {
            let methods = observation.extension?.filter { $0.url == Canonicals.recordingMethod } ?? []
            #expect(methods.count == 1, "\(observation.code.coding?.first?.code?.value?.string ?? "") states no manual entry")
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
        #expect(throws: HealthKitConversionError.ecgEvidence(testCase.expected)) {
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

        #expect(throws: HealthKitConversionError.ecgEvidence(.symptomsRequired)) {
            try HealthKitConverter.validatedSymptomSamples([], status: .present)
        }
        #expect(throws: HealthKitConversionError.ecgEvidence(.unexpectedSymptoms)) {
            try HealthKitConverter.validatedSymptomSamples([first], status: .none)
        }
        #expect(throws: HealthKitConversionError.ecgEvidence(.duplicateSymptomSource(first.uuid))) {
            try HealthKitConverter.validatedSymptomSamples([first, first], status: .present)
        }
        #expect(throws: HealthKitConversionError.ecgEvidence(
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

    @Test("A symptom's warnings stay with its own graph and reach the set")
    func symptomWarningsReachTheSet() throws {
        let start = Date(timeIntervalSince1970: 1_787_148_600)
        let source = HealthKitECGSourceEvidence(
            sourceTypeIdentifier: HealthKitContract.electrocardiogramSourceTypeIdentifier,
            startDate: start,
            endDate: start.addingTimeInterval(30),
            timeZone: try #require(TimeZone(identifier: "America/Los_Angeles")),
            classification: .sinusRhythm,
            symptomsStatus: .present,
            numberOfVoltageMeasurements: Self.validPoints.count,
            averageHeartRate: nil,
            samplingFrequency: 500,
            algorithmVersion: nil
        )
        let waveform = try HealthKitECGEvidenceValidator.validateWaveform(
            reportedCount: Self.validPoints.count,
            samplingFrequencyHertz: 500,
            points: Self.validPoints
        )
        // HKElectrocardiogram has no public initializer; this sample stands in for its envelope only.
        let envelope = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 72),
            start: start,
            end: start,
            metadata: [HKMetadataKeyTimeZone: "America/Los_Angeles"]
        )
        let set = try HealthKitConverter.convertECG(
            envelope,
            evidence: HealthKitECGEvidence(source: source, waveform: waveform),
            symptoms: [symptom(.dizziness)],
            context: HealthKitConversionContext(),
            symptomContexts: [HealthKitConversionContext(conversionInstant: ExchangeEventContext.testInstant.addingTimeInterval(1))]
        )
        let symptomWarnings: [HealthKitConversionWarning] = [
            .sourceOffsetUnavailable(field: "Observation.effectivePeriod.start"),
            .sourceOffsetUnavailable(field: "Observation.effectivePeriod.end")
        ]
        #expect(set.primary.warnings.isEmpty)
        #expect(set.companions.map(\.warnings) == [symptomWarnings])
        #expect(set.warnings == symptomWarnings)
    }

    @Test("The context API refuses a symptom-context count other than the symptoms' before it validates the symptoms")
    func symptomContextCountIsCheckedBeforeTheSymptoms() throws {
        // Symptoms the evidence says are absent: the count mismatch is still the fault reported.
        let (ecg, evidence) = try GoldenCase.electrocardiogramEvidence(uuid: 0x60, symptomsPresent: false)
        #expect(throws: HealthKitConversionError.ecgEvidence(.symptomContextCountMismatch(symptoms: 1, contexts: 0))) {
            try HealthKitConverter.convertECG(
                ecg,
                evidence: evidence,
                symptoms: [symptom(.dizziness)],
                context: HealthKitConversionContext(),
                symptomContexts: []
            )
        }
    }

    private func symptom(_ type: HKCategoryTypeIdentifier) -> HKCategorySample {
        HKCategorySample(
            type: HKCategoryType(type),
            value: HKCategoryValueSeverity.moderate.rawValue,
            start: Date(timeIntervalSince1970: 1_787_148_600),
            end: Date(timeIntervalSince1970: 1_787_148_612)
        )
    }

    @Test(arguments: [
        ("America/Los_Angeles", "2025-11-02T09:05:00Z"),
        ("Europe/Berlin", "2025-10-26T01:30:00Z")
    ])
    func ecgTimestampsInTheRepeatedDSTHourKeepTheirInstant(_ zoneName: String, _ instantText: String) throws {
        let zone = try #require(TimeZone(identifier: zoneName))
        let instant = try #require(ISO8601DateFormatter().date(from: instantText))
        let dateTime = try HealthKitConverter.exactHealthKitDateTime(instant, offsetSeconds: 0.25, timeZone: zone)
        let decoded = try JSONDecoder().decode(DateTime.self, from: JSONEncoder().encode(dateTime))
        #expect(try decoded.asNSDate() == instant.addingTimeInterval(0.25))
    }
}

#endif
