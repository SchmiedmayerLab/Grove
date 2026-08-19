//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
@available(watchOS, unavailable)
extension HKClinicalRecord {
    /// Converts an `HKClinicalRecord` into a corresponding FHIR resource, encapsulated in a `ResourceProxy`
    func resource() throws -> ResourceProxy {
        guard let fhirResource = self.fhirResource else {
            throw GroveHealthKitFHIRError.invalidFHIRResource
        }
        guard fhirResource.fhirVersion == .primaryR4() else {
            throw GroveHealthKitFHIRError.unsupportedFHIRVersion
        }
        return try JSONDecoder().decode(ResourceProxy.self, from: fhirResource.data)
    }
}

#endif
