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
            subject: .testLogicalReference(resourceType: .patient, value: "1a2b3c"),
            converter: HealthKitApplication(name: "Runner", bundleIdentifier: "", version: "1.0")
        )
        #expect(throws: HealthKitConversionError.invalidConverterApplication("bundleIdentifier")) {
            try HealthKitConverter.validate(context: context)
        }
    }

    @Test("A bundle identifier is the exact Apple product token, not arbitrary text")
    func malformedBundleIdentifierIsRejected() {
        let context = HealthKitConversionContext(
            subject: .testLogicalReference(resourceType: .patient, value: "1a2b3c"),
            converter: HealthKitApplication(
                name: "Runner",
                bundleIdentifier: "org.example. bad-id",
                version: "1.0"
            )
        )
        #expect(throws: HealthKitConversionError.invalidConverterApplication("bundleIdentifier")) {
            try HealthKitConverter.validate(context: context)
        }
    }
}

#endif
