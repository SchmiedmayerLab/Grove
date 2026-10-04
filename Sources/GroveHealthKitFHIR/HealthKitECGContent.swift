//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveFHIRContract
import HealthKit
import ModelsR4


/// The parts of an ECG's two Observations that every ECG shares, compiled once from the generated ECG claim.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitECGContent: Sendable {
    /// The waveform's code, which the claim does not state.
    private static let waveformCode = CodingContract(system: "http://loinc.org", code: "11524-6", display: "EKG study")

    /// The waveform Observation before its effective time, ECG extensions, interpretation, method, voltages and members.
    let waveform: Observation
    /// The code of the waveform's voltage component: the lead the claim reads.
    let lead: CodeableConcept
    /// The origin of the voltage SampledData: zero in the claim's voltage unit.
    let voltageOrigin: Quantity
    /// The interpretation of each classification the claim admits.
    let classifications: [HKElectrocardiogram.Classification: CodeableConcept]
    /// The method of each algorithm version the claim admits.
    let algorithmVersions: [Int: CodeableConcept]
    /// The average heart rate's Observation before its effective time and value.
    let averageHeartRate: Observation
    /// The average heart rate's quantity, in its measurement's unit.
    let averageHeartRateQuantity: QuantityTemplate

    /// The content of the ECG claim for the ECG source type.
    init(sourceType: HealthKitSourceType) throws(HealthKitContentDefect) {
        let claim = HealthKitElectrocardiogramClaim.self
        let measurement = claim.averageHeartRateMeasurement
        guard let heartRate = measurement.quantity else {
            throw HealthKitContentDefect("the average heart rate's measurement \(measurement.id) states no quantity")
        }
        waveform = ObservationPlan.skeleton(
            code: CodeableConcept(coding: [Coding(Self.waveformCode)]),
            sourceType: sourceType,
            profiles: claim.waveform.profiles
        )
        lead = CodeableConcept(coding: [Coding(claim.leadCode)])
        var origin = QuantityTemplate(claim.voltageQuantity).empty
        origin.value = FHIRPrimitive(FHIRDecimal(0))
        voltageOrigin = origin
        classifications = claim.classificationCodes.mapValues { CodeableConcept(coding: [Coding($0, system: claim.classificationSystem)]) }
        algorithmVersions = claim.algorithmVersionCodes.mapValues { CodeableConcept(coding: [Coding($0, system: claim.algorithmVersionSystem)]) }
        averageHeartRate = ObservationPlan.skeleton(
            code: CodeableConcept(coding: [Coding(claim.averageHeartRateCode)]),
            sourceType: sourceType,
            profiles: claim.averageHeartRate.profiles,
            category: HealthKitContentRules.category(of: measurement)
        )
        averageHeartRateQuantity = QuantityTemplate(heartRate)
    }
}

#endif
