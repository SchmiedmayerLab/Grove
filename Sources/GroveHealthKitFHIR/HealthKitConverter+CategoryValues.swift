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
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// One absorbed category value: the shared Grove code plus the exact retained source case.
    private struct HealthKitCategoryCase {
        let sharedCode: String
        let sourceCode: String
        let sourceDisplay: String
    }

    private struct HealthKitSeverityGrade {
        let sharedCode: String
        let sharedDisplay: String
        let sourceCode: String
        let sourceDisplay: String
    }

    static func severityValue(
        _ sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> CodeableConcept {
        let value = try categorySample(sample).value
        let grade: HealthKitSeverityGrade = switch value {
        case HKCategoryValueSeverity.unspecified.rawValue:
            HealthKitSeverityGrade(
                sharedCode: "present",
                sharedDisplay: "Present, severity unspecified",
                sourceCode: "unspecified",
                sourceDisplay: "Unspecified"
            )
        case HKCategoryValueSeverity.notPresent.rawValue:
            HealthKitSeverityGrade(
                sharedCode: "not-present",
                sharedDisplay: "Not present",
                sourceCode: "notPresent",
                sourceDisplay: "Not present"
            )
        case HKCategoryValueSeverity.mild.rawValue:
            HealthKitSeverityGrade(sharedCode: "mild", sharedDisplay: "Mild", sourceCode: "mild", sourceDisplay: "Mild")
        case HKCategoryValueSeverity.moderate.rawValue:
            HealthKitSeverityGrade(
                sharedCode: "moderate",
                sharedDisplay: "Moderate",
                sourceCode: "moderate",
                sourceDisplay: "Moderate"
            )
        case HKCategoryValueSeverity.severe.rawValue:
            HealthKitSeverityGrade(
                sharedCode: "severe",
                sharedDisplay: "Severe",
                sourceCode: "severe",
                sourceDisplay: "Severe"
            )
        default:
            throw HealthKitConversionError.unsupportedSampleValue(
                sampleType: sample.sampleType.identifier,
                value: value
            )
        }
        return CodeableConcept(coding: [
            Coding(
                code: grade.sharedCode.asFHIRStringPrimitive(),
                display: grade.sharedDisplay.asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: try resultCodeSystem(contract)))
            ),
            Coding(
                code: grade.sourceCode.asFHIRStringPrimitive(),
                display: grade.sourceDisplay.asFHIRStringPrimitive(),
                system: Canonicals.healthKitSymptomSeverity
            )
        ])
    }

    static func presenceValue(
        _ sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> CodeableConcept {
        let value = try categorySample(sample).value
        let grade: HealthKitSeverityGrade = switch value {
        case HKCategoryValuePresence.present.rawValue:
            HealthKitSeverityGrade(
                sharedCode: "present",
                sharedDisplay: "Present, severity unspecified",
                sourceCode: "present",
                sourceDisplay: "Present"
            )
        case HKCategoryValuePresence.notPresent.rawValue:
            HealthKitSeverityGrade(
                sharedCode: "not-present",
                sharedDisplay: "Not present",
                sourceCode: "notPresent",
                sourceDisplay: "Not present"
            )
        default:
            throw HealthKitConversionError.unsupportedSampleValue(
                sampleType: sample.sampleType.identifier,
                value: value
            )
        }
        return CodeableConcept(coding: [
            Coding(
                code: grade.sharedCode.asFHIRStringPrimitive(),
                display: grade.sharedDisplay.asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: try resultCodeSystem(contract)))
            ),
            Coding(
                code: grade.sourceCode.asFHIRStringPrimitive(),
                display: grade.sourceDisplay.asFHIRStringPrimitive(),
                system: Canonicals.healthKitPresence
            )
        ])
    }

    static func absorbedCategoryValue(
        _ sample: HKSample,
        absorption: HealthKitFHIRCategoryValueAbsorption,
        contract: HealthKitFHIRObservationContract
    ) throws -> CodeableConcept {
        let value = try categorySample(sample).value
        guard let absorbed = absorbedCase(absorption, value: value) else {
            throw HealthKitConversionError.unsupportedSampleValue(
                sampleType: sample.sampleType.identifier,
                value: value
            )
        }
        return CodeableConcept(coding: [
            try sharedResultCoding(absorbed.sharedCode, contract: contract),
            Coding(
                code: absorbed.sourceCode.asFHIRStringPrimitive(),
                display: absorbed.sourceDisplay.asFHIRStringPrimitive(),
                system: sourceSystem(for: absorption)
            )
        ])
    }

    static func fixedCodeValue(
        _ sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> CodeableConcept {
        try requireNotApplicableValue(sample)
        guard let fixed = contract.measurementResultCodes.first else {
            throw HealthKitConversionError.missingNormativeCode(contract.id)
        }
        return CodeableConcept(coding: [try sharedResultCoding(fixed.code, contract: contract)])
    }

    static func notificationValue(
        _ sample: HKSample,
        values: [Int: String],
        contract: HealthKitFHIRObservationContract
    ) throws -> CodeableConcept {
        // A notification whose HealthKit type carries no value states its occurrence and nothing more,
        // so the contract's single published code is the result.
        guard !values.isEmpty else {
            return try fixedCodeValue(sample, contract: contract)
        }
        let value = try categorySample(sample).value
        guard let code = values[value] else {
            throw HealthKitConversionError.unsupportedSampleValue(
                sampleType: contract.id,
                value: value
            )
        }
        return CodeableConcept(coding: [try sharedResultCoding(code, contract: contract)])
    }

    static func sexualActivityValue(
        _ sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> CodeableConcept {
        try requireNotApplicableValue(sample)
        let code: String
        switch sample.metadata?[HKMetadataKeySexualActivityProtectionUsed] {
        case nil:
            code = "unknown"
        case let protectionUsed as Bool:
            code = protectionUsed ? "protected" : "unprotected"
        case let other?:
            throw HealthKitConversionError.unsupportedMetadataValue(
                key: HKMetadataKeySexualActivityProtectionUsed,
                value: String(describing: other)
            )
        }
        return CodeableConcept(coding: [try sharedResultCoding(code, contract: contract)])
    }

    static func sessionDurationValue(
        _ sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> Quantity {
        try requireNotApplicableValue(sample)
        let quantityContract = try quantityContract(contract)
        let seconds = sample.endDate.timeIntervalSince(sample.startDate)
        let value: Double = switch quantityContract.code {
        case "s":
            seconds
        case "min":
            seconds / 60
        default:
            throw HealthKitConversionError.invalidValue
        }
        return try fhirQuantity(value: value, contract: quantityContract)
    }

    private static func requireNotApplicableValue(_ sample: HKSample) throws {
        let value = try categorySample(sample).value
        guard value == HKCategoryValue.notApplicable.rawValue else {
            throw HealthKitConversionError.unsupportedSampleValue(
                sampleType: sample.sampleType.identifier,
                value: value
            )
        }
    }

    /// The emitted shared coding always restates the exact generated result code and display.
    private static func sharedResultCoding(
        _ code: String,
        contract: HealthKitFHIRObservationContract
    ) throws -> Coding {
        guard let resultCode = contract.measurementResultCodes.first(where: { $0.code == code }) else {
            throw HealthKitConversionError.missingNormativeCode(contract.id)
        }
        return Coding(
            code: resultCode.code.asFHIRStringPrimitive(),
            display: resultCode.display.asFHIRStringPrimitive(),
            system: FHIRPrimitive(FHIRURI(stringLiteral: try resultCodeSystem(contract)))
        )
    }

    private static func sourceSystem(
        for absorption: HealthKitFHIRCategoryValueAbsorption
    ) -> FHIRPrimitive<FHIRURI> {
        switch absorption {
        case .appetiteChanges:
            Canonicals.healthKitAppetiteChanges
        case .appleStandHour:
            Canonicals.healthKitAppleStandHourValue
        case .cervicalMucusQuality:
            Canonicals.healthKitCervicalMucusQuality
        case .contraceptive:
            Canonicals.healthKitContraceptive
        case .ovulationTestResult:
            Canonicals.healthKitOvulationTestResult
        case .pregnancyTestResult, .progesteroneTestResult:
            Canonicals.healthKitTestResult
        case .vaginalBleeding:
            Canonicals.healthKitVaginalBleeding
        }
    }

    private static func absorbedCase(
        _ absorption: HealthKitFHIRCategoryValueAbsorption,
        value: Int
    ) -> HealthKitCategoryCase? {
        switch absorption {
        case .appetiteChanges:
            appetiteChangesCase(value)
        case .appleStandHour:
            appleStandHourCase(value)
        case .cervicalMucusQuality:
            cervicalMucusQualityCase(value)
        case .contraceptive:
            contraceptiveCase(value)
        case .ovulationTestResult:
            ovulationTestResultCase(value)
        case .pregnancyTestResult, .progesteroneTestResult:
            testResultCase(value)
        case .vaginalBleeding:
            vaginalBleedingCase(value)
        }
    }

    private static func appetiteChangesCase(_ value: Int) -> HealthKitCategoryCase? {
        switch value {
        case HKCategoryValueAppetiteChanges.unspecified.rawValue:
            HealthKitCategoryCase(
                sharedCode: "change-unspecified",
                sourceCode: "unspecified",
                sourceDisplay: "Unspecified"
            )
        case HKCategoryValueAppetiteChanges.noChange.rawValue:
            HealthKitCategoryCase(sharedCode: "no-change", sourceCode: "noChange", sourceDisplay: "No change")
        case HKCategoryValueAppetiteChanges.decreased.rawValue:
            HealthKitCategoryCase(sharedCode: "decreased", sourceCode: "decreased", sourceDisplay: "Decreased")
        case HKCategoryValueAppetiteChanges.increased.rawValue:
            HealthKitCategoryCase(sharedCode: "increased", sourceCode: "increased", sourceDisplay: "Increased")
        default:
            nil
        }
    }

    private static func appleStandHourCase(_ value: Int) -> HealthKitCategoryCase? {
        switch value {
        case HKCategoryValueAppleStandHour.stood.rawValue:
            HealthKitCategoryCase(sharedCode: "stood", sourceCode: "stood", sourceDisplay: "Stood")
        case HKCategoryValueAppleStandHour.idle.rawValue:
            HealthKitCategoryCase(sharedCode: "idle", sourceCode: "idle", sourceDisplay: "Idle")
        default:
            nil
        }
    }

    private static func cervicalMucusQualityCase(_ value: Int) -> HealthKitCategoryCase? {
        switch value {
        case HKCategoryValueCervicalMucusQuality.dry.rawValue:
            HealthKitCategoryCase(sharedCode: "dry", sourceCode: "dry", sourceDisplay: "Dry")
        case HKCategoryValueCervicalMucusQuality.sticky.rawValue:
            HealthKitCategoryCase(sharedCode: "sticky", sourceCode: "sticky", sourceDisplay: "Sticky")
        case HKCategoryValueCervicalMucusQuality.creamy.rawValue:
            HealthKitCategoryCase(sharedCode: "creamy", sourceCode: "creamy", sourceDisplay: "Creamy")
        case HKCategoryValueCervicalMucusQuality.watery.rawValue:
            HealthKitCategoryCase(sharedCode: "watery", sourceCode: "watery", sourceDisplay: "Watery")
        case HKCategoryValueCervicalMucusQuality.eggWhite.rawValue:
            HealthKitCategoryCase(sharedCode: "egg-white", sourceCode: "eggWhite", sourceDisplay: "Egg white")
        default:
            nil
        }
    }

    private static func contraceptiveCase(_ value: Int) -> HealthKitCategoryCase? {
        switch value {
        case HKCategoryValueContraceptive.unspecified.rawValue:
            HealthKitCategoryCase(sharedCode: "unspecified", sourceCode: "unspecified", sourceDisplay: "Unspecified")
        case HKCategoryValueContraceptive.implant.rawValue:
            HealthKitCategoryCase(sharedCode: "implant", sourceCode: "implant", sourceDisplay: "Implant")
        case HKCategoryValueContraceptive.injection.rawValue:
            HealthKitCategoryCase(sharedCode: "injection", sourceCode: "injection", sourceDisplay: "Injection")
        case HKCategoryValueContraceptive.intrauterineDevice.rawValue:
            HealthKitCategoryCase(
                sharedCode: "intrauterine-device",
                sourceCode: "intrauterineDevice",
                sourceDisplay: "Intrauterine device"
            )
        case HKCategoryValueContraceptive.intravaginalRing.rawValue:
            HealthKitCategoryCase(
                sharedCode: "intravaginal-ring",
                sourceCode: "intravaginalRing",
                sourceDisplay: "Intravaginal ring"
            )
        case HKCategoryValueContraceptive.oral.rawValue:
            HealthKitCategoryCase(sharedCode: "oral", sourceCode: "oral", sourceDisplay: "Oral")
        case HKCategoryValueContraceptive.patch.rawValue:
            HealthKitCategoryCase(sharedCode: "patch", sourceCode: "patch", sourceDisplay: "Patch")
        default:
            nil
        }
    }

    private static func ovulationTestResultCase(_ value: Int) -> HealthKitCategoryCase? {
        switch value {
        case HKCategoryValueOvulationTestResult.negative.rawValue:
            HealthKitCategoryCase(sharedCode: "negative", sourceCode: "negative", sourceDisplay: "Negative")
        case HKCategoryValueOvulationTestResult.luteinizingHormoneSurge.rawValue:
            HealthKitCategoryCase(
                sharedCode: "luteinizing-hormone-surge",
                sourceCode: "luteinizingHormoneSurge",
                sourceDisplay: "Luteinizing hormone surge"
            )
        case HKCategoryValueOvulationTestResult.indeterminate.rawValue:
            HealthKitCategoryCase(
                sharedCode: "indeterminate",
                sourceCode: "indeterminate",
                sourceDisplay: "Indeterminate"
            )
        case HKCategoryValueOvulationTestResult.estrogenSurge.rawValue:
            HealthKitCategoryCase(
                sharedCode: "high-fertility",
                sourceCode: "estrogenSurge",
                sourceDisplay: "Estrogen surge"
            )
        default:
            nil
        }
    }

    private static func testResultCase(_ value: Int) -> HealthKitCategoryCase? {
        switch value {
        case HKCategoryValuePregnancyTestResult.negative.rawValue:
            HealthKitCategoryCase(sharedCode: "negative", sourceCode: "negative", sourceDisplay: "Negative")
        case HKCategoryValuePregnancyTestResult.positive.rawValue:
            HealthKitCategoryCase(sharedCode: "positive", sourceCode: "positive", sourceDisplay: "Positive")
        case HKCategoryValuePregnancyTestResult.indeterminate.rawValue:
            HealthKitCategoryCase(
                sharedCode: "indeterminate",
                sourceCode: "indeterminate",
                sourceDisplay: "Indeterminate"
            )
        default:
            nil
        }
    }

    private static func vaginalBleedingCase(_ value: Int) -> HealthKitCategoryCase? {
        switch value {
        case HKCategoryValueVaginalBleeding.unspecified.rawValue:
            HealthKitCategoryCase(sharedCode: "unspecified", sourceCode: "unspecified", sourceDisplay: "Unspecified")
        case HKCategoryValueVaginalBleeding.light.rawValue:
            HealthKitCategoryCase(sharedCode: "light", sourceCode: "light", sourceDisplay: "Light")
        case HKCategoryValueVaginalBleeding.medium.rawValue:
            HealthKitCategoryCase(sharedCode: "medium", sourceCode: "medium", sourceDisplay: "Medium")
        case HKCategoryValueVaginalBleeding.heavy.rawValue:
            HealthKitCategoryCase(sharedCode: "heavy", sourceCode: "heavy", sourceDisplay: "Heavy")
        case HKCategoryValueVaginalBleeding.none.rawValue:
            HealthKitCategoryCase(sharedCode: "none", sourceCode: "none", sourceDisplay: "None")
        default:
            nil
        }
    }
}

#endif
