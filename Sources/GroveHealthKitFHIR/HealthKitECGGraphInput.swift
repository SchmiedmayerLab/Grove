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


struct HealthKitECGGraphContext: Sendable {
    let recordingDeviceURL: String?
    let converterURL: String
}


@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitECGObservationInput: Sendable {
    let source: HealthKitECGSourceEvidence
    let waveform: HealthKitECGValidatedWaveform
    let symptomOutputIdentifiers: [BusinessIdentifier]
    let context: HealthKitConversionContext
}


/// Exact scalar and interval evidence extracted synchronously from the caller-supplied ECG.
/// Keeping projection separate from retrieval makes the FHIR builder deterministic and testable.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitECGSourceEvidence: Sendable {
    let sourceTypeIdentifier: String
    let startDate: Date
    let endDate: Date
    let timeZone: TimeZone
    let classification: HKElectrocardiogram.Classification
    let symptomsStatus: HKElectrocardiogram.SymptomsStatus
    let numberOfVoltageMeasurements: Int
    let averageHeartRate: Double?
    let samplingFrequency: Double?
    let algorithmVersion: Int?
    let wasUserEntered: Bool
}

#endif
