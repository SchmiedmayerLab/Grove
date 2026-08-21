//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import FHIRModelsExtensions
import Foundation
import ModelsR4
import Testing


@Suite
struct ObservationExtensionsTests {
    @Test
    func fhirExtension() throws {
        let extension1Url: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/core/StructureDefinition/testDef1"
        let extension2Url: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/core/StructureDefinition/testDef2"
        let extension1: (Int) -> Extension = { Extension(url: extension1Url, value: .integer($0.asFHIRIntegerPrimitive())) }
        let extension2: (Int) -> Extension = { Extension(url: extension2Url, value: .integer($0.asFHIRIntegerPrimitive())) }
        
        var observation = Observation(code: CodeableConcept(), status: FHIRPrimitive(.final))
        #expect(observation.extension == nil)
        
        observation.append(extension: extension1(0), behaviour: .additive)
        #expect(observation.extension == [extension1(0)])
        
        observation.append(extension: extension2(0), behaviour: .additive)
        #expect(observation.extension == [extension1(0), extension2(0)])
        
        observation.append(extension: extension1(1), behaviour: .replace)
        #expect(observation.extension == [extension2(0), extension1(1)])
        
        observation.append(extension: extension1(2), behaviour: .additive)
        #expect(observation.extension == [extension2(0), extension1(1), extension1(2)])
        
        observation.append(extension: extension1(3), behaviour: .replace)
        #expect(observation.extension == [extension2(0), extension1(3)])
        
        observation.append(extension: extension2(1), behaviour: .additive)
        #expect(observation.extension == [extension2(0), extension1(3), extension2(1)])
        
        observation.append(extension: extension2(2), behaviour: .additive)
        #expect(observation.extension == [extension2(0), extension1(3), extension2(1), extension2(2)])
        
        observation.removeFirstExtension(withUrl: extension1Url)
        #expect(observation.extension == [extension2(0), extension2(1), extension2(2)])
        
        observation.removeFirstExtension(withUrl: extension2Url)
        #expect(observation.extension == [extension2(1), extension2(2)])
        
        observation.removeAllExtensions(withUrl: extension2Url)
        #expect(observation.extension == nil)
    }
}
