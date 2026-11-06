//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Fixed protocol-vector fixtures deliberately trap if a hard-coded identity becomes invalid.
// swiftlint:disable force_try

import CryptoKit
import Foundation
import GroveFHIRContract
@testable import GroveSensorKitFHIR


enum SensorFHIRIdentityTestSupport {
    static let visitLocationIdentifierSystem: IdentifierSystem =
        "https://grovealliance.org/fhir/testing/identifiers/sensorkit-location"
    static let converterHost = try! HostDevice(
        operatingSystemVersion: "20.1",
        productType: "Phone One",
        name: "Test Host",
        manufacturer: "Example Device Company"
    )
    static let subjectIdentifier = try! BusinessIdentifier(
        system: "https://grovealliance.org/fhir/testing/identifiers/participant",
        value: "example"
    )
    static let subject: Subject = .logical(subjectIdentifier)
    static let repositoryScope = try! BusinessIdentifier(
        system: "https://grovealliance.org/fhir/testing/identifiers/repository",
        value: "primary"
    )
    static let identityScope = try! OpaqueIdentityScope(
        systems: DeploymentIdentifierSystems(
            sourceRecord: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/source-record/test/1",
            sourceOutput: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/source-output/test/1",
            writerRecord: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/writer-record/test/1",
            providerRecord: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/provider-record/test/1",
            providerOutput: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/provider-output/test/1",
            sourceArtifact: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/source-artifact/test/1",
            providerArtifact: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/provider-artifact/test/1",
            sourceContext: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/source-context/test/1",
            recordingDevice: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/recording-device/test/1",
            deviceSnapshot: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/device-snapshot/test/1",
            contextSnapshot: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/context-snapshot/test/1",
            recordVersion: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/record-version/test/1",
            recordRetraction: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/record-retraction/test/1",
            deviceLocalIdentifier: "https://grovealliance.org/fhir/testing/identifiers/device-local-identifier"
        ),
        keyID: "test",
        epoch: KeyEpoch(1),
        key: SymmetricKey(data: Data(repeating: 0x42, count: 32))
    )

    static func sensorKitOutputs(
        sourceRecordID: SensorKitSourceRecordID,
        sourceToken: String,
        structuredDiscriminator: String?,
        includesNativeRecording: Bool
    ) throws -> [RoledIdentifier] {
        let sourceRecord = try identityScope.sourceRecord(
            adapterID: "sensorkit",
            sourceType: sourceToken,
            repositoryScope: repositoryScope,
            nativeRecordID: sourceRecordID.value
        )
        var outputs: [RoledIdentifier] = []
        if let structuredDiscriminator {
            outputs.append(try sourceRecord.output(role: "structured", discriminator: structuredDiscriminator))
        }
        if includesNativeRecording {
            outputs.append(try sourceRecord.output(role: "native-recording", discriminator: "native-recording"))
        }
        return outputs
    }
}


extension ApplicationDevice {
    static func test(name: String, bundleIdentifier: String, version: String) -> ApplicationDevice {
        try! ApplicationDevice(name: name, bundleIdentifier: bundleIdentifier, version: version)
    }
}


extension RecordingDevice {
    /// A recording Device stating every fact of an `SRDevice`, as `RecordingDevice(batch.info.device)` does.
    static func test(
        name: String = "Example Watch",
        model: String = "Apple Watch",
        systemName: String = "watchOS",
        systemVersion: String = "11.2",
        productType: String = "Watch7,1"
    ) -> RecordingDevice {
        var device = RecordingDevice()
        device.name = name
        device.model = model
        device.systemName = systemName
        device.systemVersion = systemVersion
        device.productType = productType
        return device
    }

    /// A recording Device stating every fact of an `SRSourceDevice`, as `RecordingDevice(batch.info.sourceDevices[0])` does.
    static func testPeripheral(
        localIdentifier: String = "peripheral-7",
        manufacturer: String = "Example Audio",
        model: String = "Ear One",
        hardwareVersion: String = "2",
        firmwareVersion: String = "5.1"
    ) -> RecordingDevice {
        var device = RecordingDevice()
        device.localIdentifier = localIdentifier
        device.manufacturer = manufacturer
        device.model = model
        device.hardwareVersion = hardwareVersion
        device.firmwareVersion = firmwareVersion
        return device
    }
}


extension RoledIdentifier {
    var value: String { identifier.value }
    var system: IdentifierSystem { identifier.system }
    var systemValue: String { identifier.system.rawValue }
}
