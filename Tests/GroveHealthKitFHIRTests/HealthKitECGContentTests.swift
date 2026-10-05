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


/// The ECG content's checks of what a caller supplies: the voltages, the symptoms, and the facts the ECG's metadata
/// states.
@Suite
struct HealthKitECGContentTests {
    /// One voltage of the lead.
    struct VoltagePoint: Sendable {
        /// Its offset from the ECG's start, in seconds.
        let offset: TimeInterval
        /// Its value.
        let millivolts: Double
    }

    struct InvalidCase: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let reportedCount: Int
        let samplingFrequencyHertz: Double?
        let points: [VoltagePoint]
        let expected: HealthKitConversionError.ECGEvidenceFailure
    }

    private static let validPoints = [
        VoltagePoint(offset: 0.250, millivolts: 0),
        VoltagePoint(offset: 0.252, millivolts: 1),
        VoltagePoint(offset: 0.254, millivolts: -2),
        VoltagePoint(offset: 0.256, millivolts: 3)
    ]

    /// A stored ECG reporting `reportedCount` voltages sampled at `samplingFrequencyHertz`, supplying `points` and
    /// stating `metadata`.
    private static func record(
        reportedCount: Int,
        samplingFrequencyHertz: Double?,
        points: [VoltagePoint],
        metadata: [String: any Sendable] = [:]
    ) throws -> HealthKitECGRecord {
        let start = GoldenFixtures.sampleStart
        let facts = StoredSampleFixtures.SampleFacts(
            uuid: GoldenFixtures.uuid(0xC0),
            start: start,
            end: start.addingTimeInterval(30),
            device: nil,
            metadata: metadata.isEmpty ? nil : metadata,
            writer: .unattributed
        )
        let reading = StoredElectrocardiogram.Reading(
            classification: .sinusRhythm,
            symptomsStatus: .none,
            numberOfVoltageMeasurements: reportedCount,
            averageHeartRate: nil,
            samplingFrequency: samplingFrequencyHertz.map { HKQuantity(unit: .hertz(), doubleValue: $0) }
        )
        return HealthKitECGRecord(
            electrocardiogram: try StoredSampleFixtures.electrocardiogram(facts: facts, reading: reading),
            voltageMeasurements: try points.map { try StoredSampleFixtures.voltageMeasurement(offset: $0.offset, millivolts: $0.millivolts) }
        )
    }

    /// The waveform of a stored ECG reporting `reportedCount` voltages sampled at `samplingFrequencyHertz`, supplying
    /// `points`.
    private static func waveform(
        reportedCount: Int,
        samplingFrequencyHertz: Double?,
        points: [VoltagePoint]
    ) throws -> HealthKitECGContent.Waveform {
        let record = try record(reportedCount: reportedCount, samplingFrequencyHertz: samplingFrequencyHertz, points: points)
        return try HealthKitECGContent.Waveform(record, unit: .voltUnit(with: .milli))
    }

    @Test
    func completeUniformEnumerationRetainsFirstOffsetAndExactPeriod() throws {
        let waveform = try Self.waveform(reportedCount: 4, samplingFrequencyHertz: 500, points: Self.validPoints)

        #expect(waveform.firstOffset == Decimal(string: "0.250"))
        #expect(waveform.lastOffset == Decimal(string: "0.256"))
        #expect(waveform.period == 2)
        #expect(waveform.data == "0 1 -2 3")
    }

    @Test
    func sampledDataUsesPlainRoundTripDecimals() throws {
        let values = [0.123_456_789_012_345_66, 1e-16]
        let waveform = try Self.waveform(
            reportedCount: 2,
            samplingFrequencyHertz: 2,
            points: [VoltagePoint(offset: 0, millivolts: values[0]), VoltagePoint(offset: 0.5, millivolts: values[1])]
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
        try HealthKitECGContent.Waveform.requireCount(count, supplied: count)
        #expect(throws: HealthKitConversionError.ecgEvidence(.voltageCountMismatch(reported: count, supplied: Self.validPoints.count))) {
            try Self.waveform(reportedCount: count, samplingFrequencyHertz: 500, points: Self.validPoints)
        }
    }

    /// What the record path reads off an `HKElectrocardiogram`'s metadata beside its voltages.
    @Test("An ECG's evidence states the zone and algorithm version its metadata names, else UTC and none")
    func evidenceReadsTheMetadata() throws {
        let plan = HealthKitContentPlan[.electrocardiogram]
        let metadata: [String: any Sendable] = [
            HKMetadataKeyTimeZone: GoldenFixtures.timeZone,
            HKMetadataKeyAppleECGAlgorithmVersion: HKAppleECGAlgorithmVersion.version2.rawValue
        ]
        let stated = try Self.record(reportedCount: 4, samplingFrequencyHertz: 500, points: Self.validPoints, metadata: metadata)
        let evidence = try plan.ecgEvidence(stated)
        #expect(evidence.electrocardiogram === stated.electrocardiogram)
        #expect(evidence.zone.identifier == GoldenFixtures.timeZone)
        #expect(evidence.algorithmVersion == HKAppleECGAlgorithmVersion.version2.rawValue)
        #expect(evidence.waveform.data == "0 1 -2 3")
        let bare = try plan.ecgEvidence(try Self.record(reportedCount: 4, samplingFrequencyHertz: 500, points: Self.validPoints))
        #expect(bare.zone.secondsFromGMT(for: GoldenFixtures.sampleStart) == 0)
        #expect(bare.algorithmVersion == nil)
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
        let record = try GoldenCase.electrocardiogramRecord(uuid: 0xC1, symptoms: [], classification: classification)
        let conversion = try ExporterFixtures.export(ExporterFixtures.electrocardiogram(record, symptoms: []))
        let observations = conversion.primary.graph.bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) } ?? []
        #expect(observations.compactMap(\.interpretation).map { $0.first?.coding?.map { $0.code?.value?.string } } == [[code]])
    }

    /// One record states one entry method: the ECG's own metadata marks its waveform and its average heart rate alike.
    @Test("A user-entered ECG states manual entry on the waveform and on its average heart rate")
    func userEnteredECGMarksEveryOutput() throws {
        let record = try GoldenCase.electrocardiogramRecord(uuid: 0xC2, symptoms: [])
        let metadata = (record.electrocardiogram.metadata ?? [:]).merging([HKMetadataKeyWasUserEntered: true]) { _, new in new }
        let ecg = try StoredSampleFixtures.withMetadata(record.electrocardiogram, metadata)
        let conversion = try ExporterFixtures.export(.electrocardiogram(ecg, voltages: record.voltageMeasurements, symptoms: []))
        let observations = conversion.primary.graph.bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) } ?? []
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
                points: [VoltagePoint(offset: -0.002, millivolts: 0), validPoints[0]],
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
                points: [validPoints[0], validPoints[1], VoltagePoint(offset: 0.255, millivolts: 2)],
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
                points: [validPoints[0], VoltagePoint(offset: 0.252, millivolts: .nan)],
                expected: .invalidLeadVoltage(index: 1)
            )
        ]
    )
    func rejectsInvalidEvidence(testCase: InvalidCase) {
        #expect(throws: HealthKitConversionError.ecgEvidence(testCase.expected)) {
            try Self.waveform(
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
        let validated = try HealthKitECGContent.validatedSymptoms(
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
            try HealthKitECGContent.validatedSymptoms([], status: .present)
        }
        #expect(throws: HealthKitConversionError.ecgEvidence(.unexpectedSymptoms)) {
            try HealthKitECGContent.validatedSymptoms([first], status: .none)
        }
        #expect(throws: HealthKitConversionError.ecgEvidence(.duplicateSymptomSource(first.uuid))) {
            try HealthKitECGContent.validatedSymptoms([first, first], status: .present)
        }
        #expect(throws: HealthKitConversionError.ecgEvidence(
            .unsupportedSymptomType(HKCategoryTypeIdentifier.sleepAnalysis.rawValue)
        )) {
            try HealthKitECGContent.validatedSymptoms([unsupported], status: .present)
        }
        let repeatedTypeSamples = (0..<8).map { _ in symptom(.dizziness) }
        let repeatedTypeValidated = try HealthKitECGContent.validatedSymptoms(
            repeatedTypeSamples,
            status: .present
        )
        #expect(repeatedTypeValidated.count == repeatedTypeSamples.count)
    }

    @Test("The symptom check admits exactly the claim's symptom source types among every category type")
    func correlatedSymptomTypesAreTheClaims() throws {
        let start = GoldenFixtures.sampleStart
        var admitted: Set<HealthKitSourceType> = []
        for type in HealthKitSourceType.allCases {
            guard let categoryType = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: type.rawValue)) else {
                continue
            }
            let facts = StoredSampleFixtures.SampleFacts(uuid: UUID(), start: start, end: start, device: nil, metadata: nil, writer: .unattributed)
            let sample = try StoredSampleFixtures.categorySample(categoryType, value: 0, facts: facts)
            if (try? HealthKitECGContent.validatedSymptoms([sample], status: .present)) != nil {
                admitted.insert(type)
            }
        }
        #expect(!admitted.isEmpty)
        #expect(admitted == HealthKitElectrocardiogramClaim.correlatedSymptomSourceTypes)
    }

    @Test("A symptom's warnings stay with its own graph and reach the set")
    func symptomWarningsReachTheSet() throws {
        let start = Date(timeIntervalSince1970: 1_787_148_600)
        let facts = StoredSampleFixtures.SampleFacts(
            uuid: UUID(),
            start: start,
            end: start.addingTimeInterval(30),
            device: nil,
            metadata: [HKMetadataKeyTimeZone: "America/Los_Angeles"],
            writer: .unattributed
        )
        let reading = StoredElectrocardiogram.Reading(
            classification: .sinusRhythm,
            symptomsStatus: .present,
            numberOfVoltageMeasurements: Self.validPoints.count,
            averageHeartRate: nil,
            samplingFrequency: HKQuantity(unit: .hertz(), doubleValue: 500)
        )
        let record = HealthKitFHIRExporter.Record.electrocardiogram(
            try StoredSampleFixtures.electrocardiogram(facts: facts, reading: reading),
            voltages: try Self.validPoints.map { point in
                try StoredSampleFixtures.voltageMeasurement(offset: point.offset, millivolts: point.millivolts)
            },
            symptoms: [symptom(.dizziness)]
        )
        let set = try ExporterFixtures.export(record)
        let symptomWarnings = [
            ExchangeGraphRule.mobileOmissionSourceOffset.diagnostic(at: "Observation.effectivePeriod.start"),
            ExchangeGraphRule.mobileOmissionSourceOffset.diagnostic(at: "Observation.effectivePeriod.end")
        ]
        #expect(set.primary.warnings.isEmpty)
        #expect(set.companions.map(\.warnings) == [symptomWarnings])
        #expect(set.warnings == symptomWarnings)
    }

    /// Each symptom is a source record of its own, so it converts under an event of its own beside the ECG's.
    @Test("Each correlated symptom converts under its own event")
    func symptomEventsAreTheirOwn() throws {
        let chest = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xD1))
        let fatigue = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xD2), type: .fatigue)
        let pair = try GoldenCase.electrocardiogramRecord(uuid: 0xD0, symptoms: [chest, fatigue])
        let set = try ExporterFixtures.export(ExporterFixtures.electrocardiogram(pair, symptoms: [chest, fatigue]))
        #expect(set.companions.count == 2)
        let events = set.all.map(\.identifiers.event)
        #expect(Set(events).count == events.count)
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
        let dateTime = try HealthKitEffectiveTime.exactDateTime(instant, offset: 0.25, zone: zone)
        let decoded = try JSONDecoder().decode(DateTime.self, from: JSONEncoder().encode(dateTime))
        #expect(try decoded.asNSDate() == instant.addingTimeInterval(0.25))
    }
}

#endif
