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
import CryptoKit
#else
import Crypto
#endif
public import Foundation


/// Configuration for one deployment-owned, key-epoch-specific pseudonymous identity scope.
///
/// The system is deliberately supplied by the deployment. Grove does not publish a global
/// pseudonymous namespace because the same clear source identity must not be linkable across
/// unrelated studies or installations.
public struct PseudonymousIdentityScope: Sendable {
    private static let publishedConformanceKey = Data((0...31).map(UInt8.init))

    public let systems: PseudonymousIdentitySystems
    public let keyID: String
    public let epoch: CanonicalPositiveDecimal
    private let keyData: Data

    /// Creates one identity scope.
    ///
    /// Keys shorter than 256 bits are rejected. `keyID` is wire-visible and therefore restricted
    /// to an unambiguous ASCII token; it is a selector, never secret key material.
    public init(
        systems: PseudonymousIdentitySystems,
        keyID: String,
        epoch: CanonicalPositiveDecimal,
        key: Data
    ) throws(PseudonymousIdentityError) {
        try self.init(
            systems: systems,
            keyID: keyID,
            epoch: epoch,
            key: key,
            permitsPublishedConformanceKey: false
        )
    }

    private init(
        systems: PseudonymousIdentitySystems,
        keyID: String,
        epoch: CanonicalPositiveDecimal,
        key: Data,
        permitsPublishedConformanceKey: Bool
    ) throws(PseudonymousIdentityError) {
        guard !keyID.isEmpty,
              keyID.utf8.allSatisfy({
                  $0.isASCIIAlphaNumeric || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
              }) else {
            throw .invalidKeyID(keyID)
        }
        guard key.count >= 32 else {
            throw .keyTooShort(actualBytes: key.count)
        }
        guard permitsPublishedConformanceKey || key != Self.publishedConformanceKey else {
            throw .publishedConformanceKeyProhibited
        }
        self.systems = systems
        self.keyID = keyID
        self.epoch = epoch
        self.keyData = key
    }

    /// Convenience for deployments whose current key epoch is still machine-sized.
    public init(
        systems: PseudonymousIdentitySystems,
        keyID: String,
        epoch: UInt64,
        key: Data
    ) throws(PseudonymousIdentityError) {
        let canonicalEpoch: CanonicalPositiveDecimal
        do {
            canonicalEpoch = try CanonicalPositiveDecimal(epoch)
        } catch {
            throw .invalidEpoch(String(epoch))
        }
        try self.init(systems: systems, keyID: keyID, epoch: canonicalEpoch, key: key)
    }

    /// Constructs the normative vector scope for tests in this package without exposing a
    /// production bypass for the published conformance key.
    package static func conformanceTesting(
        systems: PseudonymousIdentitySystems,
        keyID: String,
        epoch: CanonicalPositiveDecimal
    ) throws(PseudonymousIdentityError) -> Self {
        try Self(
            systems: systems,
            keyID: keyID,
            epoch: epoch,
            key: publishedConformanceKey,
            permitsPublishedConformanceKey: true
        )
    }

    /// Convenience for normative tests whose epoch is machine-sized.
    package static func conformanceTesting(
        systems: PseudonymousIdentitySystems,
        keyID: String,
        epoch: UInt64
    ) throws(PseudonymousIdentityError) -> Self {
        let canonicalEpoch: CanonicalPositiveDecimal
        do {
            canonicalEpoch = try CanonicalPositiveDecimal(epoch)
        } catch {
            throw .invalidEpoch(String(epoch))
        }
        return try conformanceTesting(systems: systems, keyID: keyID, epoch: canonicalEpoch)
    }

    /// Derives a typed pseudonymous identifier.
    ///
    /// The HMAC preimage is the ordered sequence of unsigned 32-bit big-endian UTF-8 lengths and
    /// bytes for the protocol label, identity kind, and every typed component. Delimiters are not
    /// special and supplementary Unicode scalars are encoded as their ordinary UTF-8 bytes.
    private func identifier(
        role: GroveIdentifierRole,
        identityKind: PseudonymousIdentityKind,
        components: [String]
    ) throws -> BusinessIdentifier {
        guard components.count == identityKind.componentCount else {
            throw PseudonymousIdentityError.invalidComponentCount(
                kind: identityKind,
                expected: identityKind.componentCount,
                actual: components.count
            )
        }
        let input = try LengthFramedUTF8.encode(
            ["org.grovealliance.fhir.identity.v0", identityKind.rawValue] + components
        )
        let authentication = HMAC<SHA256>.authenticationCode(
            for: input,
            using: SymmetricKey(data: keyData)
        )
        let digest = Data(authentication).base64URLEncodedStringWithoutPadding
        return try BusinessIdentifier(
            system: systems[identityKind],
            value: "v0:\(keyID):\(epoch.rawValue):\(digest)",
            role: role
        )
    }

    public func sourceRecord(
        adapterID: String,
        sourceType: String,
        repositoryScope: BusinessIdentifier,
        nativeRecordID: String
    ) throws -> BusinessIdentifier {
        try validateNonempty([
            ("adapterID", adapterID),
            ("sourceType", sourceType),
            ("nativeRecordID", nativeRecordID)
        ])
        try validateGenericAdapterID(adapterID)
        return try identifier(
            role: .sourceRecord,
            identityKind: .sourceRecord,
            components: [
                adapterID,
                sourceType,
                repositoryScope.systemValue,
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
    ) throws -> BusinessIdentifier {
        let providerCode = providerCode.rawValue
        try validateNonempty([
            ("sourceType", sourceType),
            ("nativeRecordID", nativeRecordID)
        ])
        return try identifier(
            role: .sourceRecord,
            identityKind: .providerRecord,
            components: [
                providerCode,
                sourceType,
                providerScope.systemValue,
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
    ) throws -> BusinessIdentifier {
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
            identityKind: .sourceOutput,
            components: [
                adapterID,
                sourceType,
                repositoryScope.systemValue,
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
    ) throws -> BusinessIdentifier {
        let providerCode = providerCode.rawValue
        try validateNonempty([
            ("sourceType", sourceType),
            ("nativeRecordID", nativeRecordID),
            ("outputRole", outputRole),
            ("outputDiscriminator", outputDiscriminator)
        ])
        try validateCodeToken(outputRole, field: "outputRole")
        return try identifier(
            role: .sourceOutput,
            identityKind: .providerOutput,
            components: [
                providerCode,
                sourceType,
                providerScope.systemValue,
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
    ) throws -> BusinessIdentifier {
        try validateNonempty([("writerRecordID", writerRecordID)])
        return try identifier(
            role: .writerRecord,
            identityKind: .writerRecord,
            components: [
                writerApplication.systemValue,
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
    ) throws -> BusinessIdentifier {
        try validateNonempty([
            ("adapterID", adapterID),
            ("sourceType", sourceType),
            ("nativeRecordID", nativeRecordID),
            ("formatCode", formatCode)
        ])
        try validateGenericAdapterID(adapterID)
        return try identifier(
            role: .sourceArtifact,
            identityKind: .sourceArtifact,
            components: [
                adapterID,
                sourceType,
                repositoryScope.systemValue,
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
    ) throws -> BusinessIdentifier {
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
    ) throws -> BusinessIdentifier {
        let providerCode = providerCode.rawValue
        try validateNonempty([
            ("sourceType", sourceType),
            ("nativeRecordID", nativeRecordID),
            ("formatCode", formatCode)
        ])
        return try identifier(
            role: .sourceArtifact,
            identityKind: .providerArtifact,
            components: [
                providerCode,
                sourceType,
                providerScope.systemValue,
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
    ) throws -> BusinessIdentifier {
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
    ) throws -> BusinessIdentifier {
        try validateNonempty([
            ("adapterID", adapterID),
            ("contextType", contextType),
            ("nativeContextID", nativeContextID)
        ])
        try validateCodeToken(contextType, field: "contextType")
        return try identifier(
            role: .sourceContext,
            identityKind: .sourceContext,
            components: [
                adapterID,
                contextType,
                repositoryScope.systemValue,
                repositoryScope.value,
                nativeContextID
            ]
        )
    }

    public func recordingDevice(
        adapterID: String,
        subject: BusinessIdentifier,
        stableUnitToken: String
    ) throws -> BusinessIdentifier {
        try validateNonempty([
            ("adapterID", adapterID),
            ("stableUnitToken", stableUnitToken)
        ])
        return try identifier(
            role: .recordingDevice,
            identityKind: .recordingDevice,
            components: [
                adapterID,
                subject.systemValue,
                subject.value,
                stableUnitToken
            ]
        )
    }

    public func deviceSnapshot(
        eventIdentifier: ExchangeEventIdentifier,
        deviceRole: GroveDeviceSnapshotRole,
        sourceDeviceToken: String
    ) throws -> BusinessIdentifier {
        try validateNonempty([
            ("sourceDeviceToken", sourceDeviceToken)
        ])
        return try identifier(
            role: .deviceSnapshot,
            identityKind: .deviceSnapshot,
            components: [
                eventIdentifier.businessIdentifier.systemValue,
                eventIdentifier.businessIdentifier.value,
                deviceRole.rawValue,
                sourceDeviceToken
            ]
        )
    }

    private func validateNonempty(_ components: [(String, String)]) throws(PseudonymousIdentityError) {
        if let component = components.first(where: { $0.1.isEmpty }) {
            throw .emptyComponent(component.0)
        }
    }

    private func validateGenericAdapterID(_ value: String) throws(PseudonymousIdentityError) {
        guard GroveProviderCode(rawValue: value) == nil else {
            throw .providerKindRequired(value)
        }
    }

    private func validateCodeToken(
        _ value: String,
        field: String
    ) throws(PseudonymousIdentityError) {
        guard let first = value.utf8.first,
              (0x61...0x7A).contains(first),
              value.utf8.allSatisfy({
                  (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x2D
              }) else {
            throw .invalidCodeToken(field: field, value: value)
        }
    }
}
