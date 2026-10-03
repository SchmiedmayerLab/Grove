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


/// The content facts the generator emits from the pinned IG (the measurement category, the ECG claim, the
/// body-mass-index contract) against what today's content code states by hand, read from what that code builds
/// wherever it builds something, so the content rewrite can take the generated facts without changing an output.
///
/// The suite reads the old content internals, so the rewrite's deletion step (M6) deletes it with the O3/O4
/// oracles: by then the new builders read these facts, and the goldens and the content corpus pin them.
@Suite
struct GeneratedContentFactTests {
    /// The measurements the pinned IG fixes a category for: the eight vital signs other than body-mass index.
    private static let categorizedMeasurements: Set<String> = [
        "blood-pressure", "body-height", "body-temperature", "body-weight", "heart-rate", "oxygen-saturation",
        "respiratory-rate", "resting-heart-rate"
    ]

    /// Every raw value the ECG sweeps try: each one HealthKit declares today (the largest is 100, `unrecognized`)
    /// and the undeclared ones around them.
    private static let rawValues = -1...255

    /// When every sample and ECG this suite builds starts.
    private static let start = Date(timeIntervalSince1970: 1_787_148_600)

    @Test("The generated body-mass-index contract is the hand contract, field by field, under today's profile rule")
    func bodyMassIndexIsTheHandContract() {
        let generated = HealthKitContract.bodyMassIndex
        let derived = HealthKitFHIRObservationContract(shared: generated)
        let hand = HealthKitFHIRObservationContract.bodyMassIndex
        #expect(derived.id == hand.id)
        #expect(derived.profiles == hand.profiles)
        #expect(derived.profiles == HealthKitContract.bodyMassIndexProfiles)
        #expect(derived.code == hand.code)
        #expect(derived.requiredCodings == hand.requiredCodings)
        #expect(derived.quantity == hand.quantity)
        #expect(derived.components == hand.components)
        #expect(derived.resultCodeSystem == hand.resultCodeSystem)
        #expect(derived.measurementResultCodes == hand.measurementResultCodes)
        #expect(derived.method == hand.method)
        #expect(derived.effective == hand.effective)
        // What the hand contract has no field for is empty; the vital-signs category stays Grove's own addition.
        #expect(generated.allowedValues.isEmpty)
        #expect(generated.methodChoice.isEmpty)
        #expect(generated.category == nil)
        // No catalog lists it, so the content corpus grid and the reverse projection see body-mass index as before.
        #expect(!(MeasurementCatalog.all + HealthKitMeasurementCatalog.all).contains { $0.id == generated.id })
    }

    @Test("Every generated category is the one today's converter states for each row of that measurement")
    func categoriesAreTodays() throws {
        let categorized = (MeasurementCatalog.all + HealthKitMeasurementCatalog.all).filter { $0.category != nil }
        #expect(Set(categorized.map(\.id)) == Self.categorizedMeasurements)
        var converted = 0
        for contract in categorized {
            for row in HealthKitContract.rows where row.measurementIDs.first == contract.id {
                let binding = try #require(HealthKitCatalog.binding(forSourceTypeIdentifier: row.sourceTypeIdentifier))
                let sample = try #require(Self.sample(row, binding: binding), "\(row.sourceTypeIdentifier) has no sample builder")
                let observation = try HealthKitConverter.observation(for: sample, binding: binding)
                let coding = observation.category?.first?.coding?.first
                #expect(observation.category?.count == 1, "\(row.sourceTypeIdentifier)")
                #expect(Self.strings(coding) == Self.strings(contract.category), "\(row.sourceTypeIdentifier)")
                converted += 1
            }
        }
        #expect(converted == Self.categorizedMeasurements.count)
    }

    @Test("The generated ECG outputs are the ones the catalog lists and the converter drafts")
    func electrocardiogramOutputsAreTodays() throws {
        let claim = HealthKitElectrocardiogramClaim.self
        let outputs = HealthKitCatalog.outputs(for: .electrocardiogram)
        #expect(outputs.map(\.role) == [claim.waveform.role, claim.averageHeartRate.role])
        #expect(outputs.map(\.discriminator) == [claim.waveform.discriminator, claim.averageHeartRate.discriminator])
        let waveform = try HealthKitConverter.ecgObservation(input: try Self.input())
        #expect(waveform.meta?.profile == claim.waveform.profiles)
        let child = try #require(try HealthKitConverter.ecgAverageHeartRateChild(input: try Self.input(averageHeartRate: 72)))
        #expect(child.role == claim.averageHeartRate.role)
        #expect(child.discriminator == claim.averageHeartRate.discriminator)
    }

    @Test("The average heart rate states the generated profiles and code, and its measurement's category and quantity")
    func averageHeartRateIsTodays() throws {
        let claim = HealthKitElectrocardiogramClaim.self
        let measurement = claim.averageHeartRateMeasurement
        #expect(measurement.id == MeasurementCatalog.heartRate.id)
        let child = try #require(try HealthKitConverter.ecgAverageHeartRateChild(input: try Self.input(averageHeartRate: 72)))
        guard case .observation(let observation) = child.resource else {
            Issue.record("The average heart rate is not an Observation")
            return
        }
        #expect(observation.meta?.profile == claim.averageHeartRate.profiles)
        // The claim's code carries the display ("Heart rate"); the heart-rate contract's code states none.
        #expect(Self.strings(observation.code.coding?.first) == Self.strings(claim.averageHeartRateCode))
        #expect(Self.strings(claim.averageHeartRateCode).prefix(2) == Self.strings(measurement.code).prefix(2))
        #expect(Self.strings(observation.category?.first?.coding?.first) == Self.strings(measurement.category))
        guard case .quantity(let quantity)? = observation.value else {
            Issue.record("The average heart rate states no Quantity")
            return
        }
        #expect(Self.strings(quantity) == Self.strings(try #require(measurement.quantity)))
        // The claim, not the measurement (dateTime or Period), fixes the effective: the waveform's exact Period.
        guard case .period? = observation.effective else {
            Issue.record("The average heart rate states no effectivePeriod")
            return
        }
    }

    @Test("The ECG waveform reads the generated lead and states its generated coding and voltage unit")
    func electrocardiogramLeadIsTodays() throws {
        let claim = HealthKitElectrocardiogramClaim.self
        let measurements = try [0.250, 0.252, 0.254, 0.256].enumerated().map { index, offset in
            try StoredSampleFixtures.voltageMeasurement(offset: offset, millivolts: Double(index) / 8)
        }
        let points = try measurements.map { measurement in
            let voltage = try #require(measurement.quantity(for: claim.sourceLead))
            return HealthKitECGVoltagePoint(
                timeSinceSampleStart: measurement.timeSinceSampleStart,
                millivolts: voltage.doubleValue(for: .voltUnit(with: .milli))
            )
        }
        let input = try Self.input()
        let record = HealthKitECGRecord(electrocardiogram: try Self.electrocardiogram(), voltageMeasurements: measurements)
        let today = try HealthKitConverter.validatedWaveform(for: record, source: input.source)
        let generated = try HealthKitECGEvidenceValidator.validateWaveform(
            reportedCount: points.count, samplingFrequencyHertz: 500, points: points
        )
        #expect(today.data == generated.data)
        let component = try #require(try HealthKitConverter.ecgObservation(input: input).component?.first)
        #expect(Self.strings(component.code.coding?.first) == Self.strings(claim.leadCode))
        guard case .sampledData(let waveform)? = component.value else {
            Issue.record("The ECG component states no SampledData")
            return
        }
        #expect(Self.strings(waveform.origin) == Self.strings(claim.voltageQuantity))
    }

    @Test("Today's converter codes exactly the generated classifications, each with its generated code")
    func classificationsAreTodays() throws {
        let claim = HealthKitElectrocardiogramClaim.self
        #expect(claim.classificationCodes.keys.allSatisfy { Self.rawValues.contains($0.rawValue) })
        for raw in Self.rawValues {
            guard let classification = HKElectrocardiogram.Classification(rawValue: raw) else {
                continue
            }
            let input = try Self.input(classification: classification)
            guard let code = claim.classificationCodes[classification] else {
                #expect(throws: HealthKitConversionError.ecgEvidence(.unsupportedClassification(raw))) {
                    try HealthKitConverter.ecgObservation(input: input)
                }
                continue
            }
            let coding = try HealthKitConverter.ecgObservation(input: input).interpretation?.first?.coding?.first
            #expect(Self.strings(coding) == [claim.classificationSystem, code, nil], "\(raw)")
        }
    }

    @Test("Today's converter codes exactly the generated symptoms statuses, each with its generated code")
    func symptomsStatusesAreTodays() throws {
        let claim = HealthKitElectrocardiogramClaim.self
        #expect(claim.symptomsStatusCodes.keys.allSatisfy { Self.rawValues.contains($0.rawValue) })
        for raw in Self.rawValues {
            guard let status = HKElectrocardiogram.SymptomsStatus(rawValue: raw) else {
                continue
            }
            let input = try Self.input(symptomsStatus: status)
            guard let code = claim.symptomsStatusCodes[status] else {
                #expect(throws: HealthKitConversionError.ecgEvidence(.unsupportedSymptomsStatus(raw))) {
                    try HealthKitConverter.ecgObservation(input: input)
                }
                continue
            }
            let observation = try HealthKitConverter.ecgObservation(input: input)
            let statusExtension = observation.extension?.first { $0.url == Canonicals.healthKitECGSymptomsStatusExtension }
            guard case .code(let stated)? = statusExtension?.value else {
                Issue.record("\(raw) states no symptoms-status code")
                continue
            }
            #expect(stated.value?.string == code, "\(raw)")
        }
        // The wire states the code alone (valueCode); its CodeSystem is named like the extension that carries it.
        let extensionURL = Canonicals.healthKitECGSymptomsStatusExtension.value?.url.absoluteString
        #expect(claim.symptomsStatusSystem == extensionURL?.replacingOccurrences(of: "/StructureDefinition/", with: "/CodeSystem/"))
    }

    @Test("Today's converter codes exactly the generated algorithm versions, each with its generated code")
    func algorithmVersionsAreTodays() throws {
        let claim = HealthKitElectrocardiogramClaim.self
        #expect(claim.algorithmVersionCodes.keys.allSatisfy { Self.rawValues.contains($0) })
        for version in Self.rawValues {
            let input = try Self.input(algorithmVersion: version)
            guard let code = claim.algorithmVersionCodes[version] else {
                #expect(throws: HealthKitConversionError.ecgEvidence(.unsupportedAlgorithmVersion(version))) {
                    try HealthKitConverter.ecgObservation(input: input)
                }
                continue
            }
            let coding = try HealthKitConverter.ecgObservation(input: input).method?.coding?.first
            #expect(Self.strings(coding) == [claim.algorithmVersionSystem, code, nil], "\(version)")
        }
    }

    @Test("Today's symptom check admits exactly the generated symptom source types among every category type")
    func correlatedSymptomTypesAreTodays() throws {
        var admitted: Set<HealthKitSourceType> = []
        for type in HealthKitSourceType.allCases {
            guard let categoryType = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: type.rawValue)) else {
                continue
            }
            let facts = StoredSampleFixtures.SampleFacts(
                uuid: UUID(), start: Self.start, end: Self.start, device: nil, metadata: nil, writer: .unattributed
            )
            let sample = try StoredSampleFixtures.categorySample(categoryType, value: 0, facts: facts)
            if (try? HealthKitConverter.validatedSymptomSamples([sample], status: .present)) != nil {
                admitted.insert(type)
            }
        }
        #expect(!admitted.isEmpty)
        #expect(admitted == HealthKitElectrocardiogramClaim.correlatedSymptomSourceTypes)
    }
}


extension GeneratedContentFactTests {
    /// A one-minute sample of a row bound as a quantity, a percent or blood pressure, the bindings of every
    /// categorized measurement, so every effective rule admits it; nil for any other binding.
    private static func sample(_ row: HealthKitContractRow, binding: HealthKitFHIRBinding) -> HKSample? {
        let end = start.addingTimeInterval(60)
        let quantity = { (identifier: HKQuantityTypeIdentifier, unit: HKUnit, value: Double) in
            HKQuantitySample(type: HKQuantityType(identifier), quantity: HKQuantity(unit: unit, doubleValue: value), start: start, end: end)
        }
        switch binding {
        case .quantity(_, let unit):
            return quantity(HKQuantityTypeIdentifier(rawValue: row.sourceTypeIdentifier), unit, 1)
        case .percent:
            return quantity(HKQuantityTypeIdentifier(rawValue: row.sourceTypeIdentifier), .percent(), 0.5)
        case .bloodPressure:
            let members: Set<HKSample> = [
                quantity(.bloodPressureSystolic, .millimeterOfMercury(), 120),
                quantity(.bloodPressureDiastolic, .millimeterOfMercury(), 80)
            ]
            return HKCorrelation(type: HKCorrelationType(.bloodPressure), start: start, end: end, objects: members)
        default:
            return nil
        }
    }

    /// The evidence of a valid four-point ECG in UTC, stating the given source facts.
    private static func input(
        classification: HKElectrocardiogram.Classification = .sinusRhythm,
        symptomsStatus: HKElectrocardiogram.SymptomsStatus = .none,
        algorithmVersion: Int? = nil,
        averageHeartRate: Double? = nil
    ) throws -> HealthKitECGObservationInput {
        let points = [0.250, 0.252, 0.254, 0.256].enumerated().map { index, offset in
            HealthKitECGVoltagePoint(timeSinceSampleStart: offset, millivolts: Double(index))
        }
        let source = HealthKitECGSourceEvidence(
            sourceTypeIdentifier: HealthKitContract.electrocardiogramSourceTypeIdentifier,
            startDate: start,
            endDate: start.addingTimeInterval(30),
            timeZone: .gmt,
            classification: classification,
            symptomsStatus: symptomsStatus,
            numberOfVoltageMeasurements: points.count,
            averageHeartRate: averageHeartRate,
            samplingFrequency: 500,
            algorithmVersion: algorithmVersion
        )
        let waveform = try HealthKitECGEvidenceValidator.validateWaveform(reportedCount: points.count, samplingFrequencyHertz: 500, points: points)
        return HealthKitECGObservationInput(source: source, waveform: waveform, symptomOutputIdentifiers: [])
    }

    /// A stored ECG of four voltages; the waveform reads only the voltages its record carries.
    private static func electrocardiogram() throws -> HKElectrocardiogram {
        let facts = StoredSampleFixtures.SampleFacts(
            uuid: UUID(), start: start, end: start.addingTimeInterval(30), device: nil, metadata: nil, writer: .unattributed
        )
        let reading = StoredElectrocardiogram.Reading(
            classification: .sinusRhythm, symptomsStatus: .none, numberOfVoltageMeasurements: 4, averageHeartRate: nil, samplingFrequency: nil
        )
        return try StoredSampleFixtures.electrocardiogram(facts: facts, reading: reading)
    }

    /// A coding's system, code and display.
    private static func strings(_ coding: Coding?) -> [String?] {
        [coding?.system?.value?.url.absoluteString, coding?.code?.value?.string, coding?.display?.value?.string]
    }

    /// A coding contract's system, code and display.
    private static func strings(_ coding: CodingContract?) -> [String?] {
        [coding?.system, coding?.code, coding?.display]
    }

    /// A quantity's system, code and unit.
    private static func strings(_ quantity: Quantity) -> [String?] {
        [quantity.system?.value?.url.absoluteString, quantity.code?.value?.string, quantity.unit?.value?.string]
    }

    /// A quantity contract's system, code and unit.
    private static func strings(_ quantity: QuantityContract) -> [String?] {
        [quantity.system, quantity.code, quantity.unit]
    }
}

#endif
