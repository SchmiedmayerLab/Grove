//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

// The coded-result suite covers every category absorption family in one auditable matrix.
// swiftlint:disable file_length type_body_length

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


@Suite
struct HealthKitFHIRCategoryConversionTests {
    struct SeverityCase: CustomTestStringConvertible, Sendable {
        let value: HKCategoryValueSeverity
        let sharedCode: String
        let sourceCode: String

        var testDescription: String { sourceCode }
    }

    struct AbsorptionCase: CustomTestStringConvertible, Sendable {
        let identifier: HKCategoryTypeIdentifier
        let value: Int
        let measurement: MeasurementContract
        let sharedCode: String
        let sourceCode: String
        let sourceSystem: FHIRPrimitive<FHIRURI>
        /// Metadata HealthKit itself requires before the sample can be constructed.
        var requiredMetadata: [String: Bool] = [:]

        var testDescription: String { "\(identifier.rawValue).\(sourceCode)" }
    }

    static let severityCases: [SeverityCase] = [
        SeverityCase(value: .unspecified, sharedCode: "present", sourceCode: "unspecified"),
        SeverityCase(value: .notPresent, sharedCode: "not-present", sourceCode: "notPresent"),
        SeverityCase(value: .mild, sharedCode: "mild", sourceCode: "mild"),
        SeverityCase(value: .moderate, sharedCode: "moderate", sourceCode: "moderate"),
        SeverityCase(value: .severe, sharedCode: "severe", sourceCode: "severe")
    ]

    static let absorptionCases: [AbsorptionCase] = [
        AbsorptionCase(
            identifier: .appleStandHour,
            value: HKCategoryValueAppleStandHour.stood.rawValue,
            measurement: HealthKitMeasurementCatalog.appleStandHour,
            sharedCode: "stood",
            sourceCode: "stood",
            sourceSystem: Canonicals.healthKitAppleStandHourValue
        ),
        AbsorptionCase(
            identifier: .appetiteChanges,
            value: HKCategoryValueAppetiteChanges.decreased.rawValue,
            measurement: HealthKitMeasurementCatalog.symptomAppetiteChanges,
            sharedCode: "decreased",
            sourceCode: "decreased",
            sourceSystem: Canonicals.healthKitAppetiteChanges
        ),
        AbsorptionCase(
            identifier: .appetiteChanges,
            value: HKCategoryValueAppetiteChanges.unspecified.rawValue,
            measurement: HealthKitMeasurementCatalog.symptomAppetiteChanges,
            sharedCode: "change-unspecified",
            sourceCode: "unspecified",
            sourceSystem: Canonicals.healthKitAppetiteChanges
        ),
        AbsorptionCase(
            identifier: .cervicalMucusQuality,
            value: HKCategoryValueCervicalMucusQuality.eggWhite.rawValue,
            measurement: MeasurementCatalog.cervicalMucusQuality,
            sharedCode: "egg-white",
            sourceCode: "eggWhite",
            sourceSystem: Canonicals.healthKitCervicalMucusQuality
        ),
        AbsorptionCase(
            identifier: .contraceptive,
            value: HKCategoryValueContraceptive.intrauterineDevice.rawValue,
            measurement: HealthKitMeasurementCatalog.contraceptiveUse,
            sharedCode: "intrauterine-device",
            sourceCode: "intrauterineDevice",
            sourceSystem: Canonicals.healthKitContraceptive
        ),
        AbsorptionCase(
            identifier: .menstrualFlow,
            value: HKCategoryValueVaginalBleeding.heavy.rawValue,
            measurement: MeasurementCatalog.menstruationFlow,
            sharedCode: "heavy",
            sourceCode: "heavy",
            sourceSystem: Canonicals.healthKitVaginalBleeding,
            requiredMetadata: [HKMetadataKeyMenstrualCycleStart: true]
        ),
        AbsorptionCase(
            identifier: .bleedingAfterPregnancy,
            value: HKCategoryValueVaginalBleeding.none.rawValue,
            measurement: HealthKitMeasurementCatalog.bleedingAfterPregnancy,
            sharedCode: "none",
            sourceCode: "none",
            sourceSystem: Canonicals.healthKitVaginalBleeding
        ),
        // The HealthKit estrogen-surge case widens to high-fertility; the exact token is retained.
        AbsorptionCase(
            identifier: .ovulationTestResult,
            value: HKCategoryValueOvulationTestResult.estrogenSurge.rawValue,
            measurement: MeasurementCatalog.ovulationTestResult,
            sharedCode: "high-fertility",
            sourceCode: "estrogenSurge",
            sourceSystem: Canonicals.healthKitOvulationTestResult
        ),
        AbsorptionCase(
            identifier: .pregnancyTestResult,
            value: HKCategoryValuePregnancyTestResult.positive.rawValue,
            measurement: HealthKitMeasurementCatalog.pregnancyTestResult,
            sharedCode: "positive",
            sourceCode: "positive",
            sourceSystem: Canonicals.healthKitTestResult
        ),
        AbsorptionCase(
            identifier: .progesteroneTestResult,
            value: HKCategoryValueProgesteroneTestResult.indeterminate.rawValue,
            measurement: HealthKitMeasurementCatalog.progesteroneTestResult,
            sharedCode: "indeterminate",
            sourceCode: "indeterminate",
            sourceSystem: Canonicals.healthKitTestResult
        )
    ]

    private let converter = HealthKitConverter()
    private let timestamp = Date(timeIntervalSince1970: 1_787_148_600)

    private var context: HealthKitConversionContext {
        HealthKitConversionContext(
            subject: Reference(reference: "Patient/example"),
            converter: HealthKitApplication(
                name: "Example Study",
                bundleIdentifier: "org.grovealliance.example-study",
                version: "2.0.0 (42)"
            ),
            graphIdentifierSystem: "https://study.example.org/fhir/identifiers/mobile-graph",
            conversionInstant: timestamp
        )
    }

    private func categorySample(
        _ type: HKCategoryTypeIdentifier,
        value: Int,
        interval: TimeInterval = 1_800,
        metadata: [String: Any] = [:]
    ) -> HKCategorySample {
        HKCategorySample(
            type: HKCategoryType(type),
            value: value,
            start: timestamp,
            end: timestamp.addingTimeInterval(interval),
            metadata: metadata.isEmpty ? nil : metadata
        )
    }

    private func codings(_ observation: Observation) throws -> [Coding] {
        let value: CodeableConcept = try #require({
            guard case .codeableConcept(let concept) = observation.value else {
                return nil
            }
            return concept
        }())
        return try #require(value.coding)
    }

    @Test("Every HKCategoryValueSeverity grade absorbs into the shared severity code", arguments: severityCases)
    func symptomSeverity(testCase: SeverityCase) throws {
        let sample = categorySample(.headache, value: testCase.value.rawValue)
        let observation = try converter.convert(sample, context: context).observation
        let codings = try codings(observation)
        let contract = HealthKitMeasurementCatalog.symptomHeadache

        #expect(observation.meta?.profile == [
            Profile.healthkitSymptomHeadache,
            Profile.healthkitObservation
        ])
        #expect(codings.count == 2)
        #expect(codings[0].system?.value?.url.absoluteString == contract.resultCodeSystem)
        #expect(codings[0].code?.value?.string == testCase.sharedCode)
        #expect(codings[1].system == Canonicals.healthKitSymptomSeverity)
        #expect(codings[1].code?.value?.string == testCase.sourceCode)
        #expect(contract.allowedValues.contains(testCase.sharedCode))
    }

    @Test("Presence-only symptoms bind the two-code presence subset")
    func symptomPresence() throws {
        let present = try converter.convert(
            categorySample(.moodChanges, value: HKCategoryValuePresence.present.rawValue),
            context: context
        ).observation
        let notPresent = try converter.convert(
            categorySample(.sleepChanges, value: HKCategoryValuePresence.notPresent.rawValue),
            context: context
        ).observation

        #expect(try codings(present)[0].code?.value?.string == "present")
        #expect(try codings(present)[1].system == Canonicals.healthKitPresence)
        #expect(try codings(present)[1].code?.value?.string == "present")
        #expect(try codings(notPresent)[0].code?.value?.string == "not-present")
        #expect(try codings(notPresent)[1].code?.value?.string == "notPresent")
        #expect(HealthKitMeasurementCatalog.symptomMoodChanges.allowedValues == ["not-present", "present"])
    }

    @Test("Every absorbed enumeration keeps the Grove code primary and the source case secondary", arguments: absorptionCases)
    func categoryValueAbsorption(testCase: AbsorptionCase) throws {
        let sample = categorySample(
            testCase.identifier,
            value: testCase.value,
            metadata: testCase.requiredMetadata
        )
        let observation = try converter.convert(sample, context: context).observation
        let codings = try codings(observation)
        let expectedDisplay = testCase.measurement.resultCodes
            .first { $0.code == testCase.sharedCode }?
            .display

        #expect(codings.count == 2)
        #expect(codings[0].system?.value?.url.absoluteString == testCase.measurement.resultCodeSystem)
        #expect(codings[0].code?.value?.string == testCase.sharedCode)
        #expect(codings[0].display?.value?.string == expectedDisplay)
        #expect(codings[1].system == testCase.sourceSystem)
        #expect(codings[1].code?.value?.string == testCase.sourceCode)
        #expect(testCase.measurement.allowedValues.contains(testCase.sharedCode))
    }

    @Test(
        "Menstrual flow carries HealthKit's mandatory cycle-start metadata as a coded component",
        arguments: [(true, "cycle-start", "Cycle start"), (false, "not-cycle-start", "Not cycle start")]
    )
    func menstrualCycleStart(cycleStart: Bool, code: String, display: String) throws {
        let sample = categorySample(
            .menstrualFlow,
            value: HKCategoryValueVaginalBleeding.light.rawValue,
            metadata: [HKMetadataKeyMenstrualCycleStart: cycleStart]
        )
        let observation = try converter.convert(sample, context: context).observation
        let component = try #require(observation.component?.first)
        let componentValue: CodeableConcept = try #require({
            guard case .codeableConcept(let concept) = component.value else {
                return nil
            }
            return concept
        }())

        #expect(observation.component?.count == 1)
        #expect(component.code.coding?.count == 1)
        #expect(
            component.code.coding?.first?.system?.value?.url.absoluteString
                == "https://grovealliance.org/fhir/mobile/CodeSystem/grove-mobile-measurement"
        )
        #expect(component.code.coding?.first?.code?.value?.string == "menstrual-cycle-start")
        #expect(
            componentValue.coding?.first?.system?.value?.url.absoluteString
                == "https://grovealliance.org/fhir/mobile/CodeSystem/grove-menstrual-cycle-start"
        )
        #expect(componentValue.coding?.first?.code?.value?.string == code)
        #expect(componentValue.coding?.first?.display?.value?.string == display)
    }

    // HealthKit rejects a menstrual-flow sample without cycle-start metadata at construction, so the
    // converter's own guard is reachable only below the sample surface.
    @Test("Menstrual flow without HealthKit's mandatory cycle-start metadata fails closed")
    func menstrualCycleStartIsRequired() throws {
        let contract = HealthKitFHIRObservationContract(shared: MeasurementCatalog.menstruationFlow)
        let sampleType = HKCategoryTypeIdentifier.menstrualFlow.rawValue

        #expect(throws: HealthKitConversionError.missingRequiredMetadata(
            sampleType: sampleType,
            key: HKMetadataKeyMenstrualCycleStart
        )) {
            try HealthKitConverter.menstrualCycleStartComponent(
                metadata: [:],
                sampleType: sampleType,
                contract: contract
            )
        }
        #expect(throws: HealthKitConversionError.unsupportedMetadataValue(
            key: HKMetadataKeyMenstrualCycleStart,
            value: "yes"
        )) {
            try HealthKitConverter.menstrualCycleStartComponent(
                metadata: [HKMetadataKeyMenstrualCycleStart: "yes"],
                sampleType: sampleType,
                contract: contract
            )
        }
    }

    @Test("Interval flags emit their one fixed result code")
    func fixedResultCodes() throws {
        let pregnancy = try converter.convert(
            categorySample(.pregnancy, value: HKCategoryValue.notApplicable.rawValue),
            context: context
        ).observation
        let lactation = try converter.convert(
            categorySample(.lactation, value: HKCategoryValue.notApplicable.rawValue),
            context: context
        ).observation
        let spotting = try converter.convert(
            categorySample(.intermenstrualBleeding, value: HKCategoryValue.notApplicable.rawValue),
            context: context
        ).observation

        #expect(try codings(pregnancy).map { $0.code?.value?.string } == ["pregnant"])
        #expect(try codings(lactation).map { $0.code?.value?.string } == ["lactating"])
        #expect(try codings(spotting).map { $0.code?.value?.string } == ["present"])
    }

    @Test(
        "Sexual activity reports protection only when the source states it",
        arguments: [
            ([HKMetadataKeySexualActivityProtectionUsed: true], "protected"),
            ([HKMetadataKeySexualActivityProtectionUsed: false], "unprotected"),
            ([:], "unknown")
        ]
    )
    func sexualActivityProtection(metadata: [String: Bool], expected: String) throws {
        let sample = categorySample(
            .sexualActivity,
            value: HKCategoryValue.notApplicable.rawValue,
            metadata: metadata
        )
        let observation = try converter.convert(sample, context: context).observation

        #expect(try codings(observation).first?.code?.value?.string == expected)
    }

    @Test("Interval sessions emit the Period duration in the profile's unit")
    func sessionDurations() throws {
        let mindful = try converter.convert(
            categorySample(.mindfulSession, value: HKCategoryValue.notApplicable.rawValue, interval: 600),
            context: context
        ).observation
        let handwashing = try converter.convert(
            categorySample(.handwashingEvent, value: HKCategoryValue.notApplicable.rawValue, interval: 22),
            context: context
        ).observation

        func quantity(_ observation: Observation) throws -> Quantity {
            try #require({
                guard case .quantity(let quantity) = observation.value else {
                    return nil
                }
                return quantity
            }())
        }

        #expect(try quantity(mindful).code?.value?.string == "min")
        #expect(try quantity(mindful).value?.value?.decimal.description == "10")
        #expect(try quantity(handwashing).code?.value?.string == "s")
        #expect(try quantity(handwashing).value?.value?.decimal.description == "22")
    }

    /// HealthKit raises `_HKObjectValidationFailureException` when an out-of-range category value
    /// is used to build a sample, so the converter's fail-closed arm is exercised through the
    /// absorption tables rather than through an impossible sample.
    @Test("Every absorbed enumeration admits exactly its published result codes", arguments: absorptionCases)
    func absorptionTablesStayInsideTheirValueSets(testCase: AbsorptionCase) {
        #expect(testCase.measurement.resultCodes.map(\.code) == testCase.measurement.allowedValues)
        #expect(testCase.measurement.allowedValues.contains(testCase.sharedCode))
    }
}

#endif
