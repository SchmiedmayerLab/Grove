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
            ("writer applications", { $0.writer = .applications(["org.example.writer"]) }),
            // The size of the set above with another member: only the members tell the two apart.
            ("writer applications other", { $0.writer = .applications(["org.example.other"]) }),
            ("writer applications member", { $0.writer = .applications(["org.example.writer", "org.example.other"]) }),
            ("writer applications empty", { $0.writer = .applications([]) }),
            ("writer classify", { $0.writer = .classify { _ in .application } }),
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

    /// The base context first, then every perturbation of an option, the subject, a scope or an output revision.
    @available(*, deprecated, message: "Names the transitional legacy Bundle.id case")
    private static func contexts(sequencer: ExchangeEventSequencer) throws -> [(String, HealthKitFHIRExporter)] {
        let base = try Fixtures.producer(sequencer: sequencer)
        let systems = Fixtures.base.identityScope.systems
        let pseudonym = Fixtures.base.subject.identifier
        var patient = Patient()
        patient.gender = FHIRPrimitive(AdministrativeGender.female)
        func scope(keyID: String = "test", epoch: UInt64 = 1, key: SymmetricKey = Self.key) throws -> OpaqueIdentityScope {
            try OpaqueIdentityScope(systems: systems, keyID: keyID, epoch: EventSequence(epoch), key: key)
        }
        var contexts: [(String, HealthKitFHIRExporter)] = [("base", try Fixtures.exporter(base))]
        contexts += try Self.optionPerturbations().map { name, configure in
            (name, try Fixtures.exporter(base, configure))
        }
        contexts += [
            ("subject", try Fixtures.exporter(try Fixtures.producer(subject: .logical(.test(.patient, "other")), sequencer: sequencer))),
            ("bundled subject", try Fixtures.exporter(try Fixtures.producer(subject: .bundled(pseudonym, Patient()), sequencer: sequencer))),
            ("bundled Patient content", try Fixtures.exporter(try Fixtures.producer(subject: .bundled(pseudonym, patient), sequencer: sequencer))),
            ("repository scope", try Fixtures.exporter(base, repositoryScope: .test(.device, "secondary"))),
            ("epoch", try Fixtures.exporter(try Fixtures.producer(identityScope: scope(epoch: 2), sequencer: sequencer))),
            ("key", try Fixtures.exporter(try Fixtures.producer(identityScope: scope(key: SymmetricKey(data: Data(repeating: 7, count: 32))), sequencer: sequencer))),
            ("key id", try Fixtures.exporter(try Fixtures.producer(identityScope: scope(keyID: "other"), sequencer: sequencer))),
            ("assembler revision", try Fixtures.exporter(base, revisions: .init(assembler: ExchangeGraphAssembler.outputRevision + 1, healthKit: HealthKitAssembly.outputRevision))),
            ("adapter revision", try Fixtures.exporter(base, revisions: .init(assembler: ExchangeGraphAssembler.outputRevision, healthKit: HealthKitAssembly.outputRevision + 1)))
        ]
        return contexts
    }

    @Test("G3: the base context and every perturbation of an option, the subject, a scope or an output revision fingerprint pairwise apart")
    @available(*, deprecated, message: "Names the transitional legacy Bundle.id case")
    func everyContextInputVersionsTheEvent() throws {
        let contexts = try Self.contexts(sequencer: .inMemory())
        let key = ExchangeEventKey.active(type: .heartRate, uuid: GoldenFixtures.uuid(1))
        let fingerprints = contexts.map { name, exporter in (name, exporter.context.request(for: key).fingerprint) }
        for (index, (name, fingerprint)) in fingerprints.enumerated() {
            for (earlier, earlierFingerprint) in fingerprints[..<index] where earlierFingerprint == fingerprint {
                Issue.record("\(name) shares its fingerprint with \(earlier)")
            }
        }
        #expect(Set(fingerprints.map(\.1)).count == contexts.count)
    }

    @Test("G3: an export reserves under its context's fingerprint; an equal context reuses the event and another does not")
    @available(*, deprecated, message: "Names the transitional legacy Bundle.id case")
    func exportsReserveUnderTheirContextFingerprint() throws {
        let storage = ExchangeEventSequencer.InMemoryStorage()
        let contexts = try Self.contexts(sequencer: ExchangeEventSequencer(storage: storage))
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(1), device: GoldenFixtures.watch, writer: GoldenFixtures.foreignWriter)
        let key = try #require(ExchangeEventKey.active(sample))
        let (original, _) = try Fixtures.collect(contexts[0].1, samples: [sample])
        let stored = try #require(try storage.transaction { try $0.read(LedgerKey.event(key)) })
        #expect(try EventEntry(decoding: stored, key: LedgerKey.event(key)).fingerprint == contexts[0].1.context.request(for: key).fingerprint)
        let (unchanged, _) = try Fixtures.collect(try Fixtures.exporter(try Fixtures.producer(sequencer: ExchangeEventSequencer(storage: storage))), samples: [sample])
        #expect(unchanged[0].event == original[0].event, "an equal context reuses the reservation")
        let (changed, _) = try Fixtures.collect(contexts[1].1, samples: [sample])
        #expect(changed[0].event != original[0].event, "\(contexts[1].0) reused an event")
    }

    @Test("A writer-policy change gives a reserved record a new sequence, never one handed out under another policy")
    func writerPolicyChangeTakesANewSequence() throws {
        let sequencer = ExchangeEventSequencer.inMemory()
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(2), writer: GoldenFixtures.foreignWriter)
        let omitting = try Fixtures.exporter(sequencer: sequencer)
        let classifying = try Fixtures.exporter(sequencer: sequencer) { $0.writer = .applications([GoldenFixtures.foreignWriter.bundleIdentifier]) }
        let (omitted, _) = try Fixtures.collect(omitting, samples: [sample])
        let (stated, _) = try Fixtures.collect(classifying, samples: [sample])
        let (reverted, _) = try Fixtures.collect(omitting, samples: [sample])
        #expect([omitted, stated, reverted].map { $0.first?.sequence } == ["1", "2", "3"])
        #expect(stated.first?.graph?.json != omitted.first?.graph?.json, "the classified source states its writer")
    }

    @Test("Equal application sets fingerprint equally, whatever order their members were inserted in")
    func applicationSetsFingerprintByMembership() throws {
        let identifiers = (0..<24).map { "org.example.app\($0)" }
        let inserted = Set(identifiers)
        var reversed = Set<String>(minimumCapacity: 512)
        for identifier in identifiers.reversed() {
            reversed.insert(identifier)
        }
        try #require(inserted == reversed)
        try #require(Array(inserted) != Array(reversed), "the two sets must iterate in different orders for this test to discriminate")
        let key = ExchangeEventKey.active(type: .heartRate, uuid: GoldenFixtures.uuid(1))
        func fingerprint(_ bundleIdentifiers: Set<String>) throws -> String {
            try Fixtures.exporter { $0.writer = .applications(bundleIdentifiers) }.context.request(for: key).fingerprint
        }
        #expect(try fingerprint(inserted) == fingerprint(reversed))
        #expect(try fingerprint(inserted) != fingerprint(inserted.subtracting(["org.example.app0"])), "a member less")
        #expect(
            try fingerprint(inserted) != fingerprint(inserted.subtracting(["org.example.app0"]).union(["org.example.app24"])),
            "another member in its place"
        )
    }

    /// A reservation keeps the fingerprint it was made under, and every later export compares against it, across
    /// launches and app updates: a build that derives the same context's fingerprint differently gives every pending
    /// reservation a new sequence on redelivery, so the derivation changes only on purpose. One member of the
    /// application set is not in Unicode normalization form C, so its UTF-8 byte order differs from Swift's `String`
    /// order.
    @Test("A fixed context fingerprints to a known answer, its application set as tag, count and members in UTF-8 byte order")
    func contextFingerprintIsAKnownAnswer() throws {
        let decomposed = "org.example.cafe\u{301}"
        let writer = HealthKitFHIRExporter.WriterPolicy.applications(["org.example.caff", decomposed])
        let expectedParts = ["applications", "2", decomposed, "org.example.caff"]
        #expect(writer.fingerprintParts.map { Array($0.utf8) } == expectedParts.map { Array($0.utf8) })
        let exporter = try Fixtures.exporter(try Fixtures.producer(sequencer: .inMemory()), revisions: .init(assembler: 1, healthKit: 2)) {
            $0.writer = writer
        }
        let key = ExchangeEventKey.active(type: .heartRate, uuid: GoldenFixtures.uuid(1))
        #expect(exporter.context.request(for: key).fingerprint == "Y9AmAuXc9kZTd8ZjijBhBS7QD_7A8w4YKQLk7RXFRig")
    }

    @Test("G3b: the fingerprint covers every stored option, each under its own name and with its own value")
    @available(*, deprecated, message: "Names the transitional legacy Bundle.id case")
    func fingerprintCoversEveryOption() {
        let configurations = [HealthKitFHIRExporter.Options()] + Self.optionPerturbations().map { _, configure in
            var options = HealthKitFHIRExporter.Options()
            configure(&options)
            return options
        }
        for options in configurations {
            let stored = Mirror(reflecting: options).children.map { child in
                (property: child.label ?? "", parts: (child.value as? any ExchangeContextFingerprinted)?.fingerprintParts ?? [])
            }
            #expect(!stored.isEmpty)
            #expect(options.fingerprintParts.map(\.property) == stored.map(\.property))
            #expect(options.fingerprintParts.map(\.parts) == stored.map(\.parts), "\(stored.map(\.property))")
        }
    }
}

#endif
