//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


private let groveFHIRRoot: URL = {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let candidates = [
        repositoryRoot.appendingPathComponent(".fhir/grove-fhir", isDirectory: true),
        repositoryRoot.deletingLastPathComponent().appendingPathComponent("grove-fhir", isDirectory: true)
    ]
    return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("catalog").path) } ?? candidates[0]
}()

private struct MissingEvent: Error {
    let name: String
}

private let groveFHIRIsAvailable = FileManager.default.fileExists(
    atPath: groveFHIRRoot.appendingPathComponent("catalog/exchange-protocol.json").path
)


/// Every optional parameter defaults the same way on every platform, and every disclosure omits.
@Suite
struct ProducerDefaultsTests {
    @Test("The event context defaults to an assembler without studies or repository rows")
    func eventContextDefaults() {
        let base = ExchangeEventContext.test()
        let context = ExchangeEventContext(
            subject: base.subject,
            event: base.event,
            identityScope: base.identityScope,
            repositoryScope: base.repositoryScope,
            application: base.application,
            host: base.host,
            conversionInstant: base.conversionInstant
        )
        #expect(context.converterRole == .assembler)
        #expect(context.studies.isEmpty)
        #expect(context.repositoryIDs.isEmpty)
    }

    @Test("Device facts default to nothing beyond what identifies the device")
    func deviceDefaults() throws {
        let application = try ApplicationDevice(name: "Grove", bundleIdentifier: "org.grovealliance.app", version: "1.0")
        #expect(application.build == nil)

        let host = try HostDevice(operatingSystemVersion: "26.0")
        #expect(host.name == nil && host.manufacturer == nil && host.modelNumber == nil)
        let current = HostDevice.current()
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #expect(current.operatingSystemVersion == "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
        #expect(current.name == nil && current.manufacturer == nil && current.modelNumber == nil)

        let recording = try RecordingDevice(stableUnitToken: "unit-1")
        #expect(recording.name == nil && recording.manufacturer == nil && recording.modelNumber == nil)
    }

    @Test("Every HealthKit disclosure omits and the recording device resolves by local identifier")
    func healthKitOptionDefaults() {
        for options in [HealthKitConversionOptions(), .default, HealthKitConversionContext(event: .test()).options] {
            #expect(options.writer == .application)
            #expect(options.recordingDevice is HealthKitLocalIdentifierResolver)
            #expect(options.udiDisclosure == .omit)
            #expect(options.routeDisclosure == .omit)
            #expect(options.nativeIdentifierDisclosure == .omit)
        }
    }

    @Test("Optional identifiers default to nil")
    func identifierDefaults() throws {
        guard case .authorized(_, let type) = GovernedSourceIdentifierDisclosurePolicy.authorized(system: "https://store.example.org") else {
            Issue.record("An authorized policy keeps its shape")
            return
        }
        #expect(type == nil)

        let scope = ExchangeEventContext.test().identityScope
        let output = try scope.sourceOutput(
            adapterID: "healthkit",
            sourceType: "HKQuantityTypeIdentifierHeartRate",
            repositoryScope: ExchangeEventContext.test().repositoryScope,
            nativeRecordID: "record-1",
            outputRole: "primary",
            outputDiscriminator: "0"
        )
        let target = try RetractionTarget(identifier: output, resourceType: .observation, role: .primaryOutput)
        #expect(target.nativeRecordIdentifier == nil)
    }
}


/// A warning is one registered `mobile-omission.*` row, and only those rows carry the warning severity.
@Suite
struct ProducerWarningTests {
    private static let warnings: [HealthKitConversionWarning] = [
        .recordingDeviceOmitted(deviceName: "Example Watch"),
        .sourceOffsetUnavailable,
        .unmodeledMetadataWithheld(keys: ["com.example.custom"])
    ]

    private static func heartRate(device: HKDevice, metadata: [String: Any]) -> HKQuantitySample {
        let start = ExchangeEventContext.testInstant
        return HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 72),
            start: start,
            end: start,
            device: device,
            metadata: metadata
        )
    }

    @Test("Each warning case is one registry row of severity warning")
    func warningsAreWarningRows() throws {
        let codes = Self.warnings.map(\.diagnostic.code)
        #expect(codes == [
            "mobile-omission.recording-device",
            "mobile-omission.source-offset",
            "mobile-omission.unmodeled-metadata"
        ])
        for warning in Self.warnings {
            let rule = try #require(ExchangeGraphRule(rawValue: warning.diagnostic.code))
            #expect(rule.severity == .warning)
            #expect(warning.diagnostic == rule.diagnostic)
            #expect(warning.diagnostic.severity == .warning)
        }
        #expect(Set(ExchangeGraphRule.allCases.filter { $0.severity == .warning }.map(\.rawValue)) == Set(codes))
    }

    @Test("Every error the adapters raise maps to a rule of severity error")
    func errorsAreErrorRows() {
        let errors: [HealthKitConversionError] = [
            .unsupportedSourceType(.workout),
            .invalidValue(.heartRate, .shapeInvalid),
            .ecgEvidence(.mismatchedSymptomContext)
        ]
        for error in errors {
            #expect(error.diagnostic.severity == .error)
            #expect(ExchangeGraphRule(rawValue: error.diagnostic.code)?.severity == .error)
        }
    }

    @Test("A conversion reports exactly what the graph lost")
    func conversionReportsOmissions() throws {
        let converter = HealthKitConverter()
        let context = HealthKitConversionContext()
        let unidentified = HKDevice(
            name: "Example Watch",
            manufacturer: "Example",
            model: "W42",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
        let identified = HKDevice(
            name: "Example Watch",
            manufacturer: "Example",
            model: "W42",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: "unit-42",
            udiDeviceIdentifier: "udi-42"
        )

        let lossy = try converter.convert(Self.heartRate(device: unidentified, metadata: [:]), context: context)
        #expect(Set(lossy.warnings) == [.recordingDeviceOmitted(deviceName: "Example Watch"), .sourceOffsetUnavailable])

        let withheld = try converter.convert(
            Self.heartRate(device: identified, metadata: [HKMetadataKeyTimeZone: "America/Los_Angeles", "com.example.custom": "x"]),
            context: context
        )
        #expect(withheld.warnings == [.unmodeledMetadataWithheld(keys: ["com.example.custom"])])

        let complete = try converter.convert(
            Self.heartRate(device: identified, metadata: [HKMetadataKeyTimeZone: "America/Los_Angeles"]),
            context: context
        )
        #expect(complete.warnings.isEmpty, "the omitted UDI is the deployment's disclosure choice, not a loss")
    }
}


/// The shared protocol vectors, read from the grove-fhir working tree.
@Suite(.enabled(if: groveFHIRIsAvailable, "Requires the grove-fhir checkout used by FHIR Output Conformance"))
struct ProducerContractVectorTests {
    private struct Catalog: Decodable {
        struct IdentitySystem: Decodable {
            let identityKind: String
            let system: String
        }

        struct Identity: Decodable {
            let id: String
            let identityKind: String
            let components: [String]
            let value: String
        }

        struct InvalidIdentity: Decodable {
            let id: String
            let identityKind: String
            let components: [String]
            let expectedError: String
        }

        struct System: Decodable {
            let system: String
        }

        struct Vectors: Decodable {
            let keyId: String
            let epoch: String
            let identitySystems: [IdentitySystem]
            let identities: [Identity]
            let invalidIdentities: [InvalidIdentity]
            let event: System
            let entryNode: System
        }

        struct Diagnostic: Decodable {
            let code: String
            let reason: String
            let severity: ExchangeGraphDiagnostic.Severity?
        }

        let testVectors: Vectors
        let producerDiagnostics: [Diagnostic]
    }

    private static let deploymentRoot: IdentifierSystem = "https://study.example.org/fhir"

    private static var catalog: Catalog {
        get throws {
            try JSONDecoder().decode(
                Catalog.self,
                from: Data(contentsOf: groveFHIRRoot.appendingPathComponent("catalog/exchange-protocol.json"))
            )
        }
    }

    private static func scope(_ vectors: Catalog.Vectors) throws -> OpaqueIdentityScope {
        let epoch = try EventSequence(vectors.epoch)
        let systems = try DeploymentIdentifierSystems.derived(root: deploymentRoot, keyID: vectors.keyId, epoch: epoch)
        return try OpaqueIdentityScope.conformanceTesting(systems: systems, keyID: vectors.keyId, epoch: epoch)
    }

    private static func identity(
        _ scope: OpaqueIdentityScope,
        kind: OpaqueIdentityKind,
        components: [String]
    ) throws -> RoledIdentifier {
        func identifier(_ system: String, _ value: String) throws -> BusinessIdentifier {
            try BusinessIdentifier(system: IdentifierSystem(system), value: value)
        }
        func provider(_ code: String) throws -> GroveProviderCode {
            try #require(GroveProviderCode(rawValue: code), "\(code)")
        }
        switch kind {
        case .sourceRecord:
            return try scope.sourceRecord(
                adapterID: components[0],
                sourceType: components[1],
                repositoryScope: identifier(components[2], components[3]),
                nativeRecordID: components[4]
            )
        case .sourceOutput:
            return try scope.sourceOutput(
                adapterID: components[0],
                sourceType: components[1],
                repositoryScope: identifier(components[2], components[3]),
                nativeRecordID: components[4],
                outputRole: components[5],
                outputDiscriminator: components[6]
            )
        case .sourceArtifact:
            return try scope.sourceArtifact(
                adapterID: components[0],
                sourceType: components[1],
                repositoryScope: identifier(components[2], components[3]),
                nativeRecordID: components[4],
                formatCode: components[5],
                partIndex: CanonicalNonnegativeDecimal(components[6])
            )
        case .providerRecord:
            return try scope.providerRecord(
                providerCode: provider(components[0]),
                sourceType: components[1],
                providerScope: identifier(components[2], components[3]),
                nativeRecordID: components[4]
            )
        case .providerOutput:
            return try scope.providerOutput(
                providerCode: provider(components[0]),
                sourceType: components[1],
                providerScope: identifier(components[2], components[3]),
                nativeRecordID: components[4],
                outputRole: components[5],
                outputDiscriminator: components[6]
            )
        case .providerArtifact:
            return try scope.providerArtifact(
                providerCode: provider(components[0]),
                sourceType: components[1],
                providerScope: identifier(components[2], components[3]),
                nativeRecordID: components[4],
                formatCode: components[5],
                partIndex: CanonicalNonnegativeDecimal(components[6])
            )
        case .writerRecord:
            return try scope.writerRecord(
                writerApplication: identifier(components[0], components[1]),
                writerRecordID: components[2]
            )
        case .sourceContext:
            return try scope.sourceContext(
                adapterID: components[0],
                contextType: components[1],
                repositoryScope: identifier(components[2], components[3]),
                nativeContextID: components[4]
            )
        case .recordingDevice:
            return try scope.recordingDevice(
                adapterID: components[0],
                subject: identifier(components[1], components[2]),
                stableUnitToken: components[3]
            )
        case .deviceSnapshot:
            return try scope.deviceSnapshot(
                event: ExchangeEventIdentifier(identifier(components[0], components[1])),
                role: #require(DeviceSnapshotRole(rawValue: components[2]), "\(components[2])"),
                sourceDeviceToken: components[3]
            )
        }
    }

    @Test("Derived identifier systems equal the shared vectors")
    func derivedSystemsMatchVectors() throws {
        let vectors = try Self.catalog.testVectors
        let epoch = try EventSequence(vectors.epoch)
        let derived = try DeploymentIdentifierSystems.derived(root: Self.deploymentRoot, keyID: vectors.keyId, epoch: epoch)
        #expect(vectors.identitySystems.count == OpaqueIdentityKind.allCases.count)
        for vector in vectors.identitySystems {
            let kind = try #require(OpaqueIdentityKind(rawValue: vector.identityKind))
            #expect(derived.opaque[kind].rawValue == vector.system, "\(vector.identityKind)")
        }
        #expect(derived.event.rawValue == vectors.event.system)
        #expect(derived.entryNode.rawValue == vectors.entryNode.system)
        #expect(try DeploymentIdentifierSystems.derived(root: "https://study.example.org/fhir/", keyID: vectors.keyId, epoch: epoch) == derived)
        #expect(throws: ExchangeIdentityError.invalidKeyID("bad key")) {
            try DeploymentIdentifierSystems.derived(root: Self.deploymentRoot, keyID: "bad key", epoch: epoch)
        }
    }

    @Test("Every shared identity vector is reproduced token for token")
    func identityVectors() throws {
        let vectors = try Self.catalog.testVectors
        let scope = try Self.scope(vectors)
        for vector in vectors.identities {
            let kind = try #require(OpaqueIdentityKind(rawValue: vector.identityKind), "\(vector.id)")
            let identity = try Self.identity(scope, kind: kind, components: vector.components)
            #expect(identity.value == vector.value, "\(vector.id)")
            #expect(identity.system == scope.systems.opaque[kind], "\(vector.id)")
        }
    }

    @Test("Every shared invalid identity vector is refused for its stated reason")
    func invalidIdentityVectors() throws {
        let vectors = try Self.catalog.testVectors
        let scope = try Self.scope(vectors)
        for vector in vectors.invalidIdentities {
            let kind = try #require(OpaqueIdentityKind(rawValue: vector.identityKind), "\(vector.id)")
            switch vector.expectedError {
            case "empty-component":
                #expect(throws: (any Error).self, "\(vector.id)") {
                    try Self.identity(scope, kind: kind, components: vector.components)
                }
            case "provider-kind-required":
                #expect(throws: OpaqueIdentityError.providerKindRequired(vector.components[0]), "\(vector.id)") {
                    try Self.identity(scope, kind: kind, components: vector.components)
                }
            default:
                Issue.record("Unknown expected error \(vector.expectedError) for \(vector.id)")
            }
        }
    }

    @Test("Registry severities have not drifted")
    func registrySeverities() throws {
        let registry = Dictionary(uniqueKeysWithValues: try Self.catalog.producerDiagnostics.map { ($0.code, $0) })
        #expect(registry.count == ExchangeGraphRule.allCases.count)
        for rule in ExchangeGraphRule.allCases {
            let row = try #require(registry[rule.rawValue], "\(rule.rawValue)")
            #expect(row.severity ?? .error == rule.severity, "\(rule.rawValue)")
            #expect(row.reason == rule.diagnostic.reason, "\(rule.rawValue)")
        }
    }

    @Test("The study-attribution source event is a complete bundled study context")
    func studyAttributionSourceEvent() throws {
        let path = groveFHIRRoot.appendingPathComponent("Conformance/corpora/study-attribution/source-event.json")
        _ = try ExchangeGraph(kind: .active, jsonData: Data(contentsOf: path))
    }

    @Test("Receiver-lifecycle retries are compared over lossless JSON tokens")
    func equalityVectors() throws {
        struct Events: Decodable {
            struct Event: Decodable {
                let path: String
            }

            let events: [String: Event]
        }
        let corpus = groveFHIRRoot.appendingPathComponent(ExchangeContract.equalityVectorCorpus, isDirectory: true)
        let events = try JSONDecoder().decode(Events.self, from: Data(contentsOf: corpus.appendingPathComponent("events.json"))).events
        func graph(_ name: String, kind: ExchangeGraphKind = .active) throws -> ExchangeGraph {
            guard let event = events[name] else {
                throw MissingEvent(name: name)
            }
            return try ExchangeGraph(kind: kind, jsonData: Data(contentsOf: corpus.appendingPathComponent(event.path)))
        }
        let original = try graph("original")
        let reformatted = try graph(ExchangeContract.equalityFormattingVector)
        let lexeme = try graph(ExchangeContract.equalityDecimalLexemeVector)
        let altered = try graph("altered-retry")

        #expect(original.isSemanticallyEqual(to: original))
        #expect(original.isSemanticallyEqual(to: reformatted))
        #expect(reformatted.isSemanticallyEqual(to: original))
        #expect(!original.isSemanticallyEqual(to: lexeme))
        #expect(!original.isSemanticallyEqual(to: altered))
        #expect(original.eventIdentifier == reformatted.eventIdentifier)
        #expect(original.eventIdentifier == lexeme.eventIdentifier)

        let retraction = try graph("retraction", kind: .retraction)
        let provenance = try #require(retraction.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        let targets = try provenance.target.map { try RoledIdentifier(#require($0.identifier)) }
        #expect(!targets.isEmpty)
        #expect(targets.allSatisfy { $0.role == .sourceOutput || $0.role == .deviceSnapshot })
    }
}

#endif
