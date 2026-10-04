//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

// The conformance corpus keeps all emitted profiles and their exact source vectors in one auditable suite.
// swiftlint:disable function_body_length type_body_length file_length

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

    private static let subject = Subject.testPatient
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

    /// The goldens whose shapes no fixture above covers: the workout session and every shape the fix round added.
    /// `exporter-deployment-state-of-mind` is left out: its negative valence fails the pinned guide's own
    /// `healthkit-state-of-mind-value-domain-1` in the HL7 validator, which rejects every negative value although the
    /// invariant admits -1 through 1, an IG defect.
    private static let validatedGoldens: Set<String> = [
        "workout-session",
        "workout-session-context",
        "writer-non-ascii-name",
        "gad7-assessment",
        "exporter-default-apple-watch-heart-rate",
        "exporter-default-apple-watch-heart-rate-without-unit-token",
        "exporter-deployment-own-heart-rate",
        "exporter-deployment-electrocardiogram",
        "exporter-deployment-electrocardiogram-symptom",
        "exporter-deployment-blood-pressure",
        "exporter-deployment-retraction",
        "exporter-clinical-record-r4",
        "exporter-clinical-record-dstu2"
    ]

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
            converter: ApplicationDevice.test(
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

        // Spec F1: the workout session, its one output, from the guide's workout vector; its lap is withheld.
        let workout = try vector("workout")
        guard case .codeableConcept("running") = workout.result else {
            throw FixtureError.unexpectedResult(workout.id)
        }
        let workoutDates = try dates(workout)
        try add("workout", HKWorkout(
            activityType: .running,
            start: workoutDates.start,
            end: workoutDates.end,
            workoutEvents: [HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: workoutDates.start, duration: 900), metadata: nil)],
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 420),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 7_500),
            device: Self.device,
            metadata: [HKMetadataKeyTimeZone: Self.sourceTimeZoneIdentifier]
        ))

        // A source the caller classifies as an application: its writer Device, its host and the Provenance author.
        let writerContext = HealthKitConversionContext(
            subject: Self.subject,
            converter: context.converter,
            graphIdentifierSystem: context.graphIdentifierSystem,
            writer: .application,
            converterWasGateway: true,
            conversionInstant: contextTime
        )
        fixtures["heart-rate-classified-writer"] = try converter.convert(
            StoredSampleFixtures.stored(
                quantity(.heartRate, .count().unitDivided(by: .minute()), 64, effective: .dateTime("2026-08-20T08:25:00-07:00")),
                uuid: UUID(uuidString: "6C4B1D1E-0000-4000-8000-0000000000F1") ?? UUID(),
                writer: GoldenFixtures.foreignWriter
            ),
            context: writerContext
        ).bundle

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
            conversionInstant: contextTime,
            studies: [.test("study-a"), .test("study-b")]
        )
        let studyQuantity = try converter.convert(
            quantity(
                .heartRate,
                .count().unitDivided(by: .minute()),
                72,
                effective: .dateTime("2026-08-20T08:20:00-07:00")
            ),
            context: ecgContext
        )
        fixtures["heart-rate-two-studies"] = studyQuantity.bundle
        let quantityStudies = studyQuantity.observation.extension?.filter { $0.url == Canonicals.researchStudy } ?? []
        #expect(quantityStudies.count == 2)
        #expect(studyQuantity.observation.extension?.contains { $0.url == Canonicals.instantiatesCanonical } != true)
        // HKElectrocardiogram has no public synthetic initializer, so the stored-sample fixtures state the ECG's
        // reading, and its voltages travel beside it as the caller supplies them.
        let ecgFacts = StoredSampleFixtures.SampleFacts(
            uuid: GoldenFixtures.uuid(0xF6),
            start: ecgStart,
            end: ecgStart.addingTimeInterval(30),
            device: Self.device,
            metadata: [
                HKMetadataKeyTimeZone: Self.sourceTimeZoneIdentifier,
                HKMetadataKeyAppleECGAlgorithmVersion: HKAppleECGAlgorithmVersion.version2.rawValue
            ],
            writer: .unattributed
        )
        let ecg = try StoredSampleFixtures.electrocardiogram(facts: ecgFacts, reading: StoredElectrocardiogram.Reading(
            classification: .sinusRhythm,
            symptomsStatus: .none,
            numberOfVoltageMeasurements: 4,
            averageHeartRate: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 72),
            samplingFrequency: HKQuantity(unit: .hertz(), doubleValue: 500)
        ))
        let voltages = try [(0.250, 0.125), (0.252, 0.250), (0.254, -0.125), (0.256, 0)].map { offset, millivolts in
            try StoredSampleFixtures.voltageMeasurement(offset: offset, millivolts: millivolts)
        }
        let ecgConversion = try converter.convert(
            HealthKitECGRecord(electrocardiogram: ecg, voltageMeasurements: voltages),
            context: ecgContext,
            symptomContexts: []
        )
        let ecgObservation = ecgConversion.observation
        let ecgStudies = ecgObservation.extension?.filter { $0.url == Canonicals.researchStudy } ?? []
        #expect(ecgStudies.map(\.value) == quantityStudies.map(\.value))
        #expect(ecgObservation.extension?.contains { $0.url == Canonicals.instantiatesCanonical } != true)
        guard case .period(let ecgEffectivePeriod) = ecgObservation.effective else {
            Issue.record("ECG fixture must use an effectivePeriod")
            return
        }
        #expect(ecgEffectivePeriod.start?.value?.description == "2026-08-20T08:20:00.25-07:00")
        #expect(ecgEffectivePeriod.end?.value?.description == "2026-08-20T08:20:00.256-07:00")
        #expect(ecgObservation.hasMember == nil)
        let interpretation = try #require(ecgObservation.interpretation)
        #expect(interpretation.count == 1)
        #expect(interpretation.first?.coding?.count == 1)
        #expect(interpretation.first?.coding?.first?.system?.value?.url.absoluteString ==
            "https://grovealliance.org/fhir/healthkit/CodeSystem/healthkit-ecg-classification")
        #expect(interpretation.first?.coding?.first?.code?.value?.string == "sinusRhythm")
        #expect(ecgObservation.method?.coding?.count == 1)
        #expect(ecgObservation.method?.coding?.first?.system?.value?.url.absoluteString ==
            "https://grovealliance.org/fhir/healthkit/CodeSystem/healthkit-ecg-algorithm-version")
        #expect(ecgObservation.method?.coding?.first?.code?.value?.string == "version2")
        #expect(ecgConversion.graphIdentifiers.childOutputs.count == 1)
        let ecgChildren = ecgConversion.bundle.entry?.compactMap { entry -> Observation? in
            guard case .observation(let child)? = entry.resource,
                  child.meta?.profile?.contains(
                      "https://grovealliance.org/fhir/healthkit/StructureDefinition/healthkit-ecg-average-heart-rate-observation"
                  ) == true else {
                return nil
            }
            return child
        } ?? []
        #expect(ecgChildren.count == 1)
        let averageHeartRate = try #require(ecgChildren.first)
        #expect(averageHeartRate.effective == ecgObservation.effective)
        let averageHeartRateCategory = try #require(averageHeartRate.category)
        #expect(averageHeartRateCategory.count == 1)
        let averageHeartRateCategoryCodings = try #require(averageHeartRateCategory.first?.coding)
        #expect(averageHeartRateCategoryCodings.count == 1)
        #expect(averageHeartRateCategoryCodings.first?.system?.value?.url.absoluteString ==
            "http://terminology.hl7.org/CodeSystem/observation-category")
        #expect(averageHeartRateCategoryCodings.first?.code?.value?.string == "vital-signs")
        let expectedECGURL = try ecgConversion.graphIdentifiers.primaryOutput.fullURLString
        #expect(averageHeartRate.derivedFrom?.count == 1)
        #expect(averageHeartRate.derivedFrom?.first?.reference?.value?.string == expectedECGURL)
        #expect(averageHeartRate.identifier?.count == 2)
        guard case .quantity(let averageHeartRateValue) = averageHeartRate.value else {
            Issue.record("ECG average heart-rate companion must carry valueQuantity")
            return
        }
        #expect(averageHeartRateValue.value?.value?.decimal == 72)
        #expect(averageHeartRateValue.system?.value?.url.absoluteString == "http://unitsofmeasure.org")
        #expect(averageHeartRateValue.code?.value?.string == "/min")
        let legacyECGExtensionURLs = Set([
            "https://grovealliance.org/fhir/healthkit/StructureDefinition/healthkit-ecg-average-heart-rate",
            "https://grovealliance.org/fhir/healthkit/StructureDefinition/healthkit-ecg-sampling-frequency",
            "https://grovealliance.org/fhir/healthkit/StructureDefinition/healthkit-ecg-voltage-measurement-count"
        ])
        #expect(ecgObservation.extension?.allSatisfy {
            guard let url = $0.url.value?.url.absoluteString else {
                return true
            }
            return !legacyECGExtensionURLs.contains(url)
        } == true)
        #expect(ecgConversion.provenance.target.count == 2)
        let directory = Self.fixtureDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, resource) in fixtures {
            try encoder.encode(resource).write(to: directory.appendingPathComponent("\(name).json"))
        }
        try encoder.encode(ecgConversion.bundle).write(
            to: directory.appendingPathComponent("electrocardiogram.json")
        )
        let validatedGoldens = Self.validatedGoldens.subtracting(GoldenCase.unavailableHere)
        #expect(Set(GoldenCase.all.map(\.name)).isSuperset(of: validatedGoldens))
        for goldenCase in GoldenCase.all where validatedGoldens.contains(goldenCase.name) {
            try goldenCase.output().graph.json.write(to: directory.appendingPathComponent("golden-\(goldenCase.name).json"))
        }
        #expect(fixtures.count == 29)
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
            "step-count",
            "workout"
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
        let inventory = SourceInventory(schemaVersion: 0, rows: rows)
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
