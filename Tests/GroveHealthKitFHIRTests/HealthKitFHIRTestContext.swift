//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Fixed valid fixtures deliberately fail at test-process startup if their literals drift.
// swiftlint:disable force_try function_body_length type_contents_order

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import ModelsR4


extension Reference {
    static var testPatient: Reference {
        testLogicalReference(resourceType: .patient, value: "example")
    }

    static func testResearchStudy(_ value: String) -> Reference {
        testLogicalReference(resourceType: .researchStudy, value: value)
    }

    static func testLogicalReference(
        resourceType: ResourceType,
        value: String
    ) -> Reference {
        let identifier = try! BusinessIdentifier(
            system: "https://grovealliance.org/fhir/testing/identifiers/\(resourceType.rawValue.lowercased())",
            value: value
        )
        return Reference(
            identifier: identifier.fhirIdentifier,
            type: FHIRPrimitive(FHIRURI(stringLiteral: resourceType.rawValue))
        )
    }
}


/// Keeps older test fixtures concise while production callers use the strict event-context API.
extension HealthKitConversionContext {
    init(
        subject: Reference,
        converter: HealthKitApplication = .main,
        converterHost: HealthKitHostDevice = HealthKitHostDevice(
            sourceDeviceToken: "grove-test-host",
            operatingSystemVersion: "20.1",
            name: "Grove Test Host",
            manufacturer: "Example Device Company",
            modelNumber: "Phone One"
        ),
        graphIdentifierSystem: IdentifierSystem? = nil,
        sourceActor: HealthKitSourceActor = .application,
        converterWasGateway: Bool = false,
        conversionInstant: Date = Date(timeIntervalSince1970: 1_787_009_400),
        recordingDeviceStableUnitToken: String? = nil,
        udiDisclosurePolicy: HealthKitUDIDisclosurePolicy = .omit,
        nativeIdentifierDisclosurePolicy: HealthKitNativeIdentifierDisclosurePolicy = .omit,
        routeDisclosurePolicy: HealthKitRouteDisclosurePolicy = .omit,
        protocolCanonical: String? = nil,
        researchStudies: [Reference] = [],
        repositoryIDs: HealthKitRepositoryIDs = .init()
    ) {
        let base = graphIdentifierSystem
            ?? "https://grovealliance.org/fhir/testing/identifiers/healthkit"
        let systemRoot = base.rawValue
        let sequence = UInt64(max(1, Int64(conversionInstant.timeIntervalSince1970 * 1_000)))
        try! self.init(
            subject: subject,
            subjectIdentity: BusinessIdentifier(
                system: "https://grovealliance.org/fhir/testing/identifiers/subject",
                value: subject.identifier?.value?.value?.string
                    ?? subject.reference?.value?.string
                    ?? "identifier-subject"
            ),
            converter: converter,
            converterHost: converterHost,
            eventIdentifier: ExchangeEventIdentifier(
                system: IdentifierSystem("\(systemRoot)/event"),
                producerInstance: UUID(uuid: (
                    0x1f, 0x5c, 0x58, 0xaa, 0x6e, 0xc6, 0x4e, 0x79,
                    0xa6, 0x82, 0x82, 0x9a, 0x9d, 0xeb, 0xd3, 0xf5
                )),
                sequence: sequence
            ),
            entryNodeIdentifierSystem: IdentifierSystem("\(systemRoot)/entry-node"),
            identityScope: PseudonymousIdentityScope(
                systems: PseudonymousIdentitySystems(
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
                keyID: "test",
                epoch: 1,
                key: Data(repeating: 0x42, count: 32)
            ),
            repositoryScope: BusinessIdentifier(
                system: "\(systemRoot)/repository",
                value: "primary"
            ),
            sourceActor: sourceActor,
            converterWasGateway: converterWasGateway,
            conversionInstant: conversionInstant,
            recordingDeviceStableUnitToken: recordingDeviceStableUnitToken,
            udiDisclosurePolicy: udiDisclosurePolicy,
            nativeIdentifierDisclosurePolicy: nativeIdentifierDisclosurePolicy,
            routeDisclosurePolicy: routeDisclosurePolicy,
            protocolCanonical: protocolCanonical,
            researchStudies: researchStudies,
            repositoryIDs: repositoryIDs
        )
    }

    var graphIdentifierSystem: IdentifierSystem? {
        eventIdentifier.businessIdentifier.system
    }
}

#endif
