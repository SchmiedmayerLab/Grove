//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    private static let observationCategory: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/observation-category"
    private static let measurementDisplays = [
        "blood-pressure": "Blood pressure panel with all children optional",
        "body-height": "Body height",
        "body-mass-index": "Body mass index (BMI) [Ratio]",
        "body-temperature": "Body temperature",
        "body-weight": "Body weight",
        "distance": "Distance traveled",
        "heart-rate": "Heart rate",
        "oxygen-saturation": "Oxygen saturation in Arterial blood",
        "respiratory-rate": "Respiratory rate"
    ]

    static func observation(
        for sample: HKSample,
        binding: HealthKitFHIRBinding,
        graphContext: HealthKitGraphContext
    ) throws -> Observation {
        let contract = binding.contract
        let primaryCoding = Coding(
            code: contract.code.code.asFHIRStringPrimitive(),
            display: measurementDisplay(contract).asFHIRStringPrimitive(),
            system: FHIRPrimitive(FHIRURI(stringLiteral: contract.code.system))
        )
        let requiredCodings = contract.requiredCodings.map { coding in
            Coding(
                code: coding.code.asFHIRStringPrimitive(),
                display: coding.display?.asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: coding.system))
            )
        }
        var observation = Observation(
            code: CodeableConcept(coding: [primaryCoding] + requiredCodings),
            status: FHIRPrimitive(.final)
        )
        applySourceTypeLineage(sample.sampleType.identifier, to: &observation)
        observation.meta = Meta(profile: contract.profiles)
        observation.subject = graphContext.subject
        // HealthKit has no per-object availability time. Conversion time belongs on Provenance.
        observation.category = category(for: contract.id).map { [CodeableConcept(coding: [$0])] }
        observation.method = contract.method.map { method in
            CodeableConcept(coding: [
                Coding(
                    code: method.code.asFHIRStringPrimitive(),
                    display: method.display.asFHIRStringPrimitive(),
                    system: Canonicals.aggregationMethodCodeSystem
                )
            ])
        }
        try applyEffective(to: &observation, sample: sample, contract: contract)
        try applyResult(to: &observation, sample: sample, binding: binding, contract: contract)
        try applyHeartRateMotionContext(to: &observation, sample: sample)
        try applyInsulinDeliveryReason(to: &observation, sample: sample)
        try applyMenstrualCycleStart(to: &observation, sample: sample, contract: contract)
        applyGraphContext(
            to: &observation,
            graphContext: graphContext,
            wasUserEntered: (sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true
        )
        return observation
    }

    private static func applyResult(
        to observation: inout Observation,
        sample: HKSample,
        binding: HealthKitFHIRBinding,
        contract: HealthKitFHIRObservationContract
    ) throws {
        switch binding {
        case .bloodPressure:
            guard let correlation = sample as? HKCorrelation else {
                throw HealthKitValueFailure.shapeInvalid
            }
            observation.component = try bloodPressureComponents(correlation, contract: contract)
            return
        case .workout:
            observation.component = try workoutComponents(try workoutSample(sample))
        case .stateOfMind:
            observation.component = try stateOfMindComponents(try stateOfMindSample(sample))
        case .quantity, .percent, .sessionRate, .sessionDuration, .assessmentScore, .severity,
             .presence, .categoryValue, .fixedCode, .notification, .sexualActivity, .sleepStage:
            break
        }
        observation.value = try result(for: binding, sample: sample, contract: contract)
    }

    // The closed binding dispatch is intentionally exhaustive.
    // swiftlint:disable:next cyclomatic_complexity
    private static func result(
        for binding: HealthKitFHIRBinding,
        sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> Observation.ValueX {
        switch binding {
        case let .quantity(_, unit):
            .quantity(try fhirQuantity(
                value: try quantitySample(sample).quantity.doubleValue(for: unit),
                contract: quantityContract(contract)
            ))
        case .percent:
            .quantity(try fhirQuantity(
                value: try quantitySample(sample).quantity.doubleValue(for: .percent()) * 100,
                contract: quantityContract(contract)
            ))
        case .sessionRate:
            .quantity(try sessionRateValue(sample, contract: contract))
        case .sessionDuration:
            .quantity(try sessionDurationValue(sample, contract: contract))
        case .assessmentScore:
            .quantity(try assessmentScoreValue(sample, contract: contract))
        case .sleepStage:
            .codeableConcept(try sleepStageValue(sample, contract: contract))
        case .severity:
            .codeableConcept(try severityValue(sample, contract: contract))
        case .presence:
            .codeableConcept(try presenceValue(sample, contract: contract))
        case let .categoryValue(_, absorption):
            .codeableConcept(try absorbedCategoryValue(sample, absorption: absorption, contract: contract))
        case .fixedCode:
            .codeableConcept(try fixedCodeValue(sample, contract: contract))
        case let .notification(_, values):
            .codeableConcept(try notificationValue(sample, values: values, contract: contract))
        case .sexualActivity:
            .codeableConcept(try sexualActivityValue(sample, contract: contract))
        case .bloodPressure:
            throw HealthKitValueFailure.shapeInvalid
        case .workout:
            .codeableConcept(try workoutValue(try workoutSample(sample)))
        case .stateOfMind:
            .quantity(try stateOfMindValue(try stateOfMindSample(sample)))
        }
    }

    private static func applyEffective(
        to observation: inout Observation,
        sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws {
        let sourceTimeZone = try sourceTimeZone(metadata: sample.metadata ?? [:])
        switch contract.effective {
        case .dateTime, .dateTimeOrPeriod:
            // Scalar HealthKit samples stay point-in-time even when the shared profile also admits
            // a Period for a separately modeled aggregate such as ECG average heart rate.
            observation.effective = .dateTime(try effectiveDateTime(sample.startDate, sourceTimeZone: sourceTimeZone))
        case .period:
            guard sample.endDate > sample.startDate else {
                throw HealthKitValueFailure.effectivePeriodInvalid
            }
            observation.effective = .period(try effectivePeriod(
                start: sample.startDate,
                end: sample.endDate,
                sourceTimeZone: sourceTimeZone
            ))
        }
    }

    /// An effective instant in the source's own time zone, which also travels as the `timezone`
    /// extension, or in UTC when the source names none.
    static func effectiveDateTime(_ date: Date, sourceTimeZone: TimeZone?) throws -> FHIRPrimitive<DateTime> {
        var dateTime = FHIRPrimitive(try HealthKitMobileCanonicalization.effectiveDateTime(date, timeZone: sourceTimeZone ?? .utc))
        if let sourceTimeZone {
            dateTime.append(
                extension: Extension(url: Canonicals.timezone, value: .code(sourceTimeZone.identifier.asFHIRStringPrimitive())),
                behaviour: .replace
            )
        }
        return dateTime
    }

    static func effectivePeriod(start: Date, end: Date, sourceTimeZone: TimeZone?) throws -> Period {
        Period(
            end: try effectiveDateTime(end, sourceTimeZone: sourceTimeZone),
            start: try effectiveDateTime(start, sourceTimeZone: sourceTimeZone)
        )
    }

    private static func measurementDisplay(_ contract: HealthKitFHIRObservationContract) -> String {
        contract.code.display ?? measurementDisplays[contract.id, default: contract.id]
    }

    private static func category(for id: String) -> Coding? {
        let code: (String, String)? = switch id {
        case "heart-rate", "resting-heart-rate", "body-weight", "blood-pressure", "body-temperature",
             "respiratory-rate", "oxygen-saturation", "body-height", "body-mass-index":
            ("vital-signs", "Vital Signs")
        case "step-count", "distance", "active-energy", "sleep-stage":
            ("activity", "Activity")
        default:
            nil
        }
        return code.map { code, display in
            Coding(
                code: code.asFHIRStringPrimitive(),
                display: display.asFHIRStringPrimitive(),
                system: observationCategory
            )
        }
    }

    private static func applyHeartRateMotionContext(
        to observation: inout Observation,
        sample: HKSample
    ) throws {
        guard sample.sampleType.identifier == HKQuantityTypeIdentifier.heartRate.rawValue,
              let raw = sample.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber else {
            return
        }
        let coding: Coding = switch raw.intValue {
        case 0:
            Coding(code: "not-set", display: "Not Set", system: Canonicals.healthKitHeartRateMotionContext)
        case 1:
            Coding(code: "sedentary", display: "Sedentary", system: Canonicals.healthKitHeartRateMotionContext)
        case 2:
            Coding(code: "active", display: "Active", system: Canonicals.healthKitHeartRateMotionContext)
        default:
            throw HealthKitValueFailure.unsupportedMetadataValue(.heartRateMotionContext)
        }
        let component = ObservationComponent(
            code: CodeableConcept(coding: [
                Coding(
                    code: HKMetadataKeyHeartRateMotionContext.asFHIRStringPrimitive(),
                    display: "Heart Rate Motion Context".asFHIRStringPrimitive(),
                    system: Canonicals.healthKitMetadataKey
                )
            ]),
            value: .codeableConcept(CodeableConcept(coding: [coding]))
        )
        observation.component = (observation.component ?? []) + [component]
    }

    private static func applyInsulinDeliveryReason(
        to observation: inout Observation,
        sample: HKSample
    ) throws {
        guard sample.sampleType.identifier == HKQuantityTypeIdentifier.insulinDelivery.rawValue else {
            return
        }
        guard let raw = sample.metadata?[HKMetadataKeyInsulinDeliveryReason] as? NSNumber else {
            throw HealthKitValueFailure.requiredMetadataMissing(.insulinDeliveryReason)
        }
        let coding: Coding = switch raw.intValue {
        case HKInsulinDeliveryReason.basal.rawValue:
            Coding(code: "basal", display: "Basal", system: Canonicals.healthKitInsulinDeliveryReason)
        case HKInsulinDeliveryReason.bolus.rawValue:
            Coding(code: "bolus", display: "Bolus", system: Canonicals.healthKitInsulinDeliveryReason)
        default:
            throw HealthKitValueFailure.unsupportedMetadataValue(.insulinDeliveryReason)
        }
        let component = ObservationComponent(
            code: CodeableConcept(coding: [
                Coding(
                    code: HKMetadataKeyInsulinDeliveryReason.asFHIRStringPrimitive(),
                    display: "Insulin Delivery Reason".asFHIRStringPrimitive(),
                    system: Canonicals.healthKitMetadataKey
                )
            ]),
            value: .codeableConcept(CodeableConcept(coding: [coding]))
        )
        observation.component = (observation.component ?? []) + [component]
    }

    private static func applyMenstrualCycleStart(
        to observation: inout Observation,
        sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws {
        guard sample.sampleType.identifier == HKCategoryTypeIdentifier.menstrualFlow.rawValue else {
            return
        }
        let component = try menstrualCycleStartComponent(
            metadata: sample.metadata ?? [:],
            contract: contract
        )
        observation.component = (observation.component ?? []) + [component]
    }

    static func menstrualCycleStartComponent(
        metadata: [String: Any],
        contract: HealthKitFHIRObservationContract
    ) throws -> ObservationComponent {
        guard let contractComponent = contract.components.first(where: { $0.id == "cycleStart" }),
              let resultCodeSystem = contractComponent.resultCodeSystem else {
            throw HealthKitValueFailure.requiredComponentMissing(component: "cycleStart")
        }
        let cycleStart: Bool
        switch metadata[HKMetadataKeyMenstrualCycleStart] {
        case nil:
            throw HealthKitValueFailure.requiredMetadataMissing(.menstrualCycleStart)
        case let value as Bool:
            cycleStart = value
        case .some:
            throw HealthKitValueFailure.unsupportedMetadataValue(.menstrualCycleStart)
        }
        let code = cycleStart ? "cycle-start" : "not-cycle-start"
        guard let resultCode = contractComponent.resultCodes.first(where: { $0.code == code }) else {
            throw HealthKitValueFailure.missingNormativeCode
        }
        return ObservationComponent(
            code: CodeableConcept(coding: [
                Coding(
                    code: contractComponent.code.asFHIRStringPrimitive(),
                    system: FHIRPrimitive(FHIRURI(stringLiteral: contractComponent.system))
                )
            ]),
            value: .codeableConcept(CodeableConcept(coding: [
                Coding(
                    code: resultCode.code.asFHIRStringPrimitive(),
                    display: resultCode.display.asFHIRStringPrimitive(),
                    system: FHIRPrimitive(FHIRURI(stringLiteral: resultCodeSystem))
                )
            ]))
        )
    }

    static func applyManualRecordingMethod(to observation: inout Observation) {
        observation.append(
            extension: Extension(
                url: Canonicals.recordingMethod,
                value: .coding(Coding(
                    code: "manual-entry",
                    display: "Manual entry",
                    system: Canonicals.recordingMethodCodeSystem
                ))
            ),
            behaviour: .replace
        )
    }
}

#endif
