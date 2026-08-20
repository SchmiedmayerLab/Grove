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
    ) throws -> HealthKitFHIRConversion {
        do {
            return try Self.convertECG(record, context: context)
        } catch let error as GroveHealthKitFHIRError {
            throw error
        } catch let error as GroveFHIRExchangeIdentityError {
            throw GroveHealthKitFHIRError.invalidExchangeIdentity(String(describing: error))
        }
    }

    /// Convenience form of ``convert(_:context:)`` that keeps each evidence family
    /// explicit at the call site.
    public func convert(
        _ electrocardiogram: HKElectrocardiogram,
        voltageMeasurements: [HKElectrocardiogram.VoltageMeasurement],
        correlatedSymptoms: [HKCategorySample] = [],
        context: HealthKitFHIRConversionContext
    ) throws -> HealthKitFHIRConversion {
        try convert(
            HealthKitECGRecord(
                electrocardiogram: electrocardiogram,
                voltageMeasurements: voltageMeasurements,
                correlatedSymptoms: correlatedSymptoms
            ),
            context: context
        )
    }

    /// Converts every ECG record and preserves a typed failure for every rejected record.
    public func convertECGs<S: Sequence>(
        _ records: S,
        context: HealthKitFHIRConversionContext
    ) -> HealthKitFHIRBatchResult where S.Element == HealthKitECGRecord {
        var conversions: [HealthKitFHIRConversion] = []
        var failures: [HealthKitFHIRRecordFailure] = []
        for record in records {
            do {
                conversions.append(try convert(record, context: context))
            } catch let error as GroveHealthKitFHIRError {
                failures.append(failure(for: record, reason: error))
            } catch {
                failures.append(failure(
                    for: record,
                    reason: .unexpectedConversionFailure(String(describing: error))
                ))
            }
        }
        return HealthKitFHIRBatchResult(conversions: conversions, failures: failures)
    }

    private func failure(
        for record: HealthKitECGRecord,
        reason: GroveHealthKitFHIRError
    ) -> HealthKitFHIRRecordFailure {
        HealthKitFHIRRecordFailure(
            sourceUUID: record.electrocardiogram.uuid,
            sourceTypeIdentifier: record.electrocardiogram.sampleType.identifier,
            reason: reason
        )
    }
}

#endif
