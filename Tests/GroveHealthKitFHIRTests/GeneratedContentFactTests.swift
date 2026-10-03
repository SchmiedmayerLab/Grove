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
@Suite
struct GeneratedContentFactTests {
    /// Every HealthKit ECG classification and the source value the IG spells it with.
    private static let classifications: [(HKElectrocardiogram.Classification, String)] = [
        (.notSet, "notSet"), (.sinusRhythm, "sinusRhythm"), (.atrialFibrillation, "atrialFibrillation"),
        (.inconclusiveLowHeartRate, "inconclusiveLowHeartRate"), (.inconclusiveHighHeartRate, "inconclusiveHighHeartRate"),
        (.inconclusivePoorReading, "inconclusivePoorReading"), (.inconclusiveOther, "inconclusiveOther"),
        (.unrecognized, "unrecognized")
    ]

    /// Every HealthKit ECG symptoms status and the source value the IG spells it with.
    private static let symptomsStatuses: [(HKElectrocardiogram.SymptomsStatus, String)] = [
        (.notSet, "notSet"), (.none, "none"), (.present, "present")
    ]

    /// The measurements the pinned IG fixes a category for: the eight vital signs other than body-mass index.
    private static let categorizedMeasurements: Set<String> = [
        "blood-pressure", "body-height", "body-temperature", "body-weight", "heart-rate", "oxygen-saturation",
        "respiratory-rate", "resting-heart-rate"
    ]

    /// When every sample and ECG this suite builds starts.
    private static let start = Date(timeIntervalSince1970: 1_787_148_600)

    /// A sample of a row bound as a quantity, a percent or blood pressure, the bindings of every categorized
    /// measurement; nil for any other binding.
    private static func sample(_ row: HealthKitContractRow, binding: HealthKitFHIRBinding) -> HKSample? {
        let quantity = { (identifier: HKQuantityTypeIdentifier, unit: HKUnit, value: Double) in
            HKQuantitySample(type: HKQuantityType(identifier), quantity: HKQuantity(unit: unit, doubleValue: value), start: start, end: start)
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
            return HKCorrelation(type: HKCorrelationType(.bloodPressure), start: start, end: start, objects: members)
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

    @Test("The generated ECG roles and discriminators are the outputs the catalog lists and the converter drafts")
    func electrocardiogramOutputsAreTodays() throws {
        let claim = HealthKitElectrocardiogramClaim.self
        let outputs = HealthKitCatalog.outputs(for: .electrocardiogram)
        #expect(outputs.map(\.role) == [claim.outputRole, claim.averageHeartRateOutputRole])
        #expect(outputs.map(\.discriminator) == [claim.outputDiscriminator, claim.averageHeartRateOutputDiscriminator])
        let child = try #require(try HealthKitConverter.ecgAverageHeartRateChild(input: try Self.input(averageHeartRate: 72)))
        #expect(child.role == claim.averageHeartRateOutputRole)
        #expect(child.discriminator == claim.averageHeartRateOutputDiscriminator)
    }

    @Test("The average heart rate states the generated profiles and its measurement's code, category and quantity")
    func averageHeartRateIsTodays() throws {
        let claim = HealthKitElectrocardiogramClaim.self
        let measurement = claim.averageHeartRateMeasurement
        #expect(measurement.id == MeasurementCatalog.heartRate.id)
        let child = try #require(try HealthKitConverter.ecgAverageHeartRateChild(input: try Self.input(averageHeartRate: 72)))
        guard case .observation(let observation) = child.resource else {
            Issue.record("The average heart rate is not an Observation")
            return
        }
        #expect(observation.meta?.profile == claim.averageHeartRateProfiles)
        // The display ("Heart rate") is not the measurement's: the heart-rate contract states none.
        let code = try #require(observation.code.coding?.first)
        #expect(code.system?.value?.url.absoluteString == measurement.code.system)
        #expect(code.code?.value?.string == measurement.code.code)
        #expect(Self.strings(observation.category?.first?.coding?.first) == Self.strings(measurement.category))
        guard case .quantity(let quantity)? = observation.value else {
            Issue.record("The average heart rate states no Quantity")
            return
        }
        #expect(Self.strings(quantity) == Self.strings(try #require(measurement.quantity)))
    }

    @Test("The ECG waveform states the generated lead and voltage unit, and every classification its generated code")
    func electrocardiogramLeadAndClassificationsAreTodays() throws {
        let claim = HealthKitElectrocardiogramClaim.self
        let component = try #require(try HealthKitConverter.ecgObservation(input: try Self.input()).component?.first)
        #expect(Self.strings(component.code.coding?.first) == Self.strings(claim.leadCode))
        guard case .sampledData(let waveform)? = component.value else {
            Issue.record("The ECG component states no SampledData")
            return
        }
        #expect(Self.strings(waveform.origin) == Self.strings(claim.voltageQuantity))
        #expect(Set(Self.classifications.map(\.1)) == Set(claim.classification.codes.keys))
        for (classification, sourceValue) in Self.classifications {
            let observation = try HealthKitConverter.ecgObservation(input: try Self.input(classification: classification))
            let coding = observation.interpretation?.first?.coding?.first
            #expect(Self.strings(coding) == [claim.classification.system, claim.classification.codes[sourceValue], nil], "\(sourceValue)")
        }
    }

    @Test("Every ECG symptoms status and algorithm version states its generated code")
    func electrocardiogramStatusesAndAlgorithmsAreTodays() throws {
        let claim = HealthKitElectrocardiogramClaim.self
        #expect(Set(Self.symptomsStatuses.map(\.1)) == Set(claim.symptomsStatus.codes.keys))
        for (status, sourceValue) in Self.symptomsStatuses {
            let observation = try HealthKitConverter.ecgObservation(input: try Self.input(symptomsStatus: status))
            let statusExtension = observation.extension?.first { $0.url == Canonicals.healthKitECGSymptomsStatusExtension }
            guard case .code(let code)? = statusExtension?.value else {
                Issue.record("\(sourceValue) states no symptoms-status code")
                continue
            }
            #expect(code.value?.string == claim.symptomsStatus.codes[sourceValue], "\(sourceValue)")
        }
        let versions = [HKAppleECGAlgorithmVersion.version1, .version2].map(\.rawValue)
        #expect(Set(versions.map(String.init)) == Set(claim.algorithmVersion.codes.keys))
        for version in versions {
            let observation = try HealthKitConverter.ecgObservation(input: try Self.input(algorithmVersion: version))
            let coding = observation.method?.coding?.first
            #expect(Self.strings(coding) == [claim.algorithmVersion.system, claim.algorithmVersion.codes[String(version)], nil], "\(version)")
        }
    }

    @Test("Today's symptom check admits exactly the generated symptom source types among every category type")
    func correlatedSymptomTypesAreTodays() throws {
        let generated = HealthKitElectrocardiogramClaim.correlatedSymptomSourceTypeIdentifiers
        var admitted: Set<String> = []
        for row in HealthKitContract.rows {
            guard let type = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: row.sourceTypeIdentifier)) else {
                continue
            }
            let facts = StoredSampleFixtures.SampleFacts(
                uuid: UUID(), start: Self.start, end: Self.start, device: nil, metadata: nil, writer: .unattributed
            )
            let sample = try StoredSampleFixtures.categorySample(type, value: 0, facts: facts)
            if (try? HealthKitConverter.validatedSymptomSamples([sample], status: .present)) != nil {
                admitted.insert(row.sourceTypeIdentifier)
            }
        }
        #expect(generated.count == 7)
        #expect(Set(generated).count == generated.count)
        #expect(admitted == Set(generated))
    }
}

#endif
