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
    static let producerInstance = UUID(uuid: (
        0xaa, 0xaa, 0xaa, 0xaa, 0xbb, 0xbb, 0x4c, 0xcc,
        0x8d, 0xdd, 0xee, 0xee, 0xee, 0xee, 0xee, 0xee
    ))
    static let entryNodeIdentifierSystem: IdentifierSystem =
        "https://grovealliance.org/fhir/testing/identifiers/exchange-entry-node"
    static let visitLocationIdentifierSystem: IdentifierSystem =
        "https://grovealliance.org/fhir/testing/identifiers/sensorkit-location"
    static let converterHost = try! HostDevice(
        operatingSystemVersion: "20.1",
        name: "Test Host",
        manufacturer: "Example Device Company",
        modelNumber: "Phone One"
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
            event: "https://grovealliance.org/fhir/testing/identifiers/exchange-event",
            entryNode: entryNodeIdentifierSystem
        ),
        keyID: "test",
        epoch: EventSequence(1),
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
    static func test(
        stableUnitToken: String,
        name: String? = nil,
        manufacturer: String? = nil,
        modelNumber: String? = nil
    ) -> RecordingDevice {
        try! RecordingDevice(stableUnitToken: stableUnitToken, name: name, manufacturer: manufacturer, modelNumber: modelNumber)
    }
}


extension RoledIdentifier {
    var value: String { identifier.value }
    var system: IdentifierSystem { identifier.system }
    var systemValue: String { identifier.system.rawValue }
}
