//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import FHIRModelsExtensions
import GroveHealthKit
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKQuantitySample: FHIRObservationBuildable {
    func build(_ observation: inout Observation, mapping: SampleTypesFHIRMapping) throws {
        let quantityType: SampleType<HKQuantitySample>
        if let type = SampleType(self.quantityType) {
            quantityType = type
        } else if let type = mapping.quantityTypesMapping.keys.first(where: { $0.identifier == self.quantityType.identifier }) {
            // ^^ fallback for cases where we're some how dealing with user-defined not-known-to-SHK sample types
            quantityType = type
        } else {
            throw GroveHealthKitFHIRError.notSupported
        }
        guard let mapping = mapping.quantityTypesMapping[quantityType] else {
            throw GroveHealthKitFHIRError.notSupported
        }
        observation.append(codings: mapping.codings)
        observation.append(categories: mapping.categories.map { CodeableConcept(coding: [$0]) })
        observation.value = .quantity(try quantity.buildQuantity(mapping: mapping))
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKQuantity {
    func buildObservationComponent(
        for quantityType: SampleType<HKQuantitySample>,
        mapping: QuantityTypesFHIRMapping = .default
    ) throws -> ObservationComponent {
        guard let mapping = mapping[quantityType] else {
            throw GroveHealthKitFHIRError.notSupported
        }
        return try buildObservationComponent(mapping: mapping)
    }
    
    func buildObservationComponent(mapping: QuantityTypeFHIRMapping) throws -> ObservationComponent {
        ObservationComponent(
            code: CodeableConcept(coding: mapping.codings),
            value: .quantity(try buildQuantity(mapping: mapping))
        )
    }
    
    func buildQuantity(mapping: QuantityTypeFHIRMapping) throws -> Quantity {
        var value = self.doubleValue(for: mapping.unit.hkUnit)
        if mapping.unit.hkUnit == .percent() {
            value *= 100
        }
        return Quantity(
            code: mapping.unit.code,
            system: mapping.unit.system,
            unit: mapping.unit.unit.asFHIRStringPrimitive(),
            value: try value.asFHIRDecimalPrimitiveSafe()
        )
    }
}

#endif
