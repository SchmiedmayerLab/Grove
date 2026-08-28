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
public import GroveHealthKit
public import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// Converts a caller-assembled ECG record after proving that its enumerated Lead-I-like
    /// voltage points are complete and exactly uniform.
    ///
    /// This overload performs no HealthKit query. The caller must finish the voltage
    /// enumeration and, when `symptomsStatus` is `present`, separately obtain and supply the
    /// associated symptom samples before calling it. Correlated symptoms also require
    /// ``HealthKitSourceDisclosurePolicy/authorized`` because the published contract
    /// preserves their complete, linkable `HKSourceRevision` evidence.
    public func convert(
        _ record: HealthKitECGRecord,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitConversion {
        do {
            return try Self.convertECG(record, context: context)
        } catch {
            throw HealthKitConversionError(conversionFailure: error)
        }
    }

    /// Convenience form of ``convert(_:context:)-(HealthKitECGRecord,_)`` that keeps each evidence family
    /// explicit at the call site.
    public func convert(
        _ electrocardiogram: HKElectrocardiogram,
        voltageMeasurements: [HKElectrocardiogram.VoltageMeasurement],
        correlatedSymptoms: [HKCategorySample] = [],
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitConversion {
        try convert(
            HealthKitECGRecord(
                electrocardiogram: electrocardiogram,
                voltageMeasurements: voltageMeasurements,
                correlatedSymptoms: correlatedSymptoms
            ),
            context: context
        )
    }

    /// Converts an electrocardiogram, gathering the evidence the contract requires.
    ///
    /// An ECG carries its waveform and its symptoms outside the sample, so a conversion needs two
    /// further queries. This overload performs them; the no-fetch overloads remain for callers that
    /// already hold the evidence or must not touch the health store.
    ///
    /// ```swift
    /// let conversion = try await HealthKitConverter().convert(ecg, using: healthKit, context: context)
    /// ```
    public func convert(
        _ electrocardiogram: HKElectrocardiogram,
        using healthKit: HealthKit,
        context: HealthKitConversionContext
    ) async throws -> HealthKitConversion {
        async let voltageMeasurements = electrocardiogram.rawVoltageMeasurements(from: healthKit.healthStore)
        async let correlatedSymptoms = electrocardiogram.correlatedSymptomSamples(from: healthKit)
        return try convert(
            HealthKitECGRecord(
                electrocardiogram: electrocardiogram,
                voltageMeasurements: try await voltageMeasurements,
                correlatedSymptoms: try await correlatedSymptoms
            ),
            context: context
        )
    }

    /// Converts one sample, fetching whatever evidence its type keeps outside the sample.
    ///
    /// An electrocardiogram holds its voltage enumeration and correlated symptoms in the health
    /// store rather than on the sample, so this overload fetches them first. Every other type
    /// converts from the sample alone and performs no query, so a caller can hand this a mixed
    /// sequence without sorting the electrocardiograms out itself.
    ///
    /// ```swift
    /// let conversion = try await HealthKitConverter().convert(sample, using: healthKit, context: context)
    /// ```
    public func convert(
        _ sample: HKSample,
        using healthKit: HealthKit,
        context: HealthKitConversionContext
    ) async throws -> HealthKitConversion {
        guard let electrocardiogram = sample as? HKElectrocardiogram else {
            return try convert(sample, context: context)
        }
        return try await convert(electrocardiogram, using: healthKit, context: context)
    }
}

#endif
