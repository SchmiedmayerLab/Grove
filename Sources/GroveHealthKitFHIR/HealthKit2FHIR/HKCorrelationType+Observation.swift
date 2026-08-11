//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveHealthKit
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCorrelation: FHIRObservationBuildable {
    func build(_ observation: inout Observation, mapping: SampleTypesFHIRMapping) throws {
        guard let sampleType = SampleType(self.correlationType),
              let correlationTypeMapping = mapping.correlationTypesMapping[sampleType] else {
            throw GroveHealthKitFHIRError.notSupported
        }
        observation.append(codings: correlationTypeMapping.codings)
        for category in correlationTypeMapping.categories {
            observation.append(
                category: CodeableConcept(coding: [category])
            )
        }
        for object in self.objects {
            guard let sample = object as? HKQuantitySample else {
                throw GroveHealthKitFHIRError.notSupported
            }
            guard let sampleType = SampleType(sample.quantityType) else {
                throw GroveHealthKitFHIRError.notSupported
            }
            observation.append(component: try sample.quantity.buildObservationComponent(for: sampleType, mapping: mapping.quantityTypesMapping))
        }
    }
}

#endif
