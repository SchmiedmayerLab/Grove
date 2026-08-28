//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

@testable import GroveHealthKitFHIR
import ModelsR4
import Testing


/// A host with no bundle identity must fail through the typed error path, never trap and never
/// mint a graph namespace shared by every such host.
@Suite
struct HealthKitFHIRApplicationIdentityTests {
    @Test("A bundle-less host is rejected as an invalid converter application")
    func bundleLessHostIsRejected() {
        let context = HealthKitConversionContext(
            subject: Reference(reference: "Patient/1a2b3c".asFHIRStringPrimitive()),
            converter: HealthKitApplication(name: "Runner", bundleIdentifier: "", version: "1.0")
        )
        #expect(throws: HealthKitConversionError.invalidConverterApplication("bundleIdentifier")) {
            try HealthKitConverter.validate(context: context)
        }
    }

    @Test("The empty namespace such a host derives is never treated as valid")
    func emptyNamespaceIsNotSilentlyAccepted() {
        let application = HealthKitApplication(name: "Runner", bundleIdentifier: "", version: "1.0")
        // Syntactically a valid URN, which is exactly why validation cannot rely on it.
        #expect(application.graphIdentifierSystem == "urn:grove:healthkit-graph:")
    }
}

#endif
