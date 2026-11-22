//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import FHIRModelsExtensions
public import ModelsDSTU2


// Lives in GroveFHIR rather than FHIRModelsExtensions, so that FHIRModelsExtensions does not depend on ModelsDSTU2.
// Every Swift module a target links stays in the binary, used or not; this keeps ModelsDSTU2 out of apps that only
// need FHIRModelsExtensions.
@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRExtensionURL {
    /// DSTU2 `FHIRPrimitive<FHIRURI>`
    public var dstu2: ModelsDSTU2.FHIRPrimitive<ModelsDSTU2.FHIRURI> {
        url.asFHIRURIPrimitive()
    }
}
