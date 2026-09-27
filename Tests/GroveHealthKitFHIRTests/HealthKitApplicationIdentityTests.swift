//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveFHIRContract
@testable import GroveHealthKitFHIR
import ModelsR4
import Testing


/// A host with no bundle identity must fail through the typed error path, never trap and never
/// mint a graph namespace shared by every such host.
@Suite
struct HealthKitFHIRApplicationIdentityTests {
    @Test("A bundle-less host has no application identity to state")
    func bundleLessHostIsRejected() {
        #expect(throws: ApplicationDeviceError.invalidBundleIdentifier("")) {
            try ApplicationDevice(name: "Runner", bundleIdentifier: "", version: "1.0")
        }
    }

    @Test("A bundle identifier is the exact Apple product token, not arbitrary text")
    func malformedBundleIdentifierIsRejected() {
        #expect(throws: ApplicationDeviceError.invalidBundleIdentifier("org.example. bad-id")) {
            try ApplicationDevice(name: "Runner", bundleIdentifier: "org.example. bad-id", version: "1.0")
        }
    }

    @Test("Blank application and host facts are refused where the deployment configures them")
    func blankFactsAreRefusedAtConstruction() {
        #expect(throws: ApplicationDeviceError.blankName) {
            try ApplicationDevice(name: " ", bundleIdentifier: "org.example.app", version: "1.0")
        }
        #expect(throws: ApplicationDeviceError.blankVersion) {
            try ApplicationDevice(name: "Runner", bundleIdentifier: "org.example.app", version: "")
        }
        #expect(throws: HostDeviceError.blankOperatingSystemVersion) {
            try HostDevice(operatingSystemVersion: "")
        }
        #expect(throws: HostDeviceError.blankModelNumber) {
            try HostDevice(operatingSystemVersion: "26.0", modelNumber: " ")
        }
        #expect(throws: RecordingDeviceError.blankStableUnitToken) {
            try RecordingDevice(stableUnitToken: "")
        }
    }
}

#endif
