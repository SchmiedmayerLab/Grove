//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import GroveHealthKit
public import ModelsR4


/// Controls how a `HKElectrocardiogram` is mapped into a FHIR Observation.
///
/// ## Topics
///
/// ### Static Properties
/// - ``default``
///
/// ### Initializers
/// - ``init(codings:categories:classification:symptomsStatus:numberOfVoltageMeasurements:samplingFrequency:averageHeartRate:voltageMeasurements:voltagePrecision:)``
///
/// ### Instance Properties
/// - ``codings``
/// - ``categories``
/// - ``classification``
/// - ``symptomsStatus``
/// - ``numberOfVoltageMeasurements``
/// - ``samplingFrequency``
/// - ``averageHeartRate``
/// - ``voltageMeasurements``
/// - ``voltagePrecision``
@available(iOS 18, macOS 15, watchOS 11, *)
public struct ECGTypeFHIRMapping: Sendable {
    /// The FHIR codings defined as `Coding`s used for the `HKElectrocardiogram`.
    public var codings: [Coding]
    /// The FHIR categories defined as `Coding`s used for the `HKElectrocardiogram`.
    public var categories: [Coding]
    /// Defines the mapping of the `classification` category sample  of an `HKElectrocardiogram` to an FHIR  observation.
    public var classification: CategoryTypeFHIRMapping
    /// Defines the mapping of the `symptomsStatus` category sample  of an `HKElectrocardiogram` to an FHIR  observation.
    public var symptomsStatus: CategoryTypeFHIRMapping
    /// Defines the mapping of the `numberOfVoltageMeasurements` quantity property of an `HKElectrocardiogram` to an FHIR  observation.
    public var numberOfVoltageMeasurements: QuantityTypeFHIRMapping
    /// Defines the mapping of the `samplingFrequency` quantity property of an `HKElectrocardiogram` to an FHIR  observation.
    public var samplingFrequency: QuantityTypeFHIRMapping
    /// Defines the mapping of the `averageHeartRate` quantity property of an `HKElectrocardiogram` to an FHIR observation.
    public var averageHeartRate: QuantityTypeFHIRMapping
    /// Defines the mapping of the `voltageMeasurements` of an `HKElectrocardiogram` to an FHIR observation.
    public var voltageMeasurements: QuantityTypeFHIRMapping
    /// Defines the precision represented as the number of decimal values for the voltage measurement mapping of an `HKElectrocardiogram` to an FHIR observation.
    public var voltagePrecision: UInt
    
    public init(
        codings: [Coding],
        categories: [Coding],
        classification: CategoryTypeFHIRMapping,
        symptomsStatus: CategoryTypeFHIRMapping,
        numberOfVoltageMeasurements: QuantityTypeFHIRMapping,
        samplingFrequency: QuantityTypeFHIRMapping,
        averageHeartRate: QuantityTypeFHIRMapping,
        voltageMeasurements: QuantityTypeFHIRMapping,
        voltagePrecision: UInt
    ) {
        self.codings = codings
        self.categories = categories
        self.classification = classification
        self.symptomsStatus = symptomsStatus
        self.numberOfVoltageMeasurements = numberOfVoltageMeasurements
        self.samplingFrequency = samplingFrequency
        self.averageHeartRate = averageHeartRate
        self.voltageMeasurements = voltageMeasurements
        self.voltagePrecision = voltagePrecision
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ECGTypeFHIRMapping {
    /// The default FHIR mapping for `HKElectrocardiogram` samples.
    public static let `default` = Self(
        codings: [
            Coding(
                code: "131328",
                display: "MDC_ECG_ELEC_POTL",
                system: GroveFHIRVocabulary.mdc
            ),
            Coding(
                code: "11524-6",
                display: "EKG study",
                system: GroveFHIRVocabulary.loinc
            ),
            Coding(
                code: "HKDataTypeIdentifierElectrocardiogram",  // the runtime value of HKObjectType.electrocardiogramType().identifier
                display: "Electrocardiogram",
                system: GroveFHIRVocabulary.healthKitSampleType
            )
        ],
        categories: [
            Coding(
                code: "procedure",
                display: "Procedure",
                system: GroveFHIRVocabulary.observationCategory
            )
        ],
        classification: CategoryTypeFHIRMapping(
            codings: [
                Coding(
                    code: "classification",
                    display: "Electrocardiogram Classification",
                    system: GroveFHIRVocabulary.healthKitECGProperty
                )
            ],
            categories: []
        ),
        symptomsStatus: CategoryTypeFHIRMapping(
            codings: [
                Coding(
                    code: "symptoms-status",
                    display: "Electrocardiogram Symptoms Status",
                    system: GroveFHIRVocabulary.healthKitECGProperty
                )
            ],
            categories: []
        ),
        numberOfVoltageMeasurements: QuantityTypeFHIRMapping(
            codings: [
                Coding(
                    code: "number-of-voltage-measurements",
                    display: "Electrocardiogram Number of Voltage Measurements",
                    system: GroveFHIRVocabulary.healthKitECGProperty
                )
            ],
            unit: QuantityTypeFHIRMapping.Unit(
                hkUnit: .count(),
                unit: "measurements",
                system: GroveFHIRVocabulary.ucum,
                code: "{measurements}"
            )
        ),
        samplingFrequency: QuantityTypeFHIRMapping(
            codings: [
                Coding(
                    code: "sampling-frequency",
                    display: "Sampling Frequency",
                    system: GroveFHIRVocabulary.healthKitECGProperty
                )
            ],
            unit: QuantityTypeFHIRMapping.Unit(
                hkUnit: .hertz(),
                unit: "Hz",
                system: GroveFHIRVocabulary.ucum,
                code: "Hz"
            )
        ),
        averageHeartRate: QuantityTypeFHIRMapping(
            codings: [
                Coding(
                    code: "8867-4",
                    display: "Heart rate",
                    system: GroveFHIRVocabulary.loinc
                ),
                Coding(
                    code: "147842",
                    display: "MDC_ECG_HEART_RATE",
                    system: GroveFHIRVocabulary.mdc
                ),
                Coding(
                    code: "HKQuantityTypeIdentifierHeartRate",
                    display: "Heart Rate",
                    system: GroveFHIRVocabulary.healthKitSampleType
                )
            ],
            unit: QuantityTypeFHIRMapping.Unit(
                hkUnit: .count() / .minute(),
                unit: "beats/minute",
                system: GroveFHIRVocabulary.ucum,
                code: "/min"
            )
        ),
        voltageMeasurements: QuantityTypeFHIRMapping(
            codings: [
                Coding(
                    code: "131329",
                    display: "MDC_ECG_ELEC_POTL_I",
                    system: GroveFHIRVocabulary.mdc
                )
            ],
            unit: QuantityTypeFHIRMapping.Unit(
                hkUnit: .voltUnit(with: .micro),
                unit: "uV",
                system: GroveFHIRVocabulary.ucum,
                code: "uV"
            )
        ),
        voltagePrecision: 1
    )
}
