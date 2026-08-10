//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import HealthKit
import ModelsR4
import SpeziHealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCorrelation: FHIRObservationBuildable {
    func build(_ observation: inout Observation, mapping: SampleTypesFHIRMapping) throws {
        guard let sampleType = SampleType(self.correlationType),
              let correlationTypeMapping = mapping.correlationTypesMapping[sampleType] else {
            throw SpeziHealthKitFHIRError.notSupported
        }
        observation.append(codings: correlationTypeMapping.codings)
        observation.append(categories: correlationTypeMapping.categories.map { CodeableConcept(coding: [$0]) })
        for object in self.objects {
            guard let sample = object as? HKQuantitySample else {
                throw SpeziHealthKitFHIRError.notSupported
            }
            guard let sampleType = SampleType(sample.quantityType) else {
                throw SpeziHealthKitFHIRError.notSupported
            }
            observation.append(component: try sample.quantity.buildObservationComponent(for: sampleType, mapping: mapping.quantityTypesMapping))
        }
    }
}

#endif
