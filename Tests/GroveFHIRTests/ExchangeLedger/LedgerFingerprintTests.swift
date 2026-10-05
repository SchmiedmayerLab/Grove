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


/// The identity scope's ledger fingerprint, which every exporter's context fingerprint carries so that a
/// reservation is never reused under another scope.
@Suite
struct LedgerFingerprintTests {
    private static let key = SymmetricKey(data: Data(repeating: 0x42, count: 32))

    private static func systems(
        root: IdentifierSystem = "https://study.example.org/fhir",
        keyID: String = "test"
    ) throws -> DeploymentIdentifierSystems {
        try DeploymentIdentifierSystems.derived(root: root, keyID: keyID, epoch: EventSequence(1))
    }

    /// `opaque`'s ten opaque systems with `event` and `entryNode`.
    private static func systems(
        opaque: DeploymentIdentifierSystems,
        event: IdentifierSystem,
        entryNode: IdentifierSystem
    ) throws -> DeploymentIdentifierSystems {
        try DeploymentIdentifierSystems(
            sourceRecord: opaque.sourceRecord,
            sourceOutput: opaque.sourceOutput,
            writerRecord: opaque.writerRecord,
            providerRecord: opaque.providerRecord,
            providerOutput: opaque.providerOutput,
            sourceArtifact: opaque.sourceArtifact,
            providerArtifact: opaque.providerArtifact,
            sourceContext: opaque.sourceContext,
            recordingDevice: opaque.recordingDevice,
            deviceSnapshot: opaque.deviceSnapshot,
            event: event,
            entryNode: entryNode
        )
    }

    private static func scope(
        systems: DeploymentIdentifierSystems,
        keyID: String = "test",
        epoch: UInt64 = 1,
        key: SymmetricKey = Self.key
    ) throws -> OpaqueIdentityScope {
        try OpaqueIdentityScope(systems: systems, keyID: keyID, epoch: EventSequence(epoch), key: key)
    }

    @Test("Scopes that differ only in key id, epoch, key, or one group of systems fingerprint pairwise apart")
    func everyScopeInputSeparatesTheFingerprint() throws {
        let systems = try Self.systems()
        let otherRoot = try Self.systems(root: "https://other.example.org/fhir")
        let scopes = [
            ("base", try Self.scope(systems: systems)),
            ("key id", try Self.scope(systems: systems, keyID: "other")),
            ("epoch", try Self.scope(systems: systems, epoch: 2)),
            ("key", try Self.scope(systems: systems, key: SymmetricKey(data: Data(repeating: 7, count: 32)))),
            ("opaque systems", try Self.scope(systems: try Self.systems(
                opaque: try Self.systems(keyID: "other"),
                event: systems.event,
                entryNode: systems.entryNode
            ))),
            ("event system", try Self.scope(systems: try Self.systems(opaque: systems, event: otherRoot.event, entryNode: systems.entryNode))),
            ("entry-node system", try Self.scope(systems: try Self.systems(opaque: systems, event: systems.event, entryNode: otherRoot.entryNode)))
        ]
        let fingerprints = scopes.map { name, scope in (name, scope.ledgerFingerprint) }
        for (index, (name, fingerprint)) in fingerprints.enumerated() {
            for (earlier, earlierFingerprint) in fingerprints[..<index] where earlierFingerprint == fingerprint {
                Issue.record("\(name) shares its ledger fingerprint with \(earlier)")
            }
        }
        #expect(Set(fingerprints.map(\.1)).count == scopes.count)
    }

    @Test("The ledger fingerprint is stable for equal scopes and reveals nothing about the key")
    func fingerprintIsStableAndKeyed() throws {
        let scope = try Self.scope(systems: try Self.systems())
        let again = try Self.scope(systems: try Self.systems())
        #expect(scope.ledgerFingerprint == again.ledgerFingerprint)
        #expect(ExchangeIdentity.isUnpaddedBase64URLDigest(scope.ledgerFingerprint))
        #expect(!scope.ledgerFingerprint.contains(Data(repeating: 0x42, count: 32).base64URLEncodedStringWithoutPadding))
    }
}
