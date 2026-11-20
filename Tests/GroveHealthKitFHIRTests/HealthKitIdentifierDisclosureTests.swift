//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CryptoKit
import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// The native and sync identifier disclosures and the system the exporter derives from its repository scope.
@Suite("HealthKit identifier disclosures")
struct HealthKitIdentifierDisclosureTests {
    private static let store = GoldenFixtures.nativeIdentifierSystem
    private static let uuid = GoldenFixtures.uuid(0xB2)
    private static let syncSegment = "/healthkit-sync-identifier/\(GoldenFixtures.foreignWriter.bundleIdentifier)"

    /// A heart rate the foreign application wrote with a sync identifier and version.
    private static func convert(_ configure: (inout HealthKitFHIRExporter.Options) -> Void) throws -> HealthKitAssembly.Conversion {
        var inputs = ExportInputs()
        configure(&inputs.options)
        let metadata = GoldenFixtures.timeZoneMetadata.merging(HealthKitMetadataWarningTests.syncPair) { $1 }
        let sample = try GoldenFixtures.heartRate(uuid: uuid, metadata: metadata, writer: GoldenFixtures.foreignWriter)
        return try AssemblyFixtures.conversion(sample, inputs)
    }

    /// The system and value of each identifier of the primary Observation that carries no Grove role.
    private static func clearIdentifiers(of conversion: HealthKitAssembly.Conversion) throws -> [[String]] {
        let observation = try #require(conversion.record.bundle.entry?.first?.resource?.get(if: Observation.self))
        return (observation.identifier ?? []).filter { (try? RoledIdentifier($0)) == nil }.map {
            [$0.system?.value?.url.absoluteString ?? "", $0.value?.value?.string ?? ""]
        }
    }

    private static func expectNoOmissionReported(_ conversion: HealthKitAssembly.Conversion, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(conversion.withheldMetadataKeys.isEmpty, sourceLocation: sourceLocation)
        #expect(conversion.warnings.isEmpty, sourceLocation: sourceLocation)
        #expect(throws: Never.self, sourceLocation: sourceLocation) {
            try ExchangeGraph(validating: conversion.record.json, kind: .active)
        }
    }

    /// The native identifier system `exporter` derived or was given.
    private static func derivedSystem(of exporter: HealthKitFHIRExporter) throws -> String {
        guard case .authorized(let system, nil) = exporter.assembly.disclosure.nativeIdentifier else {
            throw ExportFixtureError.nothingExported
        }
        return system.rawValue
    }

    /// The test deployment's identity scope under `systems` and a key of 32 bytes `key`; `0x42` is the test deployment's.
    private static func identityScope(key: UInt8, systems: DeploymentIdentifierSystems) throws -> OpaqueIdentityScope {
        try OpaqueIdentityScope(systems: systems, keyID: "test", epoch: KeyEpoch(1), key: SymmetricKey(data: Data(repeating: key, count: 32)))
    }

    private static func exporter(repository: BusinessIdentifier) throws -> HealthKitFHIRExporter {
        try ExporterFixtures.exporter(ExporterFixtures.producer(), repositoryScope: repository) { $0.nativeIdentifier = .authorized }
    }

    @Test("Authorizing the UUID alone discloses neither the sync identifier nor the writing application")
    func nativeIdentifierWithoutSyncIdentifier() throws {
        let conversion = try Self.convert { $0.nativeIdentifier = .authorized(system: Self.store) }
        #expect(try Self.clearIdentifiers(of: conversion) == [[Self.store.rawValue, Self.uuid.uuidString.lowercased()]])
        let json = String(decoding: conversion.record.json, as: UTF8.self)
        #expect(!json.contains("sync-abc"))
        #expect(!json.contains("healthkit-sync-identifier"))
        Self.expectNoOmissionReported(conversion)
    }

    @Test("An authorized sync identifier is emitted only beside an authorized UUID")
    func syncIdentifierNeedsTheNativeIdentifier() throws {
        let alone = try Self.convert { $0.syncIdentifier = .authorized }
        #expect(try Self.clearIdentifiers(of: alone).isEmpty)
        #expect(!String(decoding: alone.record.json, as: UTF8.self).contains("sync-abc"))
        Self.expectNoOmissionReported(alone)

        let both = try Self.convert { options in
            options.nativeIdentifier = .authorized(system: Self.store)
            options.syncIdentifier = .authorized
        }
        #expect(try Self.clearIdentifiers(of: both) == [
            [Self.store.rawValue, Self.uuid.uuidString.lowercased()],
            [Self.store.rawValue + Self.syncSegment, "sync-abc"]
        ])
        Self.expectNoOmissionReported(both)
    }

    @Test("The derived system is the repository scope's system, a keyed token and the record kind")
    func derivedSystem() throws {
        let scope = ExporterFixtures.base.repositoryScope
        let system = try Self.derivedSystem(of: Self.exporter(repository: scope))
        let prefix = scope.system.rawValue + "/"
        let suffix = "/healthkit-native-record"
        try #require(system.hasPrefix(prefix) && system.hasSuffix(suffix))
        let token = system.dropFirst(prefix.count).dropLast(suffix.count)
        #expect(token.count == 43, "an unpadded base64url SHA-256 HMAC")
        #expect(token.utf8.allSatisfy { $0.isASCIIAlphaNumeric || $0 == 0x2D || $0 == 0x5F }, "URL-path-safe")

        let conversion = try Self.convert { options in
            options.nativeIdentifier = .authorized
            options.syncIdentifier = .authorized
        }
        #expect(try Self.clearIdentifiers(of: conversion) == [
            [system, Self.uuid.uuidString.lowercased()],
            [system + Self.syncSegment, "sync-abc"]
        ])
        Self.expectNoOmissionReported(conversion)
    }

    @Test("The derived system is the same for one key and repository scope, differs between two scopes and between two keys")
    func derivedSystemFollowsTheScopeAndTheKey() throws {
        let system = ExporterFixtures.base.repositoryScope.system
        let first = try BusinessIdentifier(system: system, value: "participant-0042")
        let second = try BusinessIdentifier(system: system, value: "participant-0043")
        let systems = try [first, first, second].map { try Self.derivedSystem(of: Self.exporter(repository: $0)) }
        #expect(systems[0] == systems[1])
        #expect(systems[0] != systems[2])
        #expect(systems.allSatisfy { $0.hasPrefix(system.rawValue + "/") && !$0.contains("participant") })

        let otherKey = try Self.identityScope(key: 0x43, systems: ExporterFixtures.base.identityScope.systems)
        let rekeyed = try ExporterFixtures.exporter(ExporterFixtures.producer(identityScope: otherKey), repositoryScope: first) {
            $0.nativeIdentifier = .authorized
        }
        #expect(try Self.derivedSystem(of: rekeyed) != systems[0])
        // The token is no unkeyed digest of the scope: the scope's full URL is one, and it is not the token.
        let digest = try #require(try first.fullURLString.split(separator: ":").last)
        #expect(!systems[0].contains(digest))
    }

    @Test("A repository scope system that ends in a slash yields no empty path segment")
    func derivedSystemTrimsTrailingSlashes() throws {
        let plain = try BusinessIdentifier(system: IdentifierSystem("https://study.example.org/store"), value: "primary")
        for system in ["https://study.example.org/store/", "https://study.example.org/store//"] {
            let scope = try BusinessIdentifier(system: IdentifierSystem(system), value: "primary")
            let derived = try Self.derivedSystem(of: Self.exporter(repository: scope))
            #expect(derived.hasPrefix("https://study.example.org/store/"))
            #expect(!derived.dropFirst("https://".count).contains("//"))
            #expect(derived != (try Self.derivedSystem(of: Self.exporter(repository: plain))), "the token covers the scope's exact system")
        }
    }

    @Test("A derived system that is, or would hold sync identifiers inside, one of the deployment's identity systems is refused")
    func derivedSystemIsCheckedAgainstTheDeploymentSystems() throws {
        let scope = ExporterFixtures.base.repositoryScope
        let derived = try IdentifierSystem(Self.derivedSystem(of: Self.exporter(repository: scope)))
        for reserved in [derived, try IdentifierSystem(derived.rawValue + "/healthkit-sync-identifier/org")] {
            let systems = ExporterFixtures.base.identityScope.systems
            let colliding = try Self.identityScope(key: 0x42, systems: DeploymentIdentifierSystems(
                sourceRecord: systems.sourceRecord,
                sourceOutput: systems.sourceOutput,
                writerRecord: systems.writerRecord,
                providerRecord: systems.providerRecord,
                providerOutput: systems.providerOutput,
                sourceArtifact: systems.sourceArtifact,
                providerArtifact: systems.providerArtifact,
                sourceContext: systems.sourceContext,
                recordingDevice: systems.recordingDevice,
                deviceSnapshot: systems.deviceSnapshot,
                contextSnapshot: systems.contextSnapshot,
                recordVersion: systems.recordVersion,
                recordRetraction: reserved,
                deviceLocalIdentifier: systems.deviceLocalIdentifier
            ))
            #expect(throws: HealthKitFHIRExporter.ConfigurationError.reservedNativeIdentifierSystem(derived)) {
                try ExporterFixtures.exporter(ExporterFixtures.producer(identityScope: colliding), repositoryScope: scope) {
                    $0.nativeIdentifier = .authorized
                }
            }
        }
    }

    @Test("A device-form bundle identifier scopes the keyed identities and the sync identifier's system exactly, whatever the source policy")
    func deviceFormBundleIdentifierStaysExactOutsideTheSourceRevision() throws {
        let bundleIdentifier = "com.apple.health.94C8E349-0D09-4184-BF6C-AF11692FA465"
        let writer = StoredSampleFixtures.Writer(name: "Anna's iPhone", bundleIdentifier: bundleIdentifier, version: "26.1", productType: "iPhone17,1")
        let metadata = GoldenFixtures.timeZoneMetadata.merging(HealthKitMetadataWarningTests.syncPair) { $1 }
        let sample = try GoldenFixtures.heartRate(uuid: Self.uuid, device: GoldenFixtures.watch, metadata: metadata, writer: writer)
        func keyedIdentities(_ options: HealthKitFHIRExporter.Options) throws -> [GroveIdentifierRole: String] {
            var inputs = ExportInputs()
            inputs.options = options
            let conversion = try AssemblyFixtures.conversion(sample, inputs)
            let identifiers = (conversion.record.bundle.entry ?? []).flatMap { entry -> [Identifier] in
                entry.resource?.get(if: Observation.self)?.identifier ?? entry.resource?.get(if: Device.self)?.identifier ?? []
            }
            let keyed = identifiers.compactMap { try? RoledIdentifier($0) }.filter { [.writerRecord, .recordingDevice].contains($0.role) }
            return Dictionary(keyed.map { ($0.role, $0.identifier.value) }) { first, _ in first }
        }
        var narrowed = HealthKitFHIRExporter.Options.nonIdentifying
        narrowed.device = .all
        let stated = try keyedIdentities(HealthKitFHIRExporter.Options())
        #expect(Set(stated.keys) == [.writerRecord, .recordingDevice])
        #expect(try keyedIdentities(narrowed) == stated)

        var inputs = ExportInputs()
        inputs.options = narrowed
        inputs.options.nativeIdentifier = .authorized(system: Self.store)
        inputs.options.syncIdentifier = .authorized
        let disclosed = try AssemblyFixtures.conversion(sample, inputs)
        #expect(try Self.clearIdentifiers(of: disclosed) == [
            [Self.store.rawValue, Self.uuid.uuidString.lowercased()],
            ["\(Self.store.rawValue)/healthkit-sync-identifier/\(bundleIdentifier)", "sync-abc"]
        ])
        Self.expectNoOmissionReported(disclosed)
    }

    @Test("With the sync identifier omitted, a bundle identifier that cannot name its system reports nothing withheld")
    func omittedSyncIdentifierIsNotWithheld() throws {
        var inputs = ExportInputs()
        inputs.options.nativeIdentifier = .authorized(system: Self.store)
        let writer = StoredSampleFixtures.Writer(name: "Odd Writer", bundleIdentifier: "org.example/writer", version: "1", productType: nil)
        let metadata = GoldenFixtures.timeZoneMetadata.merging(HealthKitMetadataWarningTests.syncPair) { $1 }
        let conversion = try AssemblyFixtures.conversion(GoldenFixtures.heartRate(uuid: Self.uuid, metadata: metadata, writer: writer), inputs)
        #expect(try Self.clearIdentifiers(of: conversion) == [[Self.store.rawValue, Self.uuid.uuidString.lowercased()]])
        Self.expectNoOmissionReported(conversion)
    }

    @Test("A repository scope whose system cannot be extended refuses the derived system", arguments: [
        "urn:oid:2.16.840.1.113883.3.1",
        "https://study.example.org/store?participant=42",
        "https://study.example.org/store#participant-42"
    ])
    func derivedSystemNeedsAnExtensibleScope(system: String) throws {
        let scope = try BusinessIdentifier(system: IdentifierSystem(system), value: "primary")
        #expect(throws: HealthKitFHIRExporter.ConfigurationError.nativeIdentifierSystemNotExtensible(scope.system)) {
            try Self.exporter(repository: scope)
        }
        _ = try ExporterFixtures.exporter(ExporterFixtures.producer(), repositoryScope: scope)
    }

    @Test("A retraction names the UUID under the system the export states it under", arguments: [true, false])
    func retractionUsesTheExportSystem(derived: Bool) async throws {
        var inputs = ExportInputs()
        inputs.options.nativeIdentifier = derived ? .authorized : .authorized(system: Self.store)
        let sample = try GoldenFixtures.heartRate(uuid: Self.uuid)
        let exported = try Self.clearIdentifiers(of: AssemblyFixtures.conversion(sample, inputs))
        try #require(exported.count == 1)

        let deletion = HealthKitFHIRExporter.Deletion(uuid: Self.uuid, sourceType: .heartRate, deletedAfter: nil, detectedAt: inputs.instant)
        let graph = try await ExporterFixtures.retraction(deletion, inputs)
        let provenance = try #require(graph.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        let native = provenance.target.first?.extension?.first { $0.url == Canonicals.retractionTargetNativeIdentifier }
        guard case .identifier(let identifier)? = native?.value else {
            Issue.record("The authorized native identifier is on the retraction target")
            return
        }
        #expect([identifier.system?.value?.url.absoluteString ?? "", identifier.value?.value?.string ?? ""] == exported[0])
    }
}

#endif
