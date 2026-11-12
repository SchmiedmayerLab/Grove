//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
@testable import GroveFHIRContract
import Testing


/// The shared identity and canonical JSON vectors, read from the grove-fhir working tree.
@Suite(.enabled(if: groveFHIRIsAvailable, "Requires the grove-fhir checkout used by FHIR Output Conformance"))
struct ExchangeProtocolVectorTests {
    private static let subject = BusinessIdentifier(
        system: "https://study.example.org/fhir/identifiers/participant",
        nonemptyValue: "participant-001"
    )

    private static func identifier(_ system: String, _ value: String) throws -> BusinessIdentifier {
        try BusinessIdentifier(system: IdentifierSystem(system), value: value)
    }

    /// A record's identity, or the output or artifact identity that extends it.
    private static func identity(
        of record: SourceRecordIdentity,
        kind: OpaqueIdentityKind,
        components: [String]
    ) throws -> RoledIdentifier {
        switch kind {
        case .sourceOutput, .providerOutput:
            try record.output(role: components[5], discriminator: components[6])
        case .sourceArtifact, .providerArtifact:
            try record.artifact(formatCode: components[5], partIndex: CanonicalNonnegativeDecimal(components[6]))
        default:
            record.identifier
        }
    }

    /// Mints an identity through the typed entry point of its kind.
    private static func identity(
        _ scope: OpaqueIdentityScope,
        kind: OpaqueIdentityKind,
        components: [String]
    ) throws -> RoledIdentifier {
        switch kind {
        case .sourceRecord, .sourceOutput, .sourceArtifact:
            let record = try scope.sourceRecord(
                adapterID: components[0],
                sourceType: components[1],
                repositoryScope: identifier(components[2], components[3]),
                nativeRecordID: components[4]
            )
            return try identity(of: record, kind: kind, components: components)
        case .providerRecord, .providerOutput, .providerArtifact:
            let record = try scope.providerRecord(
                providerCode: #require(OpaqueIdentityScope.ProviderCode(rawValue: components[0]), "\(components[0])"),
                sourceType: components[1],
                providerScope: identifier(components[2], components[3]),
                nativeRecordID: components[4]
            )
            return try identity(of: record, kind: kind, components: components)
        case .writerRecord:
            return try scope.writerRecord(
                subject: identifier(components[0], components[1]),
                writerApplication: identifier(components[2], components[3]),
                writerRecordID: components[4]
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
                tokenScope: components[3],
                stableUnitToken: components[4]
            )
        case .deviceSnapshot, .contextSnapshot:
            return try scope.contentSnapshot(
                subject: identifier(components[0], components[1]),
                role: #require(OpaqueIdentityScope.NodeRole(kind: kind, rawValue: components[2]), "\(components[2])"),
                contentDigest: components[3]
            )
        case .recordVersion:
            return try scope.recordVersion(sourceRecord: identifier(components[0], components[1]), contentDigest: components[2])
        case .recordRetraction:
            return try scope.recordRetraction(sourceRecord: identifier(components[0], components[1]))
        }
    }

    @Test("Derived identifier systems equal the shared vectors")
    func derivedSystemsMatchVectors() throws {
        let vectors = try ExchangeProtocolCatalog.current.testVectors
        let root = ExchangeProtocolCatalog.deploymentRoot
        let epoch = try KeyEpoch(vectors.epoch)
        let derived = try DeploymentIdentifierSystems.derived(root: root, keyID: vectors.keyId, epoch: epoch)
        #expect(vectors.identitySystems.count == OpaqueIdentityKind.allCases.count)
        for vector in vectors.identitySystems {
            let kind = try #require(OpaqueIdentityKind(rawValue: vector.identityKind))
            #expect(derived[kind].rawValue == vector.system, "\(vector.identityKind)")
        }
        // The systems carry no runtime check of their own: the thirteen recommended forms keep them apart.
        #expect(Set(derived.all).count == 13)
        #expect(try DeploymentIdentifierSystems.derived(root: "https://study.example.org/fhir/", keyID: vectors.keyId, epoch: epoch) == derived)
        #expect(throws: ExchangeIdentityError.invalidKeyID("bad key")) {
            try DeploymentIdentifierSystems.derived(root: root, keyID: "bad key", epoch: epoch)
        }
    }

    @Test("Every identity kind states the catalog's components")
    func identityKindComponents() throws {
        let kinds = try ExchangeProtocolCatalog.current.opaqueIdentity.identityKinds
        #expect(kinds.count == OpaqueIdentityKind.allCases.count)
        for row in kinds {
            let kind = try #require(OpaqueIdentityKind(rawValue: row.kind), "\(row.kind)")
            #expect(kind.componentNames == row.components, "\(row.kind)")
        }
    }

    @Test("Every shared identity vector is reproduced token for token")
    func identityVectors() throws {
        let vectors = try ExchangeProtocolCatalog.current.testVectors
        let scope = try vectors.scope
        for vector in vectors.identities {
            let kind = try #require(OpaqueIdentityKind(rawValue: vector.identityKind), "\(vector.id)")
            let identity = try Self.identity(scope, kind: kind, components: vector.components)
            #expect(identity.identifier.value == vector.value, "\(vector.id)")
            #expect(identity.identifier.system == scope.systems[kind], "\(vector.id)")
            #expect(identity.role == kind.identifierRole, "\(vector.id)")
        }
    }

    @Test("Every shared invalid identity vector is refused for its stated reason")
    func invalidIdentityVectors() throws {
        let catalog = try ExchangeProtocolCatalog.current
        let scope = try catalog.testVectors.scope
        for vector in catalog.testVectors.invalidIdentities {
            let kind = try #require(OpaqueIdentityKind(rawValue: vector.identityKind), "\(vector.id)")
            let names = try #require(catalog.opaqueIdentity.identityKinds.first { $0.kind == kind.rawValue }?.components)
            let expected: ExchangeIdentityError
            switch vector.expectedError {
            case "empty-component":
                expected = .emptyComponent("\(kind.rawValue).\(names[try #require(vector.components.firstIndex(of: ""))])")
            case "provider-kind-required":
                expected = .providerKindRequired(vector.components[0])
            case "non-canonical-part-index":
                expected = .nonCanonicalPartIndex("\(kind.rawValue).part-index")
            case "non-canonical-digest":
                expected = .nonCanonicalDigest("\(kind.rawValue).\(try #require(names.last))")
            default:
                Issue.record("Unknown expected error \(vector.expectedError) for \(vector.id)")
                continue
            }
            #expect(throws: expected, "\(vector.id)") {
                try scope.identifier(kind: kind, components: vector.components)
            }
        }
    }

    @Test("A snapshot's node role must be a role of its kind")
    func nodeRolesStayWithTheirKind() throws {
        let scope = try ExchangeProtocolCatalog.current.testVectors.scope
        let digest = String(repeating: "A", count: 43)
        let subject = [Self.subject.system.rawValue, Self.subject.value]
        for (kind, role) in [(OpaqueIdentityKind.deviceSnapshot, "patient"), (.contextSnapshot, "host"), (.contextSnapshot, "bogus")] {
            #expect(throws: ExchangeIdentityError.invalidNodeRole("\(kind.rawValue).node-role"), "\(kind.rawValue) \(role)") {
                try scope.identifier(kind: kind, components: subject + [role, digest])
            }
        }
    }

    @Test("Registry severities and reasons have not drifted")
    func registrySeverities() throws {
        let registry = Dictionary(uniqueKeysWithValues: try ExchangeProtocolCatalog.current.producerDiagnostics.map { ($0.code, $0) })
        #expect(registry.count == ExchangeGraphRule.allCases.count)
        for rule in ExchangeGraphRule.allCases {
            let row = try #require(registry[rule.rawValue], "\(rule.rawValue)")
            #expect(row.severity ?? .error == rule.severity, "\(rule.rawValue)")
            #expect(row.reason == rule.diagnostic.reason, "\(rule.rawValue)")
        }
    }

    @Test("Every full URL vector is reproduced")
    func fullURLVectors() throws {
        for vector in try ExchangeProtocolCatalog.current.testVectors.fullUrls {
            #expect(try Self.identifier(vector.system, vector.value).fullURLString == vector.fullUrl, "\(vector.id)")
        }
    }

    @Test("Every key fingerprint vector is reproduced, and one key gives each subject its own key id")
    func keyFingerprintVectors() throws {
        let vectors = try ExchangeProtocolCatalog.current.testVectors
        let key = SymmetricKey(data: try Data(hex: vectors.keyHex))
        for vector in vectors.keyFingerprint {
            let subject = try Self.identifier(vector.subjectSystem, vector.subjectValue)
            #expect(try OpaqueIdentityScope.keyFingerprint(of: key, subject: subject) == vector.fingerprint, "\(vector.id)")
            #expect(try OpaqueIdentityScope.recommendedKeyID(prefix: "s", key: key, subject: subject) == "s\(vector.keyIdSuffix)", "\(vector.id)")
        }
        #expect(Set(vectors.keyFingerprint.map(\.keyIdSuffix)).count == vectors.keyFingerprint.count)
        #expect(throws: ExchangeIdentityError.keyTooShort(actualBytes: 16)) {
            try OpaqueIdentityScope.keyFingerprint(of: SymmetricKey(size: .bits128), subject: Self.subject)
        }
        let suffix = try #require(vectors.keyFingerprint.first?.keyIdSuffix)
        #expect(throws: ExchangeIdentityError.invalidKeyID("bad key\(suffix)")) {
            try OpaqueIdentityScope.recommendedKeyID(prefix: "bad key", key: key, subject: Self.subject)
        }
    }

    @Test("Every canonical JSON vector is reproduced byte for byte")
    func canonicalJSONVectors() throws {
        for vector in try ExchangeProtocolCatalog.current.testVectors.canonicalJson {
            let canonical = try LosslessJSONValue(parsing: Data(vector.input.utf8)).canonicalBytes()
            #expect(canonical == Data(vector.canonical.utf8), "\(vector.id)")
            #expect(SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined() == vector.sha256, "\(vector.id)")
        }
    }

    @Test("Every invalid canonical JSON vector is refused for its stated reason")
    func invalidCanonicalJSONVectors() throws {
        for vector in try ExchangeProtocolCatalog.current.testVectors.invalidCanonicalJson {
            let reason = try #require(LosslessJSONValue.ParseError(rawValue: vector.expectedError), "\(vector.id)")
            let input = try Data(hex: vector.inputHex)
            #expect(throws: reason, "\(vector.id)") {
                try LosslessJSONValue(parsing: input)
            }
        }
    }
}
