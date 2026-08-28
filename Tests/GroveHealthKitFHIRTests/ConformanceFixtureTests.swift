//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

// The conformance corpus keeps all emitted profiles and their exact source vectors in one auditable suite.
// swiftlint:disable function_body_length type_body_length

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// Writes one resource per shape the converter produces, for the HL7 validator to check
/// against the profiles the guides publish.
///
/// The unit tests check the converter and the IG Publisher checks the guides' hand-written
/// examples; neither crosses the gap between them, which is how a release once shipped
/// observations that declared a profile they violated. `Scripts/validate-fhir-conformance.sh`
/// runs this and then validates what it wrote.
@Suite
struct ConformanceFixtureTests {
    private enum FixtureError: Error {
        case invalidInstant(String)
        case unexpectedEffective(String)
        case unexpectedResult(String)
    }

    private struct SourceInventory: Codable {
        struct Row: Codable {
            let sourceTypeIdentifier: String
            let title: String
            let measurementIDs: [String]
            let profiles: [String]
            let implementationStatus: String
            let requirement: String?
        }

        let schemaVersion: Int
        let rows: [Row]
    }

    /// Where the fixtures land, derived from this file's own path: `xcodebuild` does not
    /// forward the shell's environment into the test process.
    static var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/conformance-fixtures/healthkit")
    }

    static var inventoryURL: URL {
        fixtureDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("grove-fhir-inventories/healthkit-source-inventory.json")
    }

    private static let subject = Reference(reference: "Patient/example")
    private static let sourceTimeZoneIdentifier = "America/Los_Angeles"

    private static var device: HKDevice {
        HKDevice(
            name: "Apple Watch",
            manufacturer: "Apple Inc.",
            model: "Watch7,12",
            hardwareVersion: "Watch7,12",
            firmwareVersion: "1.0",
            softwareVersion: "26.2.1",
            localIdentifier: "6C4B1D1E-0000-4000-8000-000000000001",
            udiDeviceIdentifier: nil
        )
    }

    @Test
    func writeConformanceFixtures() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]

        func instant(_ value: String) throws -> Date {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw FixtureError.invalidInstant(value)
            }
            return date
        }

        func vector(_ id: String) throws -> MobileSemanticVectorFixture {
            try #require(MobileSemanticVectorFixtures.all.first { $0.id == id })
        }

        func dates(
            _ effective: MobileSemanticVectorFixture.Effective
        ) throws -> (start: Date, end: Date) {
            switch effective {
            case .dateTime(let value):
                let start = try instant(value)
                return (start, start.addingTimeInterval(60))
            case let .period(start, end):
                return (try instant(start), try instant(end))
            }
        }

        func dates(
            _ fixture: MobileSemanticVectorFixture
        ) throws -> (start: Date, end: Date) {
            try dates(fixture.effective)
        }

        func normalizedQuantity(_ fixture: MobileSemanticVectorFixture) throws -> Double {
            guard case .quantity(let value) = fixture.result else {
                throw FixtureError.unexpectedResult(fixture.id)
            }
            return value
        }

        let contextTime = try instant("2026-08-20T12:00:00-07:00")

        let context = HealthKitConversionContext(
            subject: Self.subject,
            converter: HealthKitApplication(
                name: "Grove Conformance Fixture",
                bundleIdentifier: "org.grovealliance.conformance-fixture",
                version: "0.5.0"
            ),
            graphIdentifierSystem: "https://grovealliance.org/fhir/testing/identifiers/conformance-graph",
            converterWasGateway: true,
            conversionInstant: contextTime
        )
        let converter = HealthKitConverter()
        var fixtures: [String: ModelsR4.Bundle] = [:]
        func quantity(
            _ type: HKQuantityTypeIdentifier,
            _ unit: HKUnit,
            _ value: Double,
            effective: MobileSemanticVectorFixture.Effective,
            metadata: [String: Any] = [:]
        ) throws -> HKQuantitySample {
            let period = try dates(effective)
            var sourceMetadata = metadata
            sourceMetadata[HKMetadataKeyTimeZone] = Self.sourceTimeZoneIdentifier
            return HKQuantitySample(
                type: HKQuantityType(type),
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: period.start,
                end: period.end,
                device: Self.device,
                metadata: sourceMetadata
            )
        }
        func add(_ name: String, _ sample: HKSample) throws {
            fixtures[name] = try converter.convert(sample, context: context).bundle
        }

        func addQuantityVector(
            _ id: String,
            type: HKQuantityTypeIdentifier,
            unit: HKUnit,
            sourceValue: (Double) -> Double = { $0 },
            metadata: [String: Any] = [:]
        ) throws {
            let fixture = try vector(id)
            try add(id, quantity(
                type,
                unit,
                sourceValue(try normalizedQuantity(fixture)),
                effective: fixture.effective,
                metadata: metadata
            ))
        }

        try addQuantityVector("active-energy", type: .activeEnergyBurned, unit: .kilocalorie())
        try addQuantityVector("basal-body-temperature", type: .basalBodyTemperature, unit: .degreeCelsius())
        try addQuantityVector("basal-energy", type: .basalEnergyBurned, unit: .kilocalorie())
        try addQuantityVector(
            "blood-glucose-unspecified-specimen",
            type: .bloodGlucose,
            unit: .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        )
        try addQuantityVector(
            "body-fat-percentage",
            type: .bodyFatPercentage,
            unit: .percent(),
            sourceValue: { $0 / 100 }
        )
        try addQuantityVector("body-height", type: .height, unit: .meterUnit(with: .centi))
        try addQuantityVector("dietary-energy", type: .dietaryEnergyConsumed, unit: .kilocalorie())
        try addQuantityVector(
            "resting-heart-rate",
            type: .restingHeartRate,
            unit: .count().unitDivided(by: .minute())
        )
        try add("body-mass-index", quantity(
            .bodyMassIndex,
            .count(),
            22.1,
            effective: .dateTime("2026-08-20T08:17:00-07:00")
        ))
        try addQuantityVector("body-temperature", type: .bodyTemperature, unit: .degreeCelsius())
        try addQuantityVector(
            "body-weight",
            type: .bodyMass,
            unit: .gramUnit(with: .kilo),
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        try addQuantityVector("distance", type: .distanceWalkingRunning, unit: .meter())
        try addQuantityVector(
            "heart-rate",
            type: .heartRate,
            unit: .count().unitDivided(by: .minute()),
            metadata: [
                HKMetadataKeyHeartRateMotionContext: NSNumber(value: 1)
            ]
        )
        try addQuantityVector(
            "oxygen-saturation",
            type: .oxygenSaturation,
            unit: .percent(),
            sourceValue: { $0 / 100 }
        )
        try addQuantityVector(
            "respiratory-rate",
            type: .respiratoryRate,
            unit: .count().unitDivided(by: .minute())
        )
        try addQuantityVector("step-count", type: .stepCount, unit: .count())

        func category(
            _ type: HKCategoryTypeIdentifier,
            _ value: Int,
            effective: MobileSemanticVectorFixture.Effective,
            metadata: [String: Any] = [:]
        ) throws -> HKCategorySample {
            let period = try dates(effective)
            var sourceMetadata = metadata
            sourceMetadata[HKMetadataKeyTimeZone] = Self.sourceTimeZoneIdentifier
            return HKCategorySample(
                type: HKCategoryType(type),
                value: value,
                start: period.start,
                end: period.end,
                device: Self.device,
                metadata: sourceMetadata
            )
        }

        func addCodedVector(
            _ id: String,
            type: HKCategoryTypeIdentifier,
            value: Int,
            expecting code: String,
            metadata: [String: Any] = [:]
        ) throws {
            let fixture = try vector(id)
            guard case .codeableConcept(let vectorCode) = fixture.result, vectorCode == code else {
                throw FixtureError.unexpectedResult(fixture.id)
            }
            try add(id, category(type, value, effective: fixture.effective, metadata: metadata))
        }

        try addCodedVector(
            "cervical-mucus-quality",
            type: .cervicalMucusQuality,
            value: HKCategoryValueCervicalMucusQuality.dry.rawValue,
            expecting: "dry"
        )
        try addCodedVector(
            "intermenstrual-bleeding",
            type: .intermenstrualBleeding,
            value: HKCategoryValue.notApplicable.rawValue,
            expecting: "present"
        )
        try addCodedVector(
            "menstruation-flow",
            type: .menstrualFlow,
            value: HKCategoryValueVaginalBleeding.unspecified.rawValue,
            expecting: "unspecified",
            metadata: [HKMetadataKeyMenstrualCycleStart: true]
        )
        try addCodedVector(
            "ovulation-test-result",
            type: .ovulationTestResult,
            value: HKCategoryValueOvulationTestResult.negative.rawValue,
            expecting: "negative"
        )
        try addCodedVector(
            "sexual-activity",
            type: .sexualActivity,
            value: HKCategoryValue.notApplicable.rawValue,
            expecting: "protected",
            metadata: [HKMetadataKeySexualActivityProtectionUsed: true]
        )

        let mindfulness = try vector("mindfulness-session")
        try add("mindfulness-session", category(
            .mindfulSession,
            HKCategoryValue.notApplicable.rawValue,
            effective: mindfulness.effective
        ))

        // The graded-symptom and stand-hour families own no Mobile vector, so their fixtures state
        // their own exact source facts for the guide validator.
        let symptomStart = try instant("2026-08-20T09:00:00-07:00")
        try add("symptom-headache", HKCategorySample(
            type: HKCategoryType(.headache),
            value: HKCategoryValueSeverity.moderate.rawValue,
            start: symptomStart,
            end: symptomStart.addingTimeInterval(3_600),
            device: Self.device,
            metadata: [HKMetadataKeyTimeZone: Self.sourceTimeZoneIdentifier]
        ))
        let standHourStart = try instant("2026-08-20T10:00:00-07:00")
        try add("apple-stand-hour", HKCategorySample(
            type: HKCategoryType(.appleStandHour),
            value: HKCategoryValueAppleStandHour.stood.rawValue,
            start: standHourStart,
            end: standHourStart.addingTimeInterval(3_600),
            device: Self.device,
            metadata: [HKMetadataKeyTimeZone: Self.sourceTimeZoneIdentifier]
        ))

        let sleepStage = try vector("sleep-stage")
        guard case .codeableConcept(let sleepStageCode) = sleepStage.result,
              sleepStageCode == "light" else {
            throw FixtureError.unexpectedResult(sleepStage.id)
        }
        let sleepDates = try dates(sleepStage)
        try add("sleep-stage", HKCategorySample(
            type: HKCategoryType(.sleepAnalysis),
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: sleepDates.start,
            end: sleepDates.end,
            device: Self.device,
            metadata: [HKMetadataKeyTimeZone: Self.sourceTimeZoneIdentifier]
        ))

        let bloodPressure = try vector("blood-pressure")
        guard case .components(let components) = bloodPressure.result,
              let systolicValue = components.first(where: { $0.id == "systolic" })?.value,
              let diastolicValue = components.first(where: { $0.id == "diastolic" })?.value else {
            throw FixtureError.unexpectedResult(bloodPressure.id)
        }
        let bloodPressureDates = try dates(bloodPressure)
        guard case .dateTime(let bloodPressureInstant) = bloodPressure.effective else {
            throw FixtureError.unexpectedEffective(bloodPressure.id)
        }
        let systolic = try quantity(
            .bloodPressureSystolic,
            .millimeterOfMercury(),
            systolicValue,
            effective: .dateTime(bloodPressureInstant)
        )
        let diastolic = try quantity(
            .bloodPressureDiastolic,
            .millimeterOfMercury(),
            diastolicValue,
            effective: .dateTime(bloodPressureInstant)
        )
        try add("blood-pressure", HKCorrelation(
            type: HKCorrelationType(.bloodPressure),
            start: bloodPressureDates.start,
            end: bloodPressureDates.end,
            objects: [systolic, diastolic],
            device: Self.device,
            metadata: [HKMetadataKeyTimeZone: Self.sourceTimeZoneIdentifier]
        ))

        let ecgStart = try instant("2026-08-20T08:20:00-07:00")
        let ecgContext = HealthKitConversionContext(
            subject: Self.subject,
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            conversionInstant: contextTime
        )
        let ecgSource = HealthKitECGSourceEvidence(
            sourceTypeIdentifier: HealthKitContract.electrocardiogramSourceTypeIdentifier,
            startDate: ecgStart,
            endDate: ecgStart.addingTimeInterval(30),
            timeZone: try #require(TimeZone(identifier: Self.sourceTimeZoneIdentifier)),
            classification: .sinusRhythm,
            symptomsStatus: .none,
            numberOfVoltageMeasurements: 4,
            averageHeartRate: 72,
            samplingFrequency: 500,
            algorithmVersion: HKAppleECGAlgorithmVersion.version2.rawValue,
            wasUserEntered: false
        )
        let ecgWaveform = try HealthKitECGEvidenceValidator.validateWaveform(
            reportedCount: ecgSource.numberOfVoltageMeasurements,
            samplingFrequencyHertz: ecgSource.samplingFrequency,
            points: [
                .init(timeSinceSampleStart: 0.250, millivolts: 0.125),
                .init(timeSinceSampleStart: 0.252, millivolts: 0.250),
                .init(timeSinceSampleStart: 0.254, millivolts: -0.125),
                .init(timeSinceSampleStart: 0.256, millivolts: 0)
            ]
        )
        let ecgInput = HealthKitECGObservationInput(
            source: ecgSource,
            waveform: ecgWaveform,
            symptoms: [],
            context: ecgContext
        )
        // HKElectrocardiogram has no public synthetic initializer. This already-fetched
        // HealthKit sample supplies only the graph envelope's UUID/device/source-revision
        // evidence; the ECG Observation itself is built from the exact ECG input above.
        let ecgEnvelopeSource = try quantity(
            .heartRate,
            .count().unitDivided(by: .minute()),
            72,
            effective: .dateTime("2026-08-20T08:20:00-07:00")
        )
        let ecgConversion = try HealthKitConverter.assembleGraph(
            for: ecgEnvelopeSource,
            context: ecgContext
        ) { recordingDeviceURL, converterURL in
            try HealthKitConverter.ecgObservation(
                input: ecgInput,
                graphContext: HealthKitECGGraphContext(
                    recordingDeviceURL: recordingDeviceURL,
                    converterURL: converterURL
                )
            )
        }
        let ecgObservation = ecgConversion.observation
        guard case .period(let ecgEffectivePeriod) = ecgObservation.effective else {
            Issue.record("ECG fixture must use an effectivePeriod")
            return
        }
        #expect(ecgEffectivePeriod.start?.value?.description == "2026-08-20T08:20:00.25-07:00")
        #expect(ecgEffectivePeriod.end?.value?.description == "2026-08-20T08:20:00.256-07:00")
        let directory = Self.fixtureDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, resource) in fixtures {
            try encoder.encode(resource).write(to: directory.appendingPathComponent("\(name).json"))
        }
        try encoder.encode(ecgConversion.bundle).write(
            to: directory.appendingPathComponent("electrocardiogram.json")
        )
        #expect(fixtures.count == 26)
        let emittedVectorIDs = Set(fixtures.keys).intersection(Set(MobileSemanticVectorFixtures.all.map(\.id)))
        #expect(emittedVectorIDs == Set([
            "active-energy",
            "basal-body-temperature",
            "basal-energy",
            "blood-glucose-unspecified-specimen",
            "blood-pressure",
            "body-fat-percentage",
            "body-height",
            "body-temperature",
            "body-weight",
            "cervical-mucus-quality",
            "dietary-energy",
            "distance",
            "heart-rate",
            "intermenstrual-bleeding",
            "menstruation-flow",
            "mindfulness-session",
            "ovulation-test-result",
            "oxygen-saturation",
            "respiratory-rate",
            "resting-heart-rate",
            "sexual-activity",
            "sleep-stage",
            "step-count"
        ]))
    }

    @Test
    func writeAuthoritativeSourceInventory() throws {
        let rows = try HealthKitCatalog.entries.map { entry in
            SourceInventory.Row(
                sourceTypeIdentifier: entry.sourceTypeIdentifier,
                title: entry.title,
                measurementIDs: entry.measurements.map(\.id),
                profiles: try entry.measurements.flatMap { measurement in
                    try measurement.profiles.map { profile in
                        try #require(profile.value?.url.absoluteString)
                    }
                },
                implementationStatus: entry.implementationStatus.rawValue,
                requirement: entry.requirement
            )
        }
        let inventory = SourceInventory(schemaVersion: 1, rows: rows)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        let output = Self.inventoryURL
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(inventory).write(to: output)

        #expect(rows.map(\.sourceTypeIdentifier) == rows.map(\.sourceTypeIdentifier).sorted())
        #expect(Set(rows.map(\.sourceTypeIdentifier)).count == rows.count)
    }
}

#endif
