//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import HealthKit


/// All already-fetched evidence required to convert one HealthKit ECG without querying HealthKit from the FHIR layer:
/// what ``HealthKitFHIRExporter/Record/electrocardiogram(_:voltages:symptoms:)`` carries.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitECGRecord: Sendable {
    let electrocardiogram: HKElectrocardiogram
    let voltageMeasurements: [HKElectrocardiogram.VoltageMeasurement]
    let correlatedSymptoms: [HKCategorySample]

    init(
        electrocardiogram: HKElectrocardiogram,
        voltageMeasurements: [HKElectrocardiogram.VoltageMeasurement],
        correlatedSymptoms: [HKCategorySample] = []
    ) {
        self.electrocardiogram = electrocardiogram
        self.voltageMeasurements = voltageMeasurements
        self.correlatedSymptoms = correlatedSymptoms
    }
}

#endif
