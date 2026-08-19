//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import FHIRModelsExtensions
public import Foundation
import GroveHealthKit
import GroveHealthKitFHIRMacros
public import HealthKit
public import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKElectrocardiogram {
    /// The `Symptoms` contain related `HKCategoryType` instances coded as `HKCategoryValueSeverity` enums related to an `HKElectrocardiogram`.
    public typealias Symptoms = [HKCategoryType: HKCategoryValueSeverity]
    /// The raw voltage measurements are defined as `HKQuantity` samples that are correlating to a specific measurement time.
    ///
    /// The voltage measurements must be sorted by time interval.
    public typealias VoltageMeasurements = [(time: TimeInterval, value: HKQuantity)]
    
    
    /// Creates an FHIR observation incorporating additional `Symptoms` and`VoltageMeasurements` collected in HealthKit.
    /// If you do not need `HKElectrocardiogram` specific context added you can use the generic `observation` extension on `HKSample`.
    ///
    /// - Parameters:
    ///   - subject: The patient the electrocardiogram was recorded for.
    ///   - symptoms: The ``Symptoms`` that should be encoded in the FHIR observation.
    ///   - voltageMeasurements: the ECG's associated raw voltage measurements.
    ///   - mapping: The ``SampleTypesFHIRMapping`` used to populate the FHIR observation.
    ///   - issuedDate: `Instant` specifying when this version of the resource was made available. Defaults to `Date.now`.
    ///   - extensions: `FHIRExtensionBuilder`s that should be applied to the resulting `Observation`.
    public func observation(
        subject: Reference,
        symptoms: Symptoms,
        voltageMeasurements: VoltageMeasurements,
        withMapping mapping: SampleTypesFHIRMapping = .default,
        issuedDate: FHIRPrimitive<Instant>? = nil,
        extensions: [any FHIRExtensionBuilderProtocol] = []
    ) throws -> Observation {
        guard var observation = try resource(
            withMapping: mapping,
            issuedDate: issuedDate,
            subject: subject,
            extensions: extensions
        ).get(if: Observation.self) else {
            throw GroveHealthKitFHIRError.notSupported
        }
        if !symptoms.isEmpty {
            try appendSymptomsComponent(to: &observation, symptoms: symptoms, mapping: mapping)
        }
        if !voltageMeasurements.isEmpty {
            try appendVoltageMeasurementsComponent(to: &observation, voltageMeasurements: voltageMeasurements, mapping: mapping.ecgTypeMapping)
        }
        return observation
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKElectrocardiogram: FHIRObservationBuildable {
    func build(_ observation: inout Observation, mapping: SampleTypesFHIRMapping) throws {
        let mapping = mapping.ecgTypeMapping
        observation.append(codings: mapping.codings)
        observation.append(categories: mapping.categories.map { CodeableConcept(coding: [$0]) })
        try appendNumberOfVoltageMeasurementsComponent(to: &observation, mapping: mapping)
        try appendSamplingFrequencyComponent(to: &observation, mapping: mapping)
        appendClassificationComponent(to: &observation, mapping: mapping)
        try appendAverageHeartRateComponent(to: &observation, mapping: mapping)
        appendSymptomsStatusComponent(to: &observation, mapping: mapping)
    }
    
    
    private func appendNumberOfVoltageMeasurementsComponent(
        to observation: inout Observation,
        mapping: ECGTypeFHIRMapping
    ) throws {
        let component = ObservationComponent(
            code: CodeableConcept(coding: mapping.numberOfVoltageMeasurements.codings),
            value: .quantity(
                Quantity(
                    code: mapping.numberOfVoltageMeasurements.unit.code,
                    system: mapping.numberOfVoltageMeasurements.unit.system,
                    unit: mapping.numberOfVoltageMeasurements.unit.unit.asFHIRStringPrimitive(),
                    value: try Double(numberOfVoltageMeasurements).asFHIRDecimalPrimitiveSafe()
                )
            )
        )
        observation.append(component: component)
    }
    
    private func appendSamplingFrequencyComponent(
        to observation: inout Observation,
        mapping: ECGTypeFHIRMapping
    ) throws {
        guard let samplingFrequency else {
            return
        }
        let component = ObservationComponent(
            code: CodeableConcept(coding: mapping.samplingFrequency.codings),
            value: .quantity(
                Quantity(
                    code: mapping.samplingFrequency.unit.code,
                    system: mapping.samplingFrequency.unit.system,
                    unit: mapping.samplingFrequency.unit.unit.asFHIRStringPrimitive(),
                    value: try samplingFrequency.doubleValue(for: mapping.samplingFrequency.unit.hkUnit).asFHIRDecimalPrimitiveSafe()
                )
            )
        )
        observation.append(component: component)
    }
    
    private func appendClassificationComponent(
        to observation: inout Observation,
        mapping: ECGTypeFHIRMapping
    ) {
        let component = ObservationComponent(
            code: CodeableConcept(coding: mapping.classification.codings),
            value: .codeableConcept(CodeableConcept(coding: [classification.asCoding]))
        )
        observation.append(component: component)
    }
    
    private func appendAverageHeartRateComponent(
        to observation: inout Observation,
        mapping: ECGTypeFHIRMapping
    ) throws {
        guard let averageHeartRate else {
            return
        }
        let component = ObservationComponent(
            code: CodeableConcept(coding: mapping.averageHeartRate.codings),
            value: .quantity(
                Quantity(
                    code: mapping.averageHeartRate.unit.code,
                    system: mapping.averageHeartRate.unit.system,
                    unit: mapping.averageHeartRate.unit.unit.asFHIRStringPrimitive(),
                    value: try averageHeartRate.doubleValue(for: mapping.averageHeartRate.unit.hkUnit).asFHIRDecimalPrimitiveSafe()
                )
            )
        )
        observation.append(component: component)
    }
    
    private func appendSymptomsStatusComponent(
        to observation: inout Observation,
        mapping: ECGTypeFHIRMapping
    ) {
        let component = ObservationComponent(
            code: CodeableConcept(coding: mapping.symptomsStatus.codings),
            value: .codeableConcept(CodeableConcept(coding: [symptomsStatus.asCoding]))
        )
        observation.append(component: component)
    }
    
    
    private func appendSymptomsComponent(
        to observation: inout Observation,
        symptoms: Symptoms,
        mapping: SampleTypesFHIRMapping
    ) throws {
        // Sorted so a dictionary's arbitrary order cannot reshuffle the components.
        for symptom in symptoms.sorted(by: { $0.key.identifier < $1.key.identifier }) {
            guard let sampleType = SampleType(symptom.key),
                  let mapping = mapping.categoryTypesMapping[sampleType] else {
                throw GroveHealthKitFHIRError.notSupported
            }
            let component = ObservationComponent(
                code: CodeableConcept(coding: mapping.codings),
                value: .codeableConcept(CodeableConcept(coding: [symptom.value.asCoding]))
            )
            observation.append(component: component)
        }
    }
    
    
    private func appendVoltageMeasurementsComponent(
        to observation: inout Observation,
        voltageMeasurements: VoltageMeasurements,
        mapping ecgTypeMapping: ECGTypeFHIRMapping
    ) throws {
        guard !voltageMeasurements.isEmpty else {
            return
        }
        observation.append(component: ObservationComponent(
            code: CodeableConcept(coding: ecgTypeMapping.voltageMeasurements.codings),
            value: .sampledData(try Self.sampledVoltageData(
                samplingFrequency: samplingFrequency,
                voltageMeasurements: voltageMeasurements,
                mapping: ecgTypeMapping
            ))
        ))
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKElectrocardiogram {
    /// Builds the `SampledData` carrying a strip's voltage measurements.
    ///
    /// Separate from ``appendVoltageMeasurementsComponent(to:voltageMeasurements:mapping:)`` because an
    /// `HKElectrocardiogram` cannot be constructed outside HealthKit, so this is the only testable surface.
    static func sampledVoltageData(
        samplingFrequency: HKQuantity?,
        voltageMeasurements: VoltageMeasurements,
        mapping ecgTypeMapping: ECGTypeFHIRMapping
    ) throws -> SampledData {
        let voltageMapping = ecgTypeMapping.voltageMeasurements
        let voltageMeasurements = voltageMeasurements.sorted(by: { $0.time < $1.time })
        // Milliseconds between samples, as a Decimal: SampledData carries no per-sample timing, so this
        // period is the only time anchor the strip has, and a Double round-trip would print artifacts for
        // non-dyadic frequencies. Exact division prints them too — 512.4 Hz runs to 34 digits — so the
        // quotient is rounded to a scale no ECG rate outruns.
        let period: Decimal
        if let samplingFrequency {
            period = Self.roundedPeriod(Decimal(1000) / Decimal(samplingFrequency.doubleValue(for: .hertz())))
        } else if voltageMeasurements.count > 1,
                  let first = voltageMeasurements.first?.time,
                  let last = voltageMeasurements.last?.time {
            // n samples span n-1 intervals.
            period = Self.roundedPeriod(Decimal((last - first) * 1000 / Double(voltageMeasurements.count - 1)))
        } else {
            throw GroveHealthKitFHIRError.notSupported
        }
        // The whole strip is ONE SampledData: repeated components carry no ordering or
        // timing semantics in FHIR, so splitting a lead across them loses the sample
        // positions. Consumers reconstruct sample times from effective[x] + period.
        let voltagePrecision = ecgTypeMapping.voltagePrecision
        let data = voltageMeasurements
            .map { String(format: "%.\(voltagePrecision)f", $0.value.doubleValue(for: voltageMapping.unit.hkUnit)) }
            .joined(separator: " ")
        return SampledData(
            data: data.asFHIRStringPrimitive(),
            dimensions: 1,
            origin: Quantity(
                code: voltageMapping.unit.code,
                system: voltageMapping.unit.system,
                unit: voltageMapping.unit.unit.asFHIRStringPrimitive(),
                value: 0.asFHIRDecimalPrimitive()
            ),
            period: FHIRPrimitive(FHIRDecimal(period))
        )
    }

    /// Six fraction digits of a millisecond is a nanosecond, finer than any sampling rate resolves.
    private static func roundedPeriod(_ period: Decimal) -> Decimal {
        var period = period
        var rounded = Decimal()
        NSDecimalRound(&rounded, &period, 6, .plain)
        return rounded
    }
}


// MARK: HKElectrocardiogram-related enums

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKElectrocardiogram.Classification.self,
    .notSet, .sinusRhythm, .atrialFibrillation, .inconclusiveLowHeartRate,
    .inconclusiveHighHeartRate, .inconclusivePoorReading, .inconclusiveOther, .unrecognized
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKElectrocardiogram.Classification: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKElectrocardiogram.SymptomsStatus.self,
    .notSet, .none, .present
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKElectrocardiogram.SymptomsStatus: FHIRCodingConvertibleHKEnum {}

#endif
