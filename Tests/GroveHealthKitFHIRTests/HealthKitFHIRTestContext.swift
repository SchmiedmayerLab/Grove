//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Fixed valid fixtures deliberately fail at test-process startup if their literals drift, and the
// conveniences read one graph back the way the old result types spelled it.
// swiftlint:disable force_try force_unwrapping function_body_length type_contents_order

#if canImport(HealthKit)

import CryptoKit
import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4


/// Names every unit by one fixed token, for tests that assert a recording Device regardless of the sample's device.
struct FixedTokenRecordingDeviceResolver: RecordingDeviceResolver {
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


extension ExchangeEventContext {
    static let testInstant = Date(timeIntervalSince1970: 1_787_009_400)

    static func test(
        subject: Subject = .testPatient,
        graphIdentifierSystem: IdentifierSystem? = nil,
        converter: ApplicationDevice = .test,
        converterHost: HostDevice = .test,
        converterRole: ConverterRole = .assembler,
        conversionInstant: Date = testInstant,
        studies: [StudyEnrollment] = [],
        repositoryIDs: [ExchangeGraphNode: RepositoryID] = [:]
    ) -> ExchangeEventContext {
        let base = graphIdentifierSystem ?? "https://grovealliance.org/fhir/testing/identifiers/healthkit"
        let systemRoot = base.rawValue
        let sequence = UInt64(max(1, Int64(conversionInstant.timeIntervalSince1970 * 1_000)))
        return try! ExchangeEventContext(
            subject: subject,
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
                    opaque: OpaqueIdentitySystems(
                        sourceRecord: IdentifierSystem("\(systemRoot)/source-record/test/1"),
                        sourceOutput: IdentifierSystem("\(systemRoot)/source-output/test/1"),
                        writerRecord: IdentifierSystem("\(systemRoot)/writer-record/test/1"),
                        providerRecord: IdentifierSystem("\(systemRoot)/provider-record/test/1"),
                        providerOutput: IdentifierSystem("\(systemRoot)/provider-output/test/1"),
                        sourceArtifact: IdentifierSystem("\(systemRoot)/source-artifact/test/1"),
                        providerArtifact: IdentifierSystem("\(systemRoot)/provider-artifact/test/1"),
                        sourceContext: IdentifierSystem("\(systemRoot)/source-context/test/1"),
                        recordingDevice: IdentifierSystem("\(systemRoot)/recording-device/test/1"),
                        deviceSnapshot: IdentifierSystem("\(systemRoot)/device-snapshot/test/1")
                    ),
                    event: IdentifierSystem("\(systemRoot)/event"),
                    entryNode: IdentifierSystem("\(systemRoot)/entry-node")
                ),
                keyID: "test",
                epoch: EventSequence(1),
                key: SymmetricKey(data: Data(repeating: 0x42, count: 32))
            ),
            repositoryScope: BusinessIdentifier(system: IdentifierSystem("\(systemRoot)/repository"), value: "primary"),
            application: converter,
            host: converterHost,
            conversionInstant: conversionInstant,
            converterRole: converterRole,
            studies: studies,
            repositoryIDs: repositoryIDs
        )
    }
}


/// Keeps the fixtures concise while production callers build the shared event context themselves.
extension HealthKitConversionContext {
    init(
        subject: Subject = .testPatient,
        converter: ApplicationDevice = .test,
        converterHost: HostDevice = .test,
        graphIdentifierSystem: IdentifierSystem? = nil,
        writer: HealthKitWriter = .application,
        converterWasGateway: Bool = false,
        conversionInstant: Date = ExchangeEventContext.testInstant,
        recordingDeviceStableUnitToken: String? = nil,
        udiDisclosurePolicy: HealthKitUDIDisclosurePolicy = .omit,
        nativeIdentifierDisclosurePolicy: GovernedSourceIdentifierDisclosurePolicy = .omit,
        routeDisclosurePolicy: RouteDisclosurePolicy = .omit,
        studies: [StudyEnrollment] = [],
        repositoryIDs: [ExchangeGraphNode: RepositoryID] = [:]
    ) {
        self.init(
            event: .test(
                subject: subject,
                graphIdentifierSystem: graphIdentifierSystem,
                converter: converter,
                converterHost: converterHost,
                converterRole: converterWasGateway ? .gateway : .assembler,
                conversionInstant: conversionInstant,
                studies: studies,
                repositoryIDs: repositoryIDs
            ),
            options: HealthKitConversionOptions(
                writer: writer,
                recordingDevice: recordingDeviceStableUnitToken.map { FixedTokenRecordingDeviceResolver(token: $0) }
                    ?? .healthKitLocalIdentifier,
                udiDisclosure: udiDisclosurePolicy,
                routeDisclosure: routeDisclosurePolicy,
                nativeIdentifierDisclosure: nativeIdentifierDisclosurePolicy
            )
        )
    }

    var graphIdentifierSystem: IdentifierSystem? {
        event.event.identifier.identifier.system
    }

    var subject: Subject { event.subject }
    var converter: ApplicationDevice { event.application }
    var conversionInstant: Date { event.conversionInstant }
}


extension ExchangeGraph {
    func resource<R: Resource>(_ type: R.Type, at identifier: RoledIdentifier) -> R? {
        entry(fullURL: try! identifier.fullURL)?.resource?.get(if: R.self)
    }
}


extension HealthKitConversion {
    var graphIdentifiers: ExchangeGraphIdentifiers { identifiers }
    var localSourceUUID: UUID { source.uuid }
    var sourceIdentifier: Identifier { identifiers.sourceRecord.fhirIdentifier }
    var observation: Observation { graph.resource(Observation.self, at: identifiers.primaryOutput)! }
    var document: DocumentReference { graph.resource(DocumentReference.self, at: identifiers.primaryOutput)! }
    var provenance: Provenance { graph.resource(Provenance.self, at: identifiers.provenance)! }
    var converterApplication: Device { graph.resource(Device.self, at: identifiers.applicationSnapshot)! }
    var converterHost: Device { graph.resource(Device.self, at: identifiers.hostSnapshot)! }
    var recordingDevice: Device? { identifiers.recordingDeviceSnapshot.flatMap { graph.resource(Device.self, at: $0) } }
    var sourceAuthor: Device? { identifiers.sourceAuthorSnapshot.flatMap { graph.resource(Device.self, at: $0) } }
    var sourceAuthorHost: Device? { identifiers.sourceAuthorHostSnapshot.flatMap { graph.resource(Device.self, at: $0) } }
}


extension HealthKitConversionSet {
    var graph: ExchangeGraph { primary.graph }
    var bundle: ModelsR4.Bundle { primary.bundle }
    var identifiers: ExchangeGraphIdentifiers { primary.identifiers }
    var graphIdentifiers: ExchangeGraphIdentifiers { primary.identifiers }
    var source: HealthKitSourceRecord { primary.source }
    var localSourceUUID: UUID { primary.source.uuid }
    var sourceIdentifier: Identifier { primary.sourceIdentifier }
    var observation: Observation { primary.observation }
    var document: DocumentReference { primary.document }
    var provenance: Provenance { primary.provenance }
    var converterApplication: Device { primary.converterApplication }
    var converterHost: Device { primary.converterHost }
    var recordingDevice: Device? { primary.recordingDevice }
    var sourceAuthor: Device? { primary.sourceAuthor }
    var sourceAuthorHost: Device? { primary.sourceAuthorHost }
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
