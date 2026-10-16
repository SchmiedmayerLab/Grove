//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Fixed valid fixtures deliberately fail at test-process startup if their literals drift.
// swiftlint:disable force_try function_body_length

#if canImport(HealthKit)

import CryptoKit
import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4


/// Names every unit by one fixed token, for tests that assert a recording Device regardless of the sample's device.
struct FixedTokenRecordingDeviceResolver: HealthKitFHIRExporter.RecordingDeviceResolver {
    let token: String

    func recordingDevice(for device: HKDevice) -> RecordingDevice? {
        try? RecordingDevice(
            stableUnitToken: token,
            name: device.name?.nonBlank,
            manufacturer: device.manufacturer?.nonBlank,
            modelNumber: device.model?.nonBlank
        )
    }
}


/// The test deployment and one event under it: the subject, identity scope and repository scope every export states, and
/// the event identifier, application, host and instant one event freezes.
struct TestEvent {
    static let testInstant = Date(timeIntervalSince1970: 1_787_009_400)

    let subject: Subject
    let event: ExchangeEventIdentifier
    let identityScope: OpaqueIdentityScope
    let repositoryScope: BusinessIdentifier
    let application: ApplicationDevice
    let host: HostDevice
    let conversionInstant: Date

    /// The deployment's entry-node system, held by the identity scope.
    var entryNodeIdentifierSystem: IdentifierSystem { identityScope.systems.entryNode }

    /// The test deployment rooted at `graphIdentifierSystem`, and the event it numbers by the instant in milliseconds.
    static func test(graphIdentifierSystem: IdentifierSystem? = nil, conversionInstant: Date = testInstant) -> TestEvent {
        let base = graphIdentifierSystem ?? "https://grovealliance.org/fhir/testing/identifiers/healthkit"
        let systemRoot = base.rawValue
        let sequence = UInt64(max(1, Int64(conversionInstant.timeIntervalSince1970 * 1_000)))
        return try! TestEvent(
            subject: .testPatient,
            event: ExchangeEventIdentifier(
                system: IdentifierSystem("\(systemRoot)/event"),
                producerInstance: UUID(uuid: (
                    0x1f, 0x5c, 0x58, 0xaa, 0x6e, 0xc6, 0x4e, 0x79,
                    0xa6, 0x82, 0x82, 0x9a, 0x9d, 0xeb, 0xd3, 0xf5
                )),
                sequence: EventSequence(sequence)
            ),
            identityScope: OpaqueIdentityScope(
                systems: DeploymentIdentifierSystems(
                    sourceRecord: IdentifierSystem("\(systemRoot)/source-record/test/1"),
                    sourceOutput: IdentifierSystem("\(systemRoot)/source-output/test/1"),
                    writerRecord: IdentifierSystem("\(systemRoot)/writer-record/test/1"),
                    providerRecord: IdentifierSystem("\(systemRoot)/provider-record/test/1"),
                    providerOutput: IdentifierSystem("\(systemRoot)/provider-output/test/1"),
                    sourceArtifact: IdentifierSystem("\(systemRoot)/source-artifact/test/1"),
                    providerArtifact: IdentifierSystem("\(systemRoot)/provider-artifact/test/1"),
                    sourceContext: IdentifierSystem("\(systemRoot)/source-context/test/1"),
                    recordingDevice: IdentifierSystem("\(systemRoot)/recording-device/test/1"),
                    deviceSnapshot: IdentifierSystem("\(systemRoot)/device-snapshot/test/1"),
                    event: IdentifierSystem("\(systemRoot)/event"),
                    entryNode: IdentifierSystem("\(systemRoot)/entry-node")
                ),
                keyID: "test",
                epoch: EventSequence(1),
                key: SymmetricKey(data: Data(repeating: 0x42, count: 32))
            ),
            repositoryScope: BusinessIdentifier(system: IdentifierSystem("\(systemRoot)/repository"), value: "primary"),
            application: .test,
            host: .test,
            conversionInstant: conversionInstant
        )
    }

    /// The retraction of `sourceRecord` as this event, recorded at its instant.
    func retraction(
        of sourceRecord: RoledIdentifier,
        targets: [RetractionEvent.Target],
        occurred: RetractionEvent.Occurrence
    ) throws(RetractionEvent.ValidationError) -> RetractionEvent {
        try RetractionEvent(
            event: event,
            instant: conversionInstant,
            identityScope: identityScope,
            application: application,
            sourceRecord: sourceRecord,
            targets: targets,
            occurred: occurred
        )
    }
}


extension BusinessIdentifier {
    static func test(_ resourceType: ResourceType, _ value: String) -> BusinessIdentifier {
        try! BusinessIdentifier(
            system: IdentifierSystem("https://grovealliance.org/fhir/testing/identifiers/\(resourceType.rawValue.lowercased())"),
            value: value
        )
    }
}


extension Subject {
    static var testPatient: Subject { .logical(.test(.patient, "example")) }
}


extension Reference {
    static var testPatient: Reference { BusinessIdentifier.test(.patient, "example").reference(to: .patient) }

    static func testLogicalReference(resourceType: ResourceType, value: String) -> Reference {
        BusinessIdentifier.test(resourceType, value).reference(to: resourceType)
    }
}


extension StudyEnrollment {
    static func test(_ id: String) -> StudyEnrollment {
        try! StudyEnrollment(
            study: .test(.researchStudy, id),
            protocolURL: FHIRPrimitive(Canonical(stringLiteral: "https://study.example.org/PlanDefinition/\(id)")),
            protocolVersion: "1",
            enrollment: .test(.researchSubject, "enrollment-\(id)")
        )
    }
}


extension ApplicationDevice {
    static let test = ApplicationDevice.test(name: "Grove Test", bundleIdentifier: "org.grovealliance.test", version: "1.0")

    static func test(name: String, bundleIdentifier: String, version: String, build: String? = nil) -> ApplicationDevice {
        try! ApplicationDevice(name: name, bundleIdentifier: bundleIdentifier, version: version, build: build)
    }
}


extension HostDevice {
    static let test = try! HostDevice(
        operatingSystemVersion: "20.1",
        name: "Grove Test Host",
        manufacturer: "Example Device Company",
        modelNumber: "Phone One"
    )
}


extension ExchangeGraph {
    func resource<R: Resource>(_ type: R.Type, at identifier: RoledIdentifier) -> R? {
        entry(fullURL: try! identifier.fullURL)?.resource?.get(if: R.self)
    }
}


extension ExchangeGraphIdentifiers {
    var converterApplicationSnapshot: RoledIdentifier { applicationSnapshot }
    var converterHostSnapshot: RoledIdentifier { hostSnapshot }
    var sourceOutput: RoledIdentifier { primaryOutput }
}


extension RoledIdentifier {
    var value: String { identifier.value }
    var system: IdentifierSystem { identifier.system }
    var fhirIdentifierValue: String { identifier.value }
}

#endif
