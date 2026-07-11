//
// This source file is part of the HealthKitOnFHIR open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import HealthKit
import ModelsR4


/// A Type that can be used to build up a FHIR `Observation`.
@available(iOS 18, macOS 15, watchOS 11, *)
protocol FHIRObservationBuildable {
    func build(_ observation: Observation, mapping: HKSampleMapping) throws
}
