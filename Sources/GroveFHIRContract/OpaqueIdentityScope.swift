//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The exact typed constructors form one auditable protocol surface.
// swiftlint:disable function_parameter_count type_body_length

#if canImport(CryptoKit)
public import CryptoKit
#else
public import Crypto
#endif
import Foundation


/// The deployment-owned, key-epoch-specific scope that mints every opaque identity.
///
/// The systems are deliberately supplied by the deployment. Grove publishes no global namespace,
/// because the same clear source identity must not be linkable across unrelated studies.
/// Debug output prints the key id and epoch only; the key never leaves the scope.
@DebugDescription
public struct OpaqueIdentityScope: Sendable, CustomDebugStringConvertible {
    private static let publishedConformanceKey = SymmetricKey(data: Data((0...31).map(UInt8.init)))

    public let systems: DeploymentIdentifierSystems
    public let keyID: String
    public let epoch: EventSequence
    private let key: SymmetricKey

    public var debugDescription: String {
        "OpaqueIdentityScope(keyID: \(keyID), epoch: \(epoch.rawValue))"
    }

    /// Creates one identity scope.
    ///
    /// Keys shorter than 256 bits are rejected. `keyID` is wire-visible and therefore restricted
    /// to an unambiguous ASCII token; it is a selector, never secret key material.
    public init(
        systems: DeploymentIdentifierSystems,
        keyID: String,
        epoch: EventSequence,
        key: SymmetricKey
    ) throws(OpaqueIdentityError) {
        try self.init(
            systems: systems,
            keyID: keyID,
            epoch: epoch,
            key: key,
            permitsPublishedConformanceKey: false
        )
    }

    private init(
        systems: DeploymentIdentifierSystems,
        keyID: String,
        epoch: EventSequence,
        key: SymmetricKey,
        permitsPublishedConformanceKey: Bool
    ) throws(OpaqueIdentityError) {
        guard Self.isValidKeyID(keyID) else {
            throw .invalidKeyID(keyID)
        }
        guard key.bitCount >= 256 else {
            throw .keyTooShort(actualBytes: key.bitCount / 8)
        }
        guard permitsPublishedConformanceKey || key != Self.publishedConformanceKey else {
            throw .publishedConformanceKeyProhibited
        }
        self.systems = systems
        self.keyID = keyID
        self.epoch = epoch
        self.key = key
    }

    /// Constructs the normative vector scope for tests in this package without exposing a
    /// production bypass for the published conformance key.
    package static func conformanceTesting(
        systems: DeploymentIdentifierSystems,
        keyID: String,
        epoch: EventSequence
    ) throws(OpaqueIdentityError) -> Self {
        try Self(
            systems: systems,
            keyID: keyID,
            epoch: epoch,
            key: publishedConformanceKey,
            permitsPublishedConformanceKey: true
        )
    }

    static func isValidKeyID(_ keyID: String) -> Bool {
        !keyID.isEmpty && keyID.utf8.allSatisfy {
            $0.isASCIIAlphaNumeric || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
        }
    }

    /// Derives a typed opaque identifier.
    ///
    /// The HMAC preimage is the ordered sequence of unsigned 32-bit big-endian UTF-8 lengths and
    /// bytes for the protocol label, identity kind, and every typed component. Delimiters are not
    /// special and supplementary Unicode scalars are encoded as their ordinary UTF-8 bytes.
    private func identifier(
        role: GroveIdentifierRole,
        kind: OpaqueIdentityKind,
        components: [String]
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        guard components.count == kind.componentCount else {
            throw .invalidComponentCount(kind: kind, expected: kind.componentCount, actual: components.count)
        }
        let input = try LengthFramedUTF8.encode(["org.grovealliance.fhir.identity.v0", kind.rawValue] + components)
        let digest = Data(HMAC<SHA256>.authenticationCode(for: input, using: key)).base64URLEncodedStringWithoutPadding
        return RoledIdentifier(
            identifier: BusinessIdentifier(system: systems.opaque[kind], nonemptyValue: "v0:\(keyID):\(epoch.rawValue):\(digest)"),
            role: role
        )
    }

    public func sourceRecord(
        adapterID: String,
        sourceType: String,
        repositoryScope: BusinessIdentifier,
        nativeRecordID: String
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try validateNonempty([
            ("adapterID", adapterID),
            ("sourceType", sourceType),
            ("nativeRecordID", nativeRecordID)
        ])
        try validateGenericAdapterID(adapterID)
        return try identifier(
            role: .sourceRecord,
            kind: .sourceRecord,
            components: [
                adapterID,
                sourceType,
                repositoryScope.system.rawValue,
                repositoryScope.value,
                nativeRecordID
            ]
        )
    }

    public func providerRecord(
        providerCode: GroveProviderCode,
        sourceType: String,
        providerScope: BusinessIdentifier,
        nativeRecordID: String
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try validateNonempty([
            ("sourceType", sourceType),
            ("nativeRecordID", nativeRecordID)
        ])
        return try identifier(
            role: .sourceRecord,
            kind: .providerRecord,
            components: [
                providerCode.rawValue,
                sourceType,
                providerScope.system.rawValue,
                providerScope.value,
                nativeRecordID
            ]
        )
    }

    public func sourceOutput(
        adapterID: String,
        sourceType: String,
        repositoryScope: BusinessIdentifier,
        nativeRecordID: String,
        outputRole: String,
        outputDiscriminator: String
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try validateNonempty([
            ("adapterID", adapterID),
            ("sourceType", sourceType),
            ("nativeRecordID", nativeRecordID),
            ("outputRole", outputRole),
            ("outputDiscriminator", outputDiscriminator)
        ])
        try validateGenericAdapterID(adapterID)
        try validateCodeToken(outputRole, field: "outputRole")
        return try identifier(
            role: .sourceOutput,
            kind: .sourceOutput,
            components: [
                adapterID,
                sourceType,
                repositoryScope.system.rawValue,
                repositoryScope.value,
                nativeRecordID,
                outputRole,
                outputDiscriminator
            ]
        )
    }

    public func providerOutput(
        providerCode: GroveProviderCode,
        sourceType: String,
        providerScope: BusinessIdentifier,
        nativeRecordID: String,
        outputRole: String,
        outputDiscriminator: String
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try validateNonempty([
            ("sourceType", sourceType),
            ("nativeRecordID", nativeRecordID),
            ("outputRole", outputRole),
            ("outputDiscriminator", outputDiscriminator)
        ])
        try validateCodeToken(outputRole, field: "outputRole")
        return try identifier(
            role: .sourceOutput,
            kind: .providerOutput,
            components: [
                providerCode.rawValue,
                sourceType,
                providerScope.system.rawValue,
                providerScope.value,
                nativeRecordID,
                outputRole,
                outputDiscriminator
            ]
        )
    }

    public func writerRecord(
        writerApplication: BusinessIdentifier,
        writerRecordID: String
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try validateNonempty([("writerRecordID", writerRecordID)])
        return try identifier(
            role: .writerRecord,
            kind: .writerRecord,
            components: [
                writerApplication.system.rawValue,
                writerApplication.value,
                writerRecordID
            ]
        )
    }

    public func sourceArtifact(
        adapterID: String,
        sourceType: String,
        repositoryScope: BusinessIdentifier,
        nativeRecordID: String,
        formatCode: String,
        partIndex: CanonicalNonnegativeDecimal
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try validateNonempty([
            ("adapterID", adapterID),
            ("sourceType", sourceType),
            ("nativeRecordID", nativeRecordID),
            ("formatCode", formatCode)
        ])
        try validateGenericAdapterID(adapterID)
        return try identifier(
            role: .sourceArtifact,
            kind: .sourceArtifact,
            components: [
                adapterID,
                sourceType,
                repositoryScope.system.rawValue,
                repositoryScope.value,
                nativeRecordID,
                formatCode,
                partIndex.rawValue
            ]
        )
    }

    /// Convenience for a locally machine-sized source-artifact part index.
    public func sourceArtifact(
        adapterID: String,
        sourceType: String,
        repositoryScope: BusinessIdentifier,
        nativeRecordID: String,
        formatCode: String,
        partIndex: UInt64
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try sourceArtifact(
            adapterID: adapterID,
            sourceType: sourceType,
            repositoryScope: repositoryScope,
            nativeRecordID: nativeRecordID,
            formatCode: formatCode,
            partIndex: CanonicalNonnegativeDecimal(partIndex)
        )
    }

    public func providerArtifact(
        providerCode: GroveProviderCode,
        sourceType: String,
        providerScope: BusinessIdentifier,
        nativeRecordID: String,
        formatCode: String,
        partIndex: CanonicalNonnegativeDecimal
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try validateNonempty([
            ("sourceType", sourceType),
            ("nativeRecordID", nativeRecordID),
            ("formatCode", formatCode)
        ])
        return try identifier(
            role: .sourceArtifact,
            kind: .providerArtifact,
            components: [
                providerCode.rawValue,
                sourceType,
                providerScope.system.rawValue,
                providerScope.value,
                nativeRecordID,
                formatCode,
                partIndex.rawValue
            ]
        )
    }

    /// Convenience for a locally machine-sized provider-artifact part index.
    public func providerArtifact(
        providerCode: GroveProviderCode,
        sourceType: String,
        providerScope: BusinessIdentifier,
        nativeRecordID: String,
        formatCode: String,
        partIndex: UInt64
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try providerArtifact(
            providerCode: providerCode,
            sourceType: sourceType,
            providerScope: providerScope,
            nativeRecordID: nativeRecordID,
            formatCode: formatCode,
            partIndex: CanonicalNonnegativeDecimal(partIndex)
        )
    }

    /// Identifies source-owned context referenced by more than one emitted record.
    ///
    /// For example, HealthKit medication statements and dose events use this identity for the
    /// same `HKHealthConceptIdentifier` without disclosing that platform identifier on the wire.
    public func sourceContext(
        adapterID: String,
        contextType: String,
        repositoryScope: BusinessIdentifier,
        nativeContextID: String
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try validateNonempty([
            ("adapterID", adapterID),
            ("contextType", contextType),
            ("nativeContextID", nativeContextID)
        ])
        try validateCodeToken(contextType, field: "contextType")
        return try identifier(
            role: .sourceContext,
            kind: .sourceContext,
            components: [
                adapterID,
                contextType,
                repositoryScope.system.rawValue,
                repositoryScope.value,
                nativeContextID
            ]
        )
    }

    public func recordingDevice(
        adapterID: String,
        subject: BusinessIdentifier,
        stableUnitToken: String
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try validateNonempty([
            ("adapterID", adapterID),
            ("stableUnitToken", stableUnitToken)
        ])
        return try identifier(
            role: .recordingDevice,
            kind: .recordingDevice,
            components: [
                adapterID,
                subject.system.rawValue,
                subject.value,
                stableUnitToken
            ]
        )
    }

    public func deviceSnapshot(
        event: ExchangeEventIdentifier,
        role: DeviceSnapshotRole,
        sourceDeviceToken: String
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try validateNonempty([("sourceDeviceToken", sourceDeviceToken)])
        return try identifier(
            role: .deviceSnapshot,
            kind: .deviceSnapshot,
            components: [
                event.identifier.identifier.system.rawValue,
                event.identifier.identifier.value,
                role.rawValue,
                sourceDeviceToken
            ]
        )
    }

    private func validateNonempty(_ components: [(String, String)]) throws(OpaqueIdentityError) {
        if let component = components.first(where: { $0.1.isEmpty }) {
            throw .emptyComponent(component.0)
        }
    }

    private func validateGenericAdapterID(_ value: String) throws(OpaqueIdentityError) {
        guard GroveProviderCode(rawValue: value) == nil else {
            throw .providerKindRequired(value)
        }
    }

    private func validateCodeToken(_ value: String, field: String) throws(OpaqueIdentityError) {
        guard let first = value.utf8.first,
              (0x61...0x7A).contains(first),
              value.utf8.allSatisfy({
                  (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x2D
              }) else {
            throw .invalidCodeToken(field: field, value: value)
        }
    }
}
