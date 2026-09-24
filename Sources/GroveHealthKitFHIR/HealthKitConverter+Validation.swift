//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveFHIRContract


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// The one check the typed context cannot make at construction: a disclosed native identifier
    /// system must not be one of the deployment's own graph identity systems.
    static func validate(context: HealthKitConversionContext) throws(HealthKitConversionError) {
        guard case let .authorized(nativeSystem, _) = context.options.nativeIdentifierDisclosure else {
            return
        }
        guard !context.identityScope.systems.all.contains(nativeSystem) else {
            throw .reservedIdentifierSystem
        }
    }
}

#endif
