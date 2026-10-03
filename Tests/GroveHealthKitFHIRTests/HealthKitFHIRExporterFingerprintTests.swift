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
import Testing


/// A resolver whose only distinguishing feature is that the deployment supplied it.
private struct NoRecordingDevice: RecordingDeviceResolver {
    func recordingDevice(for device: HKDevice) -> RecordingDevice? {
        nil
    }
}


/// The context fingerprint: everything that shapes a graph but is not frozen with its event.
@Suite
struct HealthKitFHIRExporterFingerprintTests {
    private typealias Fixtures = ExporterFixtures
    private typealias Configure = (inout HealthKitFHIRExporter.Options) -> Void

    private static let key = SymmetricKey(data: Data(repeating: 0x42, count: 32))

    /// Every option perturbation the fingerprint must tell apart from the defaults and from each other.
    @available(*, deprecated, message: "Names the transitional legacy Bundle.id case")
    private static func optionPerturbations() -> [(String, Configure)] {
        let gateway = ApplicationDevice.test(name: "Cuff Companion", bundleIdentifier: "com.example.cuff", version: "3.1", build: "9")
        let system = GoldenFixtures.nativeIdentifierSystem
        let typeSystem: IdentifierSystem = "https://study.example.org/fhir/CodeSystem/identifier-type"
        let otherSystem: IdentifierSystem = "https://study.example.org/fhir/CodeSystem/other-type"
        return [
            ("route", { $0.route = .authorized }),
            ("legacyBundleID", { $0.legacyBundleID = .healthKitUUID }),
            ("writer application", { $0.writer = .application }),
            ("writer device", { $0.writer = .device }),
            ("writer omit", { $0.writer = .omit }),
            ("recordingDevice omit", { $0.recordingDevice = .omit }),
            ("recordingDevice custom", { $0.recordingDevice = .custom(NoRecordingDevice()) }),
            ("role gatewayForOwnWrites", { $0.role = .gatewayForOwnWrites }),
            ("role gateway", { $0.role = .gateway }),
            ("role gatewayApplication", { $0.role = .gatewayApplication(gateway) }),
            ("gateway name", { $0.role = .gatewayApplication(.test(name: "Other", bundleIdentifier: "com.example.cuff", version: "3.1", build: "9")) }),
            ("gateway bundle", { $0.role = .gatewayApplication(.test(name: "Cuff Companion", bundleIdentifier: "com.example.x", version: "3.1", build: "9")) }),
            ("gateway version", { $0.role = .gatewayApplication(.test(name: "Cuff Companion", bundleIdentifier: "com.example.cuff", version: "3.2", build: "9")) }),
            ("gateway build", { $0.role = .gatewayApplication(.test(name: "Cuff Companion", bundleIdentifier: "com.example.cuff", version: "3.1")) }),
            ("nativeIdentifier", { $0.nativeIdentifier = .authorized(system: system) }),
            ("nativeIdentifier system", { $0.nativeIdentifier = .authorized(system: "https://study.example.org/fhir/NamingSystem/other") }),
            ("type", { $0.nativeIdentifier = .authorized(system: system, type: try? GovernedSourceIdentifierType(system: typeSystem, code: "store")) }),
            ("type system", { $0.nativeIdentifier = .authorized(system: system, type: try? GovernedSourceIdentifierType(system: otherSystem, code: "store")) }),
            ("type code", { $0.nativeIdentifier = .authorized(system: system, type: try? GovernedSourceIdentifierType(system: typeSystem, code: "record")) }),
            ("type display", {
                $0.nativeIdentifier = .authorized(system: system, type: try? GovernedSourceIdentifierType(system: typeSystem, code: "store", display: "Store"))
            }),
            ("udi", { $0.udi = .authorized })
        ]
    }

    @Test("G3: every option, the subject, the repository and identity scopes and each output revision version the event")
    @available(*, deprecated, message: "Names the transitional legacy Bundle.id case")
    func everyContextInputVersionsTheEvent() throws {
        let sequencer = ExchangeEventSequencer.inMemory()
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(1), device: GoldenFixtures.watch, writer: GoldenFixtures.foreignWriter)
        let base = try Fixtures.producer(sequencer: sequencer)
        var exporters: [(String, HealthKitFHIRExporter)] = try Self.optionPerturbations().map { name, configure in
            (name, try Fixtures.exporter(base, configure))
        }
        let systems = Fixtures.base.identityScope.systems
        exporters += [
            ("subject", try Fixtures.exporter(try Fixtures.producer(subject: .logical(.test(.patient, "other")), sequencer: sequencer))),
            ("bundled subject", try Fixtures.exporter(try Fixtures.producer(subject: .bundled(.test(.patient, "example"), .init()), sequencer: sequencer))),
            ("repository scope", try Fixtures.exporter(base, repositoryScope: .test(.device, "secondary"))),
            ("epoch", try Fixtures.exporter(try Fixtures.producer(
                identityScope: OpaqueIdentityScope(systems: systems, keyID: "test", epoch: EventSequence(2), key: Self.key),
                sequencer: sequencer
            ))),
            ("key", try Fixtures.exporter(try Fixtures.producer(
                identityScope: OpaqueIdentityScope(systems: systems, keyID: "test", epoch: EventSequence(1), key: SymmetricKey(data: Data(repeating: 7, count: 32))),
                sequencer: sequencer
            ))),
            ("assembler revision", try Fixtures.exporter(base, revisions: .init(assembler: ExchangeGraphAssembler.outputRevision + 1, healthKit: HealthKitAssembly.outputRevision))),
            ("adapter revision", try Fixtures.exporter(base, revisions: .init(assembler: ExchangeGraphAssembler.outputRevision, healthKit: HealthKitAssembly.outputRevision + 1)))
        ]
        let (original, _) = try Fixtures.collect(try Fixtures.exporter(base), samples: [sample])
        let (unchanged, _) = try Fixtures.collect(try Fixtures.exporter(base), samples: [sample])
        #expect(unchanged[0].event == original[0].event, "an equal context reuses the reservation")
        var sequences = [try #require(original[0].sequence)]
        for (name, exporter) in exporters {
            let (exports, _) = try Fixtures.collect(exporter, samples: [sample])
            let sequence = try #require(exports[0].sequence, "\(name): \(exports[0].outcome)")
            #expect(!sequences.contains(sequence), "\(name) reused an event")
            sequences.append(sequence)
        }
    }

    @Test("G3b: the fingerprint covers every stored option")
    func fingerprintCoversEveryOption() {
        let options = HealthKitFHIRExporter.Options()
        let stored = Mirror(reflecting: options).children.compactMap(\.label)
        #expect(!stored.isEmpty)
        #expect(options.fingerprintParts.map(\.property) == stored)
    }

    @Test("The ledger fingerprint of an identity scope is keyed and reveals nothing about the key")
    func ledgerFingerprintIsKeyed() throws {
        let scope = Fixtures.base.identityScope
        let again = try OpaqueIdentityScope(systems: scope.systems, keyID: scope.keyID, epoch: scope.epoch, key: Self.key)
        let rekeyed = try OpaqueIdentityScope(systems: scope.systems, keyID: scope.keyID, epoch: scope.epoch, key: SymmetricKey(data: Data(repeating: 7, count: 32)))
        #expect(scope.ledgerFingerprint == again.ledgerFingerprint)
        #expect(scope.ledgerFingerprint != rekeyed.ledgerFingerprint)
        #expect(scope.ledgerFingerprint.utf8.count == 43)
        #expect(!scope.ledgerFingerprint.contains(Data(repeating: 0x42, count: 32).base64EncodedString()))
    }
}

#endif
