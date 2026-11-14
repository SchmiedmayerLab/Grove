//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import ModelsR4


/// Converts already acquired Withings records. Each distinct source token yields its own exchange record.
public enum WithingsFHIR {
    /// A pressure pair is atomic within this group. A heart rate in the same group remains a separate record.
    public static func convert(
        _ group: WithingsMeasureGroup,
        context: ProviderConversionContext
    ) throws -> [ProviderConversionResult] {
        var byType: [Int: WithingsMeasureGroup.Measure] = [:]
        for measure in group.measures {
            guard byType.updateValue(measure, forKey: measure.type) == nil else {
                throw ProviderConversionError.conflictingMeasurement(measure.type)
            }
        }
        var results: [ProviderConversionResult] = []
        if byType[9] != nil || byType[10] != nil {
            results.append(try bloodPressure(group, measures: byType, context: context))
        }
        for type in byType.keys.sorted() where type != 9 && type != 10 {
            guard let measure = byType[type] else { continue }
            let token = "getmeas:\(type)"
            let outputs: [ExchangeOutputDraft]
            let omissions: [ProviderConversionResult.Omission]
            if let contract = contract(type) {
                outputs = [
                    try ProviderObservation.scalar(
                        measure.scaled(additionalExponent: type == 4 ? 2 : 0),
                        contract: contract,
                        adapter: Profile.withingsObservation,
                        effective: .instant(group.date),
                        context: context
                    )
                ]
                omissions = []
            } else {
                outputs = []
                let reason = omissionReason(type)
                omissions = [.init(sourceToken: token, element: "measure.value", reason: reason)]
            }
            results.append(
                try ProviderObservation.assemble(
                    provider: .withings,
                    token: token,
                    nativeID: group.id,
                    outputs: outputs,
                    omissions: omissions,
                    context: context
                )
            )
        }
        return results
    }

    private static func bloodPressure(
        _ group: WithingsMeasureGroup,
        measures: [Int: WithingsMeasureGroup.Measure],
        context: ProviderConversionContext
    ) throws -> ProviderConversionResult {
        let token = "getmeas:9+10"
        guard let diastolic = measures[9], let systolic = measures[10] else {
            return try ProviderObservation.assemble(
                provider: .withings,
                token: token,
                nativeID: group.id,
                outputs: [],
                omissions: [.init(sourceToken: token, element: "measure-group", reason: .missingRequiredEvidence)],
                context: context
            )
        }
        let contract = MeasurementCatalog.bloodPressure
        var observation = try ProviderObservation.base(
            contract,
            adapter: Profile.withingsObservation,
            effective: .instant(group.date),
            context: context
        )
        observation.component = try contract.components.map { component in
            guard let quantity = component.quantity else { throw ProviderConversionError.invalidContract(component.id) }
            let value: Decimal
            switch component.id {
            case "systolic": value = try systolic.scaled()
            case "diastolic": value = try diastolic.scaled()
            default: throw ProviderConversionError.invalidContract(component.id)
            }
            return try ObservationComponent(
                code: CodeableConcept(coding: [Coding(code: component.code.asFHIRStringPrimitive(), system: component.system.asFHIRURIPrimitive())]),
                value: .quantity(ProviderObservation.quantity(value, contract: quantity))
            )
        }
        return try ProviderObservation.assemble(
            provider: .withings,
            token: token,
            nativeID: group.id,
            outputs: [.init(role: "blood-pressure-panel", resource: .observation(observation))],
            context: context
        )
    }
}


extension WithingsFHIR {
    static func omissionReason(_ type: Int) -> ProviderConversionResult.Omission.Reason {
        switch type {
        case 130, 139, 135...138: .missingRequiredEvidence
        case 196: .sourceDefinitionConflict
        default: .notAdmitted
        }
    }

    // Each provider type selects one generated semantic contract.
    // swiftlint:disable:next cyclomatic_complexity
    static func contract(_ type: Int) -> MeasurementContract? {
        switch type {
        case 1: MeasurementCatalog.bodyWeight
        case 4: MeasurementCatalog.bodyHeight
        case 5: MeasurementCatalog.leanBodyMass
        case 6: MeasurementCatalog.bodyFatPercentage
        case 8: WithingsMeasurementCatalog.bodyFatMass
        case 11: MeasurementCatalog.heartRate
        case 54: MeasurementCatalog.oxygenSaturation
        case 71: MeasurementCatalog.bodyTemperature
        case 73: MeasurementCatalog.skinTemperature
        case 76: WithingsMeasurementCatalog.muscleMass
        case 77: MeasurementCatalog.bodyWaterMass
        case 88: MeasurementCatalog.boneMass
        case 91: WithingsMeasurementCatalog.withingsPulseWaveVelocity
        case 123: MeasurementCatalog.vo2Max
        case 155: WithingsMeasurementCatalog.withingsVascularAge
        case 167: WithingsMeasurementCatalog.withingsNerveHealthScore
        case 168: WithingsMeasurementCatalog.extracellularWaterMass
        case 169: WithingsMeasurementCatalog.intracellularWaterMass
        case 170: WithingsMeasurementCatalog.withingsVisceralFatIndex
        default: nil
        }
    }
}
