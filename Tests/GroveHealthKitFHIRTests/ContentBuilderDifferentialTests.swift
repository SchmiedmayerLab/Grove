//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// The content plans' builders against today's builders (oracle O4): every content-corpus record, and seeded random
/// records whose faults are drawn independently so many refused ones state several, builds to the same JSON tokens or
/// is refused with the same error by both; every corpus Observation and seeded random variant of one projects back to
/// the same sample, or is refused the same way, by both reverse projections.
///
/// Temporary: it reads the old content internals, so the old code's deletion (M6) deletes it; the goldens and the
/// content corpus then pin the plans' output.
@Suite
struct ContentBuilderDifferentialTests {
    /// The corpus splits into this many shards, which run in parallel.
    static let shards = 8

    /// How many random records at least must be refused for each refusal the draw reaches.
    private static let minimumRefusals = 5

    /// Every refusal the random draw reaches on this platform: watchOS has no clinical record or CDA document, so it
    /// reaches none of theirs.
    private static var drawnRefusals: Set<String> {
        #if os(watchOS)
        sampleRefusals
        #else
        sampleRefusals.union(clinicalRefusals)
        #endif
    }

    /// Every refusal the random draw reaches on every platform, by case (see `refusalCase(_:)`), in the order the
    /// checks run: an Observation's, an ECG's, then a recording document's.
    private static let sampleRefusals: Set<String> = [
        "HealthKitValueFailure.unsupportedMetadataValue(HealthKitMetadataField.timeZone)",
        "HealthKitValueFailure.effectivePeriodInvalid",
        "HealthKitValueFailure.shapeInvalid",
        "HealthKitValueFailure.unsupportedValue(#)",
        "HealthKitValueFailure.missingNormativeCode",
        "HealthKitValueFailure.unsupportedMetadataValue(HealthKitMetadataField.sexualActivityProtectionUsed)",
        "HealthKitValueFailure.requiredComponentMissing(component: \"systolic\")",
        "HealthKitValueFailure.requiredComponentMissing(component: \"diastolic\")",
        "HealthKitValueFailure.unsupportedMetadataValue(HealthKitMetadataField.heartRateMotionContext)",
        "HealthKitValueFailure.requiredMetadataMissing(HealthKitMetadataField.insulinDeliveryReason)",
        "HealthKitValueFailure.unsupportedMetadataValue(HealthKitMetadataField.insulinDeliveryReason)",
        "HealthKitValueFailure.requiredMetadataMissing(HealthKitMetadataField.menstrualCycleStart)",
        "HealthKitValueFailure.unsupportedMetadataValue(HealthKitMetadataField.menstrualCycleStart)",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.missingLeadVoltage(index: #))",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.invalidReportedVoltageCount(#))",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.voltageCountMismatch(reported: #, supplied: #))",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.insufficientVoltageMeasurements)",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.invalidOffset(index: #))",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.nonUniformOffset(index: #))",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.invalidSamplingFrequency)",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.samplingFrequencyMismatch)",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.invalidLeadVoltage(index: #))",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.unsupportedSymptomsStatus(#))",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.symptomsRequired)",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.unexpectedSymptoms)",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.unsupportedSymptomType(\"HKCategoryTypeIdentifierHeadache\"))",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.duplicateSymptomSource(<uuid>))",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.invalidSourcePeriod)",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.unsupportedClassification(#))",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.unsupportedAlgorithmVersion(#))",
        "HealthKitConversionError.ecgEvidence(HealthKitECGEvidenceFailure.invalidAverageHeartRate)",
        "HealthKitValueFailure.emptyRecordingSeries",
        "RecordingCSVWriter.WriterError.nonFiniteNumber(column: \"timestamp\")",
        "RecordingCSVWriter.WriterError.nonFiniteNumber(column: \"latitude\")"
    ]

    /// The refusals only a clinical record or CDA document reaches.
    private static let clinicalRefusals: Set<String> = [
        "HealthKitConversionError.clinicalRecord(HealthKitClinicalRecordFailure.empty)",
        "HealthKitConversionError.clinicalRecord(HealthKitClinicalRecordFailure.unsupportedRelease)",
        "HealthKitConversionError.clinicalRecord(HealthKitClinicalRecordFailure.undecodable)"
    ]

    /// The plans' reverse projection.
    private static let plannedProjection: ContentCorpusRecorder.Projection = { observation throws(HealthKitSampleProjectionError) in
        try HealthKitSampleProjection.sample(of: observation, syncIdentifier: nil)
    }

    /// Compares both builders on one shard of the corpus: every record a builder runs for, every reverse projection
    /// and every round trip. A record this platform cannot rebuild is skipped, as the corpus skips it; retractions and
    /// catalog projections run no builder.
    @Test(arguments: 0..<shards)
    func everyCorpusRecordBuildsAsToday(shard: Int) throws {
        var differences: [String] = []
        var eligible = 0
        var compared = 0
        let vectors = try ContentCorpusStore.vectors(in: ContentCorpusStore.checkedIn())
        for (index, vector) in vectors.enumerated() where index % Self.shards == shard {
            try autoreleasepool {
                guard let outcomes = try Self.outcomes(of: vector.input, eligible: &eligible) else {
                    return
                }
                compared += 1
                if let difference = Self.difference(outcomes.today, outcomes.planned) {
                    differences.append("\(vector.id): \(difference)")
                }
            }
        }
        #expect(compared > eligible * 3 / 4, "shard \(shard) compares only \(compared) of the \(eligible) vectors it can rebuild")
        #expect(differences.isEmpty, "\(differences.count) corpus vectors build differently: \(differences.prefix(10))")
    }

    @Test("Seeded random records, many with several faults, build as today's builders build them or refuse them alike")
    func seededRandomRecordsBuildAsToday() throws {
        var records = ContentBuilderRandomRecords(seed: 0x4F34_2D42_7569_6C64)
        var differences: [String] = []
        var refusals: [String: Int] = [:]
        var refusedWithSeveralFaults = 0
        var eligible = 0
        var compared = 0
        for index in 0..<ContentBuilderRandomRecords.count {
            try autoreleasepool {
                let (source, faults) = records.next()
                guard let outcomes = try Self.outcomes(of: .convert(source: source), eligible: &eligible) else {
                    return
                }
                compared += 1
                if let difference = Self.difference(outcomes.today, outcomes.planned) {
                    differences.append("record \(index) (\(try ContentCorpusStore.inputText(.convert(source: source)))): \(difference)")
                } else if case .threw(let error) = outcomes.today {
                    refusals[Self.refusalCase(error), default: 0] += 1
                    refusedWithSeveralFaults += faults > 1 ? 1 : 0
                }
            }
        }
        #expect(compared > eligible * 9 / 10, "only \(compared) of the \(eligible) random records this platform rebuilds reach a builder")
        #expect(refusedWithSeveralFaults > eligible / 6, "only \(refusedWithSeveralFaults) multi-fault refusals")
        let rare = Self.drawnRefusals.filter { refusals[$0, default: 0] < Self.minimumRefusals }
        #expect(rare.isEmpty, "refused fewer than \(Self.minimumRefusals) times: \(rare)")
        let unlisted = refusals.keys.filter { !Self.drawnRefusals.contains($0) }.sorted()
        #expect(unlisted.isEmpty, "refusals the draw is not known to reach: \(unlisted.map { "\($0) x\(refusals[$0, default: 0])" })")
        #expect(differences.isEmpty, "\(differences.count) random records build differently: \(differences.prefix(5))")
    }

    @Test("Seeded random variants of every corpus Observation project back as today's reverse projection does")
    func seededRandomObservationsProjectAsToday() throws {
        var generator = HealthKitEffectiveTimeTests.SeededGenerator(state: 0x4F34_2D52_6576_6572)
        let observations = try ContentCorpusStore.vectors(in: ContentCorpusStore.checkedIn()).compactMap { vector -> ContentCorpusJSON? in
            guard case .reverse(let observation) = vector.input else {
                return nil
            }
            return observation
        }
        try #require(!observations.isEmpty)
        var differences: [String] = []
        for index in 0..<1_500 {
            try autoreleasepool {
                let variant = try ContentBuilderRandomRecords.variant(of: observations[index % observations.count], using: &generator)
                let today = ContentCorpusRecorder.reverse(variant, projection: ContentBuilderPair.todaysProjection)
                let planned = ContentCorpusRecorder.reverse(variant, projection: Self.plannedProjection)
                if let difference = TokenDiff.firstDifference(expected: today, actual: planned) {
                    differences.append("variant \(index): \(difference)")
                }
            }
        }
        #expect(differences.isEmpty, "\(differences.count) Observations project differently: \(differences.prefix(5))")
    }

    /// Today's assembly converts each correlated symptom as its own graph before it builds the ECG's outputs, so a
    /// symptom value no code states is refused before an average heart rate no decimal states, by today's exporter
    /// and by both builders.
    @Test("An ECG's invalid symptom value is refused before its invalid average heart rate")
    func symptomValuePrecedesAverageHeartRate() throws {
        let chest = HKCategoryTypeIdentifier.chestTightnessOrPain.rawValue
        let present = HKElectrocardiogram.SymptomsStatus.present.rawValue
        let symptoms = ContentCorpusGrid.symptoms(present, [ContentCorpusElectrocardiogram.Symptom(type: chest, value: 9, ordinal: 0xE1)])
        let source = ContentCorpusGrid.electrocardiogramSource(ContentCorpusGrid.reading(symptoms) { $0.averageHeartRate = .nan })
        guard case .refused(let error) = try ContentCorpusRecorder.outcome(of: source) else {
            Issue.record("today's exporter converts the ECG")
            return
        }
        #expect(error == .invalidValue(.electrocardiogram, .unsupportedValue(9)))
        let outcomes = try #require(try ContentBuilderPair.outcomes(of: source))
        #expect(outcomes.today == .threw(String(reflecting: HealthKitValueFailure.unsupportedValue(9))))
        #expect(outcomes.planned == outcomes.today)
    }
}


extension ContentBuilderDifferentialTests {
    /// Both sides' outcomes for one corpus input, or `nil` when no builder or projection runs for it here. `eligible`
    /// counts the inputs this platform can rebuild; one it cannot (watchOS has no clinical record or CDA document) is
    /// skipped, as the corpus skips it, and compared on the other platforms.
    private static func outcomes(of input: ContentCorpusInput, eligible: inout Int) throws -> ContentBuilderPair.Outcomes? {
        do {
            let outcomes = try outcomes(of: input)
            eligible += 1
            return outcomes
        } catch ContentCorpusSamples.RebuildError.unavailableHere {
            return nil
        }
    }

    /// Both sides' outcomes for one corpus input, or `nil` when no builder or projection runs for it.
    private static func outcomes(of input: ContentCorpusInput) throws -> ContentBuilderPair.Outcomes? {
        switch input {
        case .convert(let source):
            return try ContentBuilderPair.outcomes(of: source)
        case .roundTrip(let source):
            let builders = try ContentBuilderPair.outcomes(of: source)
            let today = ContentBuilderOutcome {
                let roundTrip = try ContentCorpusRecorder.roundTrip(source, projection: ContentBuilderPair.todaysProjection)
                return .object(["record": builders?.today.tokens ?? .null, "roundTrip": roundTrip])
            }
            let planned = ContentBuilderOutcome {
                let roundTrip = try ContentCorpusRecorder.roundTrip(source, projection: plannedProjection)
                return .object(["record": builders?.planned.tokens ?? .null, "roundTrip": roundTrip])
            }
            return (today, planned)
        case .reverse(let observation):
            let decoded = try observation.decoded(as: Observation.self)
            let today = ContentCorpusRecorder.reverse(decoded, projection: ContentBuilderPair.todaysProjection)
            return (.built(today), .built(ContentCorpusRecorder.reverse(decoded, projection: plannedProjection)))
        case .retract, .catalog:
            return nil
        }
    }

    /// The case of a refusal: its error without module names, UUIDs and numbers.
    private static func refusalCase(_ error: String) -> String {
        error.replacingOccurrences(of: "Grove(HealthKitFHIR|FHIRContract)\\.", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}", with: "<uuid>", options: .regularExpression)
            .replacingOccurrences(of: "-?[0-9]+", with: "#", options: .regularExpression)
    }

    /// How two outcomes differ, or `nil` when they are equal.
    private static func difference(_ today: ContentBuilderOutcome, _ planned: ContentBuilderOutcome) -> String? {
        switch (today, planned) {
        case let (.built(expected), .built(actual)):
            TokenDiff.firstDifference(expected: expected, actual: actual)
        case let (.threw(expected), .threw(actual)):
            expected == actual ? nil : "today throws \(expected), the plans throw \(actual)"
        default:
            "today \(today), the plans \(planned)"
        }
    }
}

#endif
