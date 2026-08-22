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
public import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRConverter {
    /// Converts a caller-assembled ECG record after proving that its enumerated Lead-I-like
    /// voltage points are complete and exactly uniform.
    ///
    /// This overload performs no HealthKit query. The caller must finish the voltage
    /// enumeration and, when `symptomsStatus` is `present`, separately obtain and supply the
    /// associated symptom samples before calling it. Correlated symptoms also require
    /// ``HealthKitFHIRSourceDisclosurePolicy/authorized`` because the published contract
    /// preserves their complete, linkable `HKSourceRevision` evidence.
    public func convert(
        _ record: HealthKitECGRecord,
        context: HealthKitFHIRConversionContext
    ) throws(GroveHealthKitFHIRError) -> HealthKitFHIRConversion {
        do {
            return try Self.convertECG(record, context: context)
        } catch {
            throw GroveHealthKitFHIRError(conversionFailure: error)
        }
    }

    /// Convenience form of ``convert(_:context:)-(HealthKitECGRecord,_)`` that keeps each evidence family
    /// explicit at the call site.
    public func convert(
        _ electrocardiogram: HKElectrocardiogram,
        voltageMeasurements: [HKElectrocardiogram.VoltageMeasurement],
        correlatedSymptoms: [HKCategorySample] = [],
        context: HealthKitFHIRConversionContext
    ) throws(GroveHealthKitFHIRError) -> HealthKitFHIRConversion {
        try convert(
            HealthKitECGRecord(
                electrocardiogram: electrocardiogram,
                voltageMeasurements: voltageMeasurements,
                correlatedSymptoms: correlatedSymptoms
            ),
            context: context
        )
    }
}

#endif
