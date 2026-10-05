//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CryptoKit
import Foundation
@testable import GroveFHIRContract
import ModelsR4
import Testing


/// Pins the one-step scope of a deployment root against the two-step construction it stands for.
@Suite
struct OpaqueIdentityScopeRootTests {
    private static let root: IdentifierSystem = "https://study.example.org/fhir"
    private static let key = SymmetricKey(data: Data(repeating: 0x42, count: 32))

    @Test("The root scope derives the recommended systems and mints the same identities as the two-step scope")
    func rootScopeEqualsDerivedScope() throws {
        let scope = try OpaqueIdentityScope(root: Self.root, keyID: "key-1", epoch: EventSequence(3), key: Self.key)
        let systems = try DeploymentIdentifierSystems.derived(root: Self.root, keyID: "key-1", epoch: EventSequence(3))
        let twoStep = try OpaqueIdentityScope(systems: systems, keyID: "key-1", epoch: EventSequence(3), key: Self.key)
        #expect(scope.systems == systems)
        #expect(scope.keyID == "key-1")
        #expect(scope.epoch == EventSequence(3))
        #expect(scope.systems.event.rawValue == "https://study.example.org/fhir/NamingSystem/grove-event-v0")
        #expect(scope.systems.opaque.sourceRecord.rawValue == "https://study.example.org/fhir/NamingSystem/grove-source-record-v0/key-1/3")
        let repository = try BusinessIdentifier(system: IdentifierSystem("https://study.example.org/fhir/repository"), value: "primary")
        let minted = try scope.sourceRecord(adapterID: "healthkit", sourceType: "heart-rate", repositoryScope: repository, nativeRecordID: "abc")
        let expected = try twoStep.sourceRecord(adapterID: "healthkit", sourceType: "heart-rate", repositoryScope: repository, nativeRecordID: "abc")
        #expect(minted.identifier == expected.identifier)
        #expect(minted.identifier.identifier.value.hasPrefix("v0:key-1:3:"))
        #expect(minted.identifier.identifier.system == systems.opaque.sourceRecord)
        #expect(scope.debugDescription == "OpaqueIdentityScope(keyID: key-1, epoch: 3)")
    }

    @Test("A trailing slash on the root is dropped, as the two-step derivation drops it")
    func trailingSlashIsDropped() throws {
        let scope = try OpaqueIdentityScope(root: "https://study.example.org/fhir/", keyID: "key-1", epoch: EventSequence(1), key: Self.key)
        #expect(scope.systems.entryNode.rawValue == "https://study.example.org/fhir/NamingSystem/grove-entry-node-v0")
    }

    @Test("The root scope reports its own faults as opaque-identity errors")
    func rootScopeReportsFaults() {
        #expect(throws: ExchangeIdentityError.invalidKeyID("key one")) {
            try OpaqueIdentityScope(root: Self.root, keyID: "key one", epoch: EventSequence(1), key: Self.key)
        }
        #expect(throws: ExchangeIdentityError.invalidKeyID("")) {
            try OpaqueIdentityScope(root: Self.root, keyID: "", epoch: EventSequence(1), key: Self.key)
        }
        #expect(throws: ExchangeIdentityError.keyTooShort(actualBytes: 16)) {
            try OpaqueIdentityScope(root: Self.root, keyID: "key-1", epoch: EventSequence(1), key: SymmetricKey(size: .bits128))
        }
        #expect(throws: ExchangeIdentityError.publishedConformanceKeyProhibited) {
            try OpaqueIdentityScope(
                root: Self.root,
                keyID: "key-1",
                epoch: EventSequence(1),
                key: SymmetricKey(data: Data((0...31).map(UInt8.init)))
            )
        }
        #expect(ExchangeIdentityError.invalidDeploymentRoot("x").diagnostic.code == ExchangeGraphRule.mobileInputUnclassified.rawValue)
    }
}


@Suite
struct ExchangeProducerTests {
    private static let key = SymmetricKey(data: Data(repeating: 0x42, count: 32))

    private static func scope() throws -> OpaqueIdentityScope {
        try OpaqueIdentityScope(root: "https://study.example.org/fhir", keyID: "key-1", epoch: EventSequence(1), key: key)
    }

    private static func identifier(_ system: String, _ value: String) throws -> BusinessIdentifier {
        try BusinessIdentifier(system: IdentifierSystem(system), value: value)
    }

    private static func enrollment(
        study: BusinessIdentifier? = nil,
        enrollment: BusinessIdentifier? = nil,
        name: String = "a"
    ) throws -> StudyEnrollment {
        try StudyEnrollment(
            study: study ?? identifier("https://study.example.org/fhir/study", name),
            protocolURL: FHIRPrimitive(Canonical(stringLiteral: "https://study.example.org/PlanDefinition/\(name)")),
            protocolVersion: "1",
            enrollment: enrollment ?? identifier("https://study.example.org/fhir/enrollment", "enrollment-\(name)")
        )
    }

    private static func producer(
        subject: Subject? = nil,
        studies: [StudyEnrollment] = [],
        host: HostDevice? = nil,
        storage: ExchangeProducer.InMemoryStorage = ExchangeProducer.InMemoryStorage()
    ) throws -> ExchangeProducer {
        let scope = try scope()
        let subject = try subject ?? .logical(identifier("https://study.example.org/fhir/participant", "p-1"))
        let application = try ApplicationDevice(name: "Grove Test", bundleIdentifier: "org.grovealliance.test", version: "1.0", build: "7")
        return try ExchangeProducer(
            identityScope: scope,
            subject: subject,
            application: application,
            host: host ?? HostDevice(operatingSystemVersion: "20.1", name: "Host", manufacturer: "Example", modelNumber: "Phone1"),
            studies: studies,
            storage: storage
        )
    }

    @Test("A producer keeps every input it was built from")
    func producerKeepsItsInputs() throws {
        let scope = try Self.scope()
        let subject = Subject.logical(try Self.identifier("https://study.example.org/fhir/participant", "p-1"))
        let application = try ApplicationDevice(name: "Grove Test", bundleIdentifier: "org.grovealliance.test", version: "1.0")
        let host = try HostDevice(operatingSystemVersion: "20.1")
        let studies = [try Self.enrollment(name: "a"), try Self.enrollment(name: "b")]
        let storage = ExchangeProducer.InMemoryStorage()
        let producer = try ExchangeProducer(
            identityScope: scope,
            subject: subject,
            application: application,
            host: host,
            studies: studies,
            storage: storage
        )
        #expect(producer.identityScope.systems == scope.systems)
        #expect(producer.subject == subject)
        #expect(producer.application == application)
        #expect(producer.host == host)
        #expect(producer.studies == studies)
        #expect(producer.ledger.storage as? ExchangeProducer.InMemoryStorage === storage)
        #expect(producer.facts == ExchangeEventFacts(application: application, host: host, studies: studies))
    }

    /// An integrator rebuilds the producer whenever its facts change, so a call through an old producer can overlap a
    /// redelivery through a new one. Holds are the process's, not the producer's: the first call's release leaves the
    /// event the other call still holds, so that call's redelivery restates it, and the last holder's release removes it.
    @Test("Producers over one storage share the process's holds: a release keeps the event another producer's call holds")
    func producersShareTheProcessHolds() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let request = ExchangeEventRequest(key: ExchangeEventKey(kind: .active, adapterID: "healthkit", sourceRecord: "a"), fingerprint: "context")
        let instant = Date(timeIntervalSince1970: 1_791_023_400)
        let (first, firstReceipt) = try Self.producer(storage: storage).reserve([request], at: instant)
        let (again, againReceipt) = try Self.producer(storage: storage).reserve([request], at: instant.addingTimeInterval(60))
        #expect(again == first)
        firstReceipt.release()
        let (retried, retriedReceipt) = try Self.producer(storage: storage).reserve([request], at: instant.addingTimeInterval(120))
        #expect(retried == first, "the rebuilt producer's call still holds the event")
        againReceipt.release()
        retriedReceipt.release()
        let (next, _) = try Self.producer(storage: storage).reserve([request], at: instant)
        #expect(first[request]?.sequence == EventSequence(1))
        #expect(next[request]?.sequence == EventSequence(2))
    }

    @Test("The host and the studies default to the current host and no enrollment")
    func defaultsDescribeThisHost() throws {
        let producer = try ExchangeProducer(
            identityScope: Self.scope(),
            subject: .logical(Self.identifier("https://study.example.org/fhir/participant", "p-1")),
            application: ApplicationDevice(name: "Grove Test", bundleIdentifier: "org.grovealliance.test", version: "1.0"),
            storage: ExchangeProducer.InMemoryStorage()
        )
        #expect(producer.host.operatingSystemVersion == HostDevice.current().operatingSystemVersion)
        #expect(producer.host.sourceDeviceToken == HostDevice.current().sourceDeviceToken)
        #expect(producer.studies.isEmpty)
    }

    @Test("A bundled subject is accepted with its pseudonym")
    func bundledSubjectIsAccepted() throws {
        let pseudonym = try Self.identifier("https://study.example.org/fhir/participant", "p-1")
        let producer = try Self.producer(subject: .bundled(pseudonym, Patient()))
        #expect(producer.subject.identifier == pseudonym)
    }

    @Test("A subject numbered in a deployment identity system is refused")
    func reservedSubjectSystemIsRefused() throws {
        let systems = try Self.scope().systems
        for system in systems.opaque.all + [systems.event, systems.entryNode] {
            let subject = Subject.logical(try BusinessIdentifier(system: system, value: "p-1"))
            #expect(throws: ExchangeProducer.ConfigurationError.reservedSubjectIdentifierSystem(system)) {
                try Self.producer(subject: subject)
            }
            #expect(throws: ExchangeProducer.ConfigurationError.reservedSubjectIdentifierSystem(system)) {
                try Self.producer(subject: .bundled(BusinessIdentifier(system: system, value: "p-1"), Patient()))
            }
        }
    }

    @Test("A study or enrollment numbered in a deployment identity system is refused")
    func reservedStudySystemIsRefused() throws {
        let systems = try Self.scope().systems
        let reservedStudy = try BusinessIdentifier(system: systems.event, value: "study")
        #expect(throws: ExchangeProducer.ConfigurationError.reservedStudyIdentifierSystem(systems.event)) {
            try Self.producer(studies: [Self.enrollment(study: reservedStudy)])
        }
        let reservedEnrollment = try BusinessIdentifier(system: systems.opaque.sourceRecord, value: "enrollment")
        #expect(throws: ExchangeProducer.ConfigurationError.reservedStudyIdentifierSystem(systems.opaque.sourceRecord)) {
            try Self.producer(studies: [Self.enrollment(name: "a"), Self.enrollment(enrollment: reservedEnrollment, name: "b")])
        }
    }

    @Test("The same study or enrollment listed twice is refused")
    func duplicateEnrollmentsAreRefused() throws {
        let study = try Self.identifier("https://study.example.org/fhir/study", "shared")
        #expect(throws: ExchangeProducer.ConfigurationError.duplicateStudy(study)) {
            try Self.producer(studies: [Self.enrollment(study: study, name: "a"), Self.enrollment(study: study, name: "b")])
        }
        let enrollment = try Self.identifier("https://study.example.org/fhir/enrollment", "shared")
        #expect(throws: ExchangeProducer.ConfigurationError.duplicateEnrollment(enrollment)) {
            try Self.producer(studies: [Self.enrollment(enrollment: enrollment, name: "a"), Self.enrollment(enrollment: enrollment, name: "b")])
        }
        #expect(try Self.producer(studies: [Self.enrollment(name: "a"), Self.enrollment(name: "b")]).studies.count == 2)
    }

    @Test("Facts the ledger cannot read back are refused: a study protocol canonical with an empty URL")
    func unfreezableFactsAreRefused() throws {
        // Foundation builds a URL with empty text from empty components; no canonical text states it.
        let empty = try #require(URLComponents().url)
        #expect(empty.absoluteString.isEmpty)
        let study = try StudyEnrollment(
            study: Self.identifier("https://study.example.org/fhir/study", "a"),
            protocolURL: FHIRPrimitive(Canonical(empty)),
            protocolVersion: "1",
            enrollment: Self.identifier("https://study.example.org/fhir/enrollment", "enrollment-a")
        )
        #expect(throws: ExchangeProducer.ConfigurationError.unfreezableFacts) {
            try Self.producer(studies: [study])
        }
        #expect(try Self.producer(studies: [Self.enrollment(name: "a")]).studies.count == 1)
    }

    @Test("Every configuration fault reports the unclassified input diagnostic at the producer")
    func configurationFaultsReportOneDiagnostic() throws {
        let identifier = try Self.identifier("https://study.example.org/fhir/study", "s")
        let faults: [ExchangeProducer.ConfigurationError] = [
            .reservedSubjectIdentifierSystem(identifier.system),
            .reservedStudyIdentifierSystem(identifier.system),
            .duplicateStudy(identifier),
            .duplicateEnrollment(identifier),
            .unfreezableFacts
        ]
        for fault in faults {
            #expect(fault.diagnostic.code == ExchangeGraphRule.mobileInputUnclassified.rawValue)
            #expect(fault.diagnostic.location == "ExchangeProducer")
        }
    }
}
