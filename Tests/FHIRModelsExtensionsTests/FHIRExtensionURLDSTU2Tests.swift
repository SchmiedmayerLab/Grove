//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if DSTU2
import FHIRModelsExtensions
import Foundation
import ModelsDSTU2
import Testing


@Suite
struct FHIRExtensionURLDSTU2Tests {
    @Test
    func dstu2PrimitiveCarriesTheURL() throws {
        let url = try FHIRExtensionURL("https://example.org/fhir/extension")
        let primitive: ModelsDSTU2.FHIRPrimitive<ModelsDSTU2.FHIRURI> = url.dstu2
        #expect(primitive.value?.url == url.url)
    }
}
#endif
