//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(CryptoKit)
public import CryptoKit
#else
public import Crypto
#endif
import Foundation


/// The closed domain-separation token fed to the Grove HMAC preimage.
package enum OpaqueIdentityKind: String, CaseIterable, Hashable, Sendable {
    case sourceRecord = "source-record"
    case sourceOutput = "source-output"
    case writerRecord = "writer-record"
    case providerRecord = "provider-record"
    case providerOutput = "provider-output"
    case sourceArtifact = "source-artifact"
    case providerArtifact = "provider-artifact"
    case sourceContext = "source-context"
    case recordingDevice = "recording-device"
    case deviceSnapshot = "device-snapshot"

    /// The frozen number of typed fields in this identity kind's protocol preimage.
    package var componentCount: Int {
        componentNames.count
    }
}


/// The deployment-owned, key-epoch-specific scope that mints every opaque identity.
///
/// The systems derive from the deployment's own root (``DeploymentIdentifierSystems/derived(root:keyID:epoch:)``).
/// Grove publishes no global namespace, because the same clear source identity must not be linkable across unrelated
/// studies.
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

    /// Distinguishes the identity scopes one exchange ledger may serve, without revealing the key.
    ///
    /// HMAC-SHA-256 under the scope's key, base64url without padding, over the length-framed label
    /// `org.grovealliance.grove.ledger-context.v0`, the key id, the epoch and every derived system, in
    /// their fixed order. A different key, key id, epoch or system yields a different value.
    package var ledgerFingerprint: String {
        let parts = ["org.grovealliance.grove.ledger-context.v0", keyID, epoch.rawValue] + systems.all.map(\.rawValue)
        let framed: Data
        do {
            framed = try Data(lengthFramedUTF8: parts)
        } catch {
            preconditionFailure("A validated identity-scope part exceeds the framing limit: \(error)")
        }
        return Data(HMAC<SHA256>.authenticationCode(for: framed, using: key)).base64URLEncodedStringWithoutPadding
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
    ) throws(ExchangeIdentityError) {
        try self.init(
            systems: systems,
            keyID: keyID,
            epoch: epoch,
            key: key,
            permitsPublishedConformanceKey: false
        )
    }

    /// Creates the identity scope of one deployment root, with its twelve systems in the exchange
    /// protocol's recommended form: ``DeploymentIdentifierSystems/derived(root:keyID:epoch:)``
    /// followed by ``init(systems:keyID:epoch:key:)``.
    ///
    /// A key id the systems cannot carry is reported as ``ExchangeIdentityError/invalidKeyID(_:)``;
    /// a root the recommended form cannot be built under as ``ExchangeIdentityError/invalidDeploymentRoot(_:)``.
    public init(
        root: IdentifierSystem,
        keyID: String,
        epoch: EventSequence,
        key: SymmetricKey
    ) throws(ExchangeIdentityError) {
        guard Self.isValidKeyID(keyID) else {
            throw .invalidKeyID(keyID)
        }
        let systems: DeploymentIdentifierSystems
        do {
            systems = try DeploymentIdentifierSystems.derived(root: root, keyID: keyID, epoch: epoch)
        } catch {
            throw .invalidDeploymentRoot(root.rawValue)
        }
        try self.init(systems: systems, keyID: keyID, epoch: epoch, key: key)
    }

    private init(
        systems: DeploymentIdentifierSystems,
        keyID: String,
        epoch: EventSequence,
        key: SymmetricKey,
        permitsPublishedConformanceKey: Bool
    ) throws(ExchangeIdentityError) {
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
    ) throws(ExchangeIdentityError) -> Self {
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

    /// Derives a typed opaque identifier from the kind's raw components, checking every component rule.
    ///
    /// The HMAC preimage is the ordered sequence of unsigned 32-bit big-endian UTF-8 lengths and
    /// bytes for the protocol label, identity kind, and every typed component. Delimiters are not
    /// special and supplementary Unicode scalars are encoded as their ordinary UTF-8 bytes.
    package func identifier(kind: OpaqueIdentityKind, components: [String]) throws(ExchangeIdentityError) -> RoledIdentifier {
        guard components.count == kind.componentCount else {
            throw .invalidComponentCount(kind: kind.rawValue, expected: kind.componentCount, actual: components.count)
        }
        for (name, component) in zip(kind.componentNames, components) {
            let path = "\(kind.rawValue).\(name)"
            guard !component.isEmpty else {
                throw .emptyComponent(path)
            }
            guard !OpaqueIdentityKind.unsignedDecimalComponents.contains(name) || CanonicalNonnegativeDecimal.isCanonical(component) else {
                throw .nonCanonicalPartIndex(path)
            }
        }
        if [.sourceRecord, .sourceOutput, .sourceArtifact].contains(kind), let adapterID = components.first {
            try validateGenericAdapterID(adapterID)
        }
        let input = try Data(lengthFramedUTF8: ["org.grovealliance.fhir.identity.v0", kind.rawValue] + components)
        let digest = Data(HMAC<SHA256>.authenticationCode(for: input, using: key)).base64URLEncodedStringWithoutPadding
        return RoledIdentifier(
            identifier: BusinessIdentifier(system: systems[kind], nonemptyValue: "v0:\(keyID):\(epoch.rawValue):\(digest)"),
            role: kind.identifierRole
        )
    }

    private func validateGenericAdapterID(_ value: String) throws(ExchangeIdentityError) {
        guard ProviderCode(rawValue: value) == nil else {
            throw .providerKindRequired(value)
        }
    }

    /// An empty token is left to the minting path, which reports it with the component's path.
    func validateCodeToken(_ value: String, field: String) throws(ExchangeIdentityError) {
        guard let first = value.utf8.first else {
            return
        }
        guard (0x61...0x7A).contains(first),
              value.utf8.allSatisfy({ (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x2D }) else {
            throw .invalidCodeToken(field: field, value: value)
        }
    }
}


extension OpaqueIdentityScope {
    /// The providers admitted by the Grove identity protocol.
    ///
    /// Provider-owned records use a provider identity kind. Rejecting these values from generic
    /// `source-*` constructors prevents two names for the same provider preimage.
    package enum ProviderCode: String, CaseIterable, Hashable, Sendable {
        case googleHealthAPI = "google-health-api"
        case oura
        case withings
    }

    /// The closed resource-kind role used by an immutable event-time Device snapshot.
    package enum DeviceRole: String, CaseIterable, Hashable, Sendable {
        case application
        case host
        case recordingDevice = "recording-device"
    }
}
