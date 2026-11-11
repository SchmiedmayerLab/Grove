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


/// The test deployment: the subject, identity scope and repository scope every export states, and the application, host
/// and instant a producer states.
struct TestDeployment {
    static let testInstant = Date(timeIntervalSince1970: 1_787_009_400)

    let subject: Subject
    let identityScope: OpaqueIdentityScope
    let repositoryScope: BusinessIdentifier
    let application: ApplicationDevice
    let host: HostDevice
    let conversionInstant: Date

    /// The envelope every record of this deployment states.
    var envelope: ExchangeEnvelope {
        ExchangeEnvelope(
            scope: ExchangeEnvelope.Scope(
                adapter: HealthKitAssembly.adapter,
                identityScope: identityScope,
                subject: subject,
                repositoryScope: repositoryScope
            ),
            facts: ConversionFacts(application: application, host: host, studies: [])
        )
    }

    /// The test deployment rooted at `graphIdentifierSystem`.
    static func test(graphIdentifierSystem: IdentifierSystem? = nil, conversionInstant: Date = testInstant) -> TestDeployment {
        let base = graphIdentifierSystem ?? "https://grovealliance.org/fhir/testing/identifiers/healthkit"
        let systemRoot = base.rawValue
        return try! TestDeployment(
            subject: .testPatient,
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
                    contextSnapshot: IdentifierSystem("\(systemRoot)/context-snapshot/test/1"),
                    recordVersion: IdentifierSystem("\(systemRoot)/record-version/test/1"),
                    recordRetraction: IdentifierSystem("\(systemRoot)/record-retraction/test/1"),
                    deviceLocalIdentifier: IdentifierSystem("\(systemRoot)/device-local-identifier")
                ),
                keyID: "test",
                epoch: KeyEpoch(1),
                key: SymmetricKey(data: Data(repeating: 0x42, count: 32))
            ),
            repositoryScope: BusinessIdentifier(system: IdentifierSystem("\(systemRoot)/repository"), value: "primary"),
            application: .test,
            host: .test,
            conversionInstant: conversionInstant
        )
    }

    /// The retraction of `sourceRecord` under this deployment, recorded at its instant.
    func retraction(
        of sourceRecord: RoledIdentifier,
        targets: [RetractionRecord.Target],
        occurred: RetractionRecord.Occurrence
    ) throws(RetractionRecord.ValidationError) -> RetractionRecord {
        try ExchangeGraphAssembler(envelope: envelope).retraction(of: sourceRecord, targets: targets, occurred: occurred, at: conversionInstant)
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
        productType: "Phone One",
        name: "Grove Test Host",
        manufacturer: "Example Device Company"
    )
}


extension ExchangeRecord {
    /// The record's one-record Bundle, read back and validated the way a stored record is.
    var graph: ExchangeGraph {
        try! ExchangeGraph(validating: json, kind: kind == .active ? .active : .retraction)
    }

    /// The record's one-record Bundle, decoded.
    var bundle: ModelsR4.Bundle {
        try! JSONDecoder().decode(ModelsR4.Bundle.self, from: json)
    }
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
