//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import AsyncAlgorithms
import Grove
import HealthKit
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKElectrocardiogram {
    /// A type alias used to associate symptoms in an `HKElectrocardiogram`.
    public typealias Symptoms = [HKCategoryType: HKCategoryValueSeverity]
    
    /// A single voltage measurement in an `HKElectrocardiogram`.
    public struct Measurement: Hashable, Sendable {
        /// The time of the measurement relative to the sample’s start time.
        public let timeOffset: TimeInterval
        /// The voltage as determined by the Apple Watch sensor, similar to a Lead I ECG.
        public let voltage: HKQuantity
    }
    
    /// All possible `HKCategoryType`s (`HKCategoryTypeIdentifier`s) that can be associated with an `HKElectrocardiogram`.
    public static let correlatedSymptomTypes: [SampleType<HKCategorySample>] = [
        .rapidPoundingOrFlutteringHeartbeat,
        .skippedHeartbeat,
        .fatigue,
        .shortnessOfBreath,
        .chestTightnessOrPain,
        .fainting,
        .dizziness
    ]
    
    
    /// Load the symptoms of an `HKElectrocardiogram` instance from an `HKHealthStore` instance.
    /// - Parameter healthKit: The ``HealthKit`` instance that should be used to load the `Symptoms`.
    /// - Returns: The electrocardiogram's associated symptoms
    public func symptoms(from healthKit: HealthKit) async throws -> Symptoms {
        try await correlatedSymptomSamples(from: healthKit).reduce(into: [:]) { symptoms, sample in
            guard let severity = HKCategoryValueSeverity(rawValue: sample.value) else {
                return
            }
            symptoms[sample.categoryType] = severity
        }
    }

    /// Load the symptom samples correlated with this electrocardiogram.
    ///
    /// The samples themselves, rather than the severities ``symptoms(from:)`` reduces them to:
    /// each one's identity, exact period, and source revision are the evidence a lossless FHIR
    /// conversion requires, and reducing to a severity per type discards all of it. Distinct
    /// samples may share a type, so this preserves every sample rather than one per type.
    ///
    /// - Parameter healthKit: The ``HealthKit`` instance used to load the samples.
    /// - Returns: Every symptom sample associated with the electrocardiogram.
    public func correlatedSymptomSamples(from healthKit: HealthKit) async throws -> [HKCategorySample] {
        guard symptomsStatus == .present else {
            return []
        }
        try await healthKit.askForAuthorization(for: .init(
            read: HKElectrocardiogram.correlatedSymptomTypes.map(\.hkSampleType)
        ))
        // SAFETY: the predicate doesn't use a block and therefore is Sendable.
        nonisolated(unsafe) let predicate = HKQuery.predicateForObjectsAssociated(electrocardiogram: self)
        return try await withThrowingTaskGroup(of: [HKCategorySample].self) { taskGroup in
            for categoryType in HKElectrocardiogram.correlatedSymptomTypes {
                taskGroup.addTask {
                    try await healthKit.query(categoryType, timeRange: .ever, predicate: predicate)
                }
            }
            return try await taskGroup.reduce(into: []) { $0.append(contentsOf: $1) }
        }
    }


    /// Load the voltage measurements of an `HKElectrocardiogram` instance from an `HKHealthStore` instance.
    /// - Parameter healthStore: The `HKHealthStore` instance that should be used to load the `VoltageMeasurements`.
    /// - Returns: The electrocardiogram's associated voltage measurements
    public func voltageMeasurements(from healthStore: HKHealthStore) async throws -> [Measurement] {
        try await rawVoltageMeasurements(from: healthStore).compactMap { measurement in
            guard let voltage = measurement.quantity(for: .appleWatchSimilarToLeadI) else {
                return nil
            }
            return Measurement(timeOffset: measurement.timeSinceSampleStart, voltage: voltage)
        }
    }

    /// Load the voltage measurements as HealthKit itself reports them.
    ///
    /// ``voltageMeasurements(from:)`` projects each point onto ``Measurement``, which keeps only the
    /// Lead-I-like quantity and its offset. A conversion that must prove the enumeration is complete
    /// and exactly uniform needs the platform value, so this returns it unreduced.
    ///
    /// - Parameter healthStore: The `HKHealthStore` used to enumerate the waveform.
    /// - Returns: Every voltage measurement, in source order.
    public func rawVoltageMeasurements(from healthStore: HKHealthStore) async throws -> [VoltageMeasurement] {
        var measurements: [VoltageMeasurement] = []
        measurements.reserveCapacity(numberOfVoltageMeasurements)
        for try await measurement in HKElectrocardiogramQueryDescriptor(self).results(for: healthStore) {
            measurements.append(measurement)
        }
        return measurements
    }
}

#endif
