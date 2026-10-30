//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import FHIRModelsExtensions
import GroveFHIRContract
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// Preserves the exact SDK source class as lineage, without claiming that it is an equivalent
    /// clinical or document-type coding.
    static func applySourceTypeLineage<T: FHIRTypeWithExtensions>(
        _ sourceTypeIdentifier: String,
        to resource: inout T
    ) {
        resource.append(
            extension: Extension(
                url: Canonicals.healthKitSourceTypeExtension,
                value: .code(sourceTypeIdentifier.asFHIRStringPrimitive())
            ),
            behaviour: .replace
        )
    }
}

#endif
