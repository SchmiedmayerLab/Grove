//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// The readable sync identifier: the exact `HKMetadataKeySyncIdentifier` text, which the native-identifier setting
/// discloses beside the HealthKit UUID on the primary output, under a system scoped to the store and the writing
/// application. The sync pair is never an entry of the metadata extension (HealthKit guide `mapping.md`, readable sync
/// identifier).
@Suite
struct HealthKitSyncIdentifierTests {
    private typealias Warnings = HealthKitMetadataWarningTests

    private static let store = GoldenFixtures.nativeIdentifierSystem
    private static let otherWriter = StoredSampleFixtures.Writer(name: "Other Writer", bundleIdentifier: "org.example.other", version: "7", productType: "iPhone17,1")
    private static let syncKeys = [HKMetadataKeySyncIdentifier, HKMetadataKeySyncVersion]
    private static let metadata = GoldenFixtures.timeZoneMetadata.merging(Warnings.syncPair) { $1 }

    /// The inputs of an exporter whose native-identifier setting authorizes `system`, or omits when `nil`.
    private static func inputs(disclosing system: IdentifierSystem? = store) -> ExportInputs {
        var inputs = ExportInputs()
        inputs.options.route = .authorized
        if let system {
            inputs.options.nativeIdentifier = .authorized(system: system)
            inputs.options.syncIdentifier = .authorized
        }
        return inputs
    }

    private static func heartRate(
        _ inputs: ExportInputs,
        metadata: [String: any Sendable] = metadata,
        writer: StoredSampleFixtures.Writer = GoldenFixtures.foreignWriter
    ) throws -> HealthKitAssembly.Conversion {
        try Warnings.convert(
            StoredSampleFixtures.quantitySample(
                HKQuantityType(.heartRate),
                value: 72,
                unit: GoldenFixtures.beatsPerMinute,
                facts: Warnings.facts(0xA1, metadata: metadata, writer: writer)
            ),
            inputs
        )
    }

    /// The document of each document source type, stating `metadata`: a heartbeat series, a workout route and, where the
    /// platform has clinical records, a CDA document.
    private static func documents(_ inputs: ExportInputs, metadata: [String: any Sendable] = metadata) throws -> [HealthKitAssembly.Conversion] {
        let series = try StoredSampleFixtures.seriesSample(
            HKHeartbeatSeriesSample.self,
            sampleType: HKSeriesType.heartbeat(),
            facts: Warnings.facts(0xA2, duration: 2, metadata: metadata)
        )
        let route = try StoredSampleFixtures.seriesSample(
            HKWorkoutRoute.self,
            sampleType: HKSeriesType.workoutRoute(),
            facts: Warnings.facts(0xA3, duration: 1, metadata: metadata)
        )
        var conversions = try [
            #require(try AssemblyFixtures.conversions(.heartbeatSeries(series, beats: ContentCorpusGrid.heartbeats.map(\.heartbeat)), inputs).first),
            #require(try AssemblyFixtures.conversions(.workoutRoute(route, locations: GoldenCase.routeLocations), inputs).first)
        ]
        #if !os(watchOS)
        let document = try HKCDADocumentSample(
            data: Data(GoldenCase.clinicalDocumentXML.utf8),
            start: GoldenFixtures.sampleStart,
            end: GoldenFixtures.sampleStart.addingTimeInterval(1),
            metadata: nil
        )
        let stored = try StoredSampleFixtures.stored(document, uuid: GoldenFixtures.uuid(0xA4), writer: GoldenFixtures.foreignWriter)
        conversions.append(try Warnings.convert(StoredSampleFixtures.withMetadata(stored, metadata), inputs))
        #endif
        return conversions
    }

    /// The identifiers and extensions of the record's primary output, an Observation or its sole document.
    private static func primary(of conversion: HealthKitAssembly.Conversion) throws -> (identifiers: [Identifier], extensions: [Extension]) {
        let resource = try #require(conversion.record.bundle.entry?.first?.resource)
        if let observation = resource.get(if: Observation.self) {
            return (observation.identifier ?? [], observation.extension ?? [])
        }
        let document = try #require(resource.get(if: DocumentReference.self))
        return (document.identifier ?? [], document.extension ?? [])
    }

    private static func isSyncIdentifier(_ identifier: Identifier) -> Bool {
        identifier.type?.coding?.contains { $0.code?.value?.string == "healthkit-sync-id" } == true
    }

    /// The system and value of each readable sync identifier anywhere in the record.
    private static func syncIdentifiers(in conversion: HealthKitAssembly.Conversion) -> [[String?]] {
        (conversion.record.bundle.entry ?? []).flatMap { entry -> [Identifier] in
            entry.resource?.get(if: Observation.self)?.identifier ?? entry.resource?.get(if: DocumentReference.self)?.identifier ?? []
        }
        .filter(isSyncIdentifier)
        .map { [$0.system?.value?.url.absoluteString, $0.value?.value?.string] }
    }

    private static func writerVersions(_ extensions: [Extension]) -> [String?] {
        extensions.filter { $0.url == Canonicals.writerRecordVersion }.map { version in
            if case .string(let value)? = version.value { value.value?.string } else { nil }
        }
    }

    /// The keys of the typed metadata extension anywhere in the record's JSON.
    private static func statesSyncMetadata(_ conversion: HealthKitAssembly.Conversion) -> Bool {
        let json = String(decoding: conversion.record.json, as: UTF8.self)
        return syncKeys.contains { json.contains($0) }
    }


    @Test("The native-identifier setting discloses the UUID and the sync identifier together, and neither while it omits")
    func oneSettingGatesBothReadableIdentifiers() throws {
        let omitted = try Self.heartRate(Self.inputs(disclosing: nil))
        let disclosed = try Self.heartRate(Self.inputs())

        let hidden = try Self.primary(of: omitted)
        #expect(try hidden.identifiers.map { try RoledIdentifier($0).role } == [.sourceRecord, .sourceOutput, .writerRecord])
        #expect(Self.writerVersions(hidden.extensions) == ["3"])
        #expect(!String(decoding: omitted.record.json, as: UTF8.self).contains("sync-abc"), "the sync identifier text reaches no element")

        let shown = try Self.primary(of: disclosed)
        let readable = shown.identifiers.filter { (try? RoledIdentifier($0)) == nil }
        #expect(readable.map { $0.system?.value?.url.absoluteString } == [
            "https://study.example.org/fhir/NamingSystem/healthkit-store",
            "https://study.example.org/fhir/NamingSystem/healthkit-store/healthkit-sync-identifier/org.example.writer"
        ])
        #expect(readable.map { $0.value?.value?.string } == [GoldenFixtures.uuid(0xA1).uuidString.lowercased(), "sync-abc"])
        let type = try #require(readable.last?.type)
        #expect(type.text == nil)
        #expect(type.coding?.count == 1)
        #expect(type.coding?.first?.system == "https://grovealliance.org/fhir/healthkit/CodeSystem/healthkit-identifier-type")
        #expect(type.coding?.first?.code?.value?.string == "healthkit-sync-id")
        #expect(Self.writerVersions(shown.extensions) == ["3"])

        // The readable value is traceability: every Grove identity and entry key stays as it is without it.
        #expect(shown.identifiers.filter { (try? RoledIdentifier($0)) != nil } == hidden.identifiers)
        #expect(disclosed.record.bundle.entry?.first?.fullUrl == omitted.record.bundle.entry?.first?.fullUrl)
        #expect(disclosed.identifiers.sourceRecord == omitted.identifiers.sourceRecord)
        #expect(disclosed.identifiers.primaryOutput == omitted.identifiers.primaryOutput)
        #expect(disclosed.record.json != omitted.record.json, "disclosure changes the record's content")
        for conversion in [omitted, disclosed] {
            #expect(conversion.withheldMetadataKeys.isEmpty)
            #expect(conversion.warnings.isEmpty)
        }
    }

    @Test("A sample without a sync pair states no readable sync identifier")
    func noPairStatesNoSyncIdentifier() throws {
        let conversions = try [Self.heartRate(Self.inputs(), metadata: GoldenFixtures.timeZoneMetadata)]
            + Self.documents(Self.inputs(), metadata: GoldenFixtures.timeZoneMetadata)
        for conversion in conversions {
            let primary = try Self.primary(of: conversion)
            #expect(Self.syncIdentifiers(in: conversion).isEmpty, "\(conversion.source.typeIdentifier)")
            #expect(primary.identifiers.filter { (try? RoledIdentifier($0)) == nil }.count == 1, "only the UUID, \(conversion.source.typeIdentifier)")
            #expect(Self.writerVersions(primary.extensions).isEmpty)
        }
    }

    @Test("Equal sync identifiers of two writing applications and of two participant stores have distinct systems")
    func writersAndStoresScopeTheSystem() throws {
        let otherStore: IdentifierSystem = "https://study.example.org/fhir/NamingSystem/healthkit-store-2"
        var systems: [String?] = []
        for store in [Self.store, otherStore] {
            for writer in [GoldenFixtures.foreignWriter, Self.otherWriter] {
                let identifiers = Self.syncIdentifiers(in: try Self.heartRate(Self.inputs(disclosing: store), writer: writer))
                try #require(identifiers.count == 1)
                #expect(identifiers[0][1] == "sync-abc")
                systems.append(identifiers[0][0])
            }
        }
        #expect(systems == [
            "https://study.example.org/fhir/NamingSystem/healthkit-store/healthkit-sync-identifier/org.example.writer",
            "https://study.example.org/fhir/NamingSystem/healthkit-store/healthkit-sync-identifier/org.example.other",
            "https://study.example.org/fhir/NamingSystem/healthkit-store-2/healthkit-sync-identifier/org.example.writer",
            "https://study.example.org/fhir/NamingSystem/healthkit-store-2/healthkit-sync-identifier/org.example.other"
        ])
    }

    @Test("The sync identifier text is exact")
    func textIsExact() throws {
        let text = " Reading/42 | e\u{301}?#"
        let conversion = try Self.heartRate(Self.inputs(), metadata: Self.metadata.merging([HKMetadataKeySyncIdentifier: text]) { $1 })
        let system = "https://study.example.org/fhir/NamingSystem/healthkit-store/healthkit-sync-identifier/org.example.writer"
        #expect(Self.syncIdentifiers(in: conversion) == [[system, text]])
        #expect(try ExchangeGraph(validating: conversion.record.json, kind: .active).json == conversion.record.json)
    }

    @Test("A bundle identifier that cannot be a system segment withholds the readable sync identifier and reports it")
    func unrepresentableWriterWithholdsTheText() throws {
        for bundleIdentifier in ["org.example/writer", "org.example.wr\u{E9}ter", "org.example writer", "org.example_writer", "org.example%2Fwriter"] {
            let writer = StoredSampleFixtures.Writer(name: "Odd Writer", bundleIdentifier: bundleIdentifier, version: "1", productType: nil)
            let disclosed = try Self.heartRate(Self.inputs(), writer: writer)
            let primary = try Self.primary(of: disclosed)
            #expect(Self.syncIdentifiers(in: disclosed).isEmpty, "\(bundleIdentifier)")
            #expect(!String(decoding: disclosed.record.json, as: UTF8.self).contains("sync-abc"), "\(bundleIdentifier)")
            #expect(primary.identifiers.contains { (try? RoledIdentifier($0).role) == .writerRecord }, "the keyed identity still travels")
            #expect(Self.writerVersions(primary.extensions) == ["3"])
            #expect(disclosed.withheldMetadataKeys == [HKMetadataKeySyncIdentifier], "\(bundleIdentifier)")
            #expect(disclosed.warnings == [Warnings.unmodeled], "\(bundleIdentifier)")
            // While the setting omits readable identifiers, nothing the deployment asked for is withheld.
            let omitted = try Self.heartRate(Self.inputs(disclosing: nil), writer: writer)
            #expect(omitted.withheldMetadataKeys.isEmpty)
            #expect(omitted.warnings.isEmpty)
        }
    }

    @Test("A document states the writer record, its version and the readable sync identifier as an Observation does")
    func documentsStateTheWriterRecordAsObservationsDo() throws {
        let observation = try Self.primary(of: Self.heartRate(Self.inputs()))
        let writerRecord = try #require(observation.identifiers.first { (try? RoledIdentifier($0).role) == .writerRecord })
        let plain = try Self.documents(Self.inputs(disclosing: nil), metadata: GoldenFixtures.timeZoneMetadata)
        let omitted = try Self.documents(Self.inputs(disclosing: nil))
        let disclosed = try Self.documents(Self.inputs())
        for (index, conversion) in disclosed.enumerated() {
            let type = conversion.source.typeIdentifier
            let primary = try Self.primary(of: conversion)
            let roled = primary.identifiers.compactMap { try? RoledIdentifier($0) }
            #expect(roled.map(\.role) == [.sourceRecord, .sourceOutput, .sourceArtifact, .writerRecord], "\(type)")
            // One writer and one sync identifier name one logical record, whatever output type carries them.
            #expect(primary.identifiers.contains(writerRecord), "\(type)")
            #expect(Self.writerVersions(primary.extensions) == ["3"], "\(type)")
            let system = "https://study.example.org/fhir/NamingSystem/healthkit-store/healthkit-sync-identifier/org.example.writer"
            #expect(Self.syncIdentifiers(in: conversion) == [[system, "sync-abc"]], "\(type)")
            #expect(conversion.withheldMetadataKeys.isEmpty, "\(type)")
            #expect(conversion.warnings.isEmpty, "\(type)")
            #expect(!Self.statesSyncMetadata(conversion), "\(type)")
            #expect(try HealthKitWriterRecordPairingTests.unpairedWriterRecords(in: LosslessJSONValue(parsing: conversion.record.json)).isEmpty)

            let hidden = try Self.primary(of: omitted[index])
            #expect(hidden.identifiers.compactMap { try? RoledIdentifier($0) } == roled, "\(type)")
            #expect(hidden.identifiers.count == roled.count, "no readable identifier, \(type)")
            #expect(Self.writerVersions(hidden.extensions) == ["3"], "\(type)")
            #expect(!String(decoding: omitted[index].record.json, as: UTF8.self).contains("sync-abc"), "\(type)")

            // The source bytes and their hash are those of the same record without a sync pair.
            let contents = try [conversion, omitted[index], plain[index]].map { conversion in
                try #require(conversion.record.bundle.entry?.first?.resource?.get(if: DocumentReference.self)).content
            }
            #expect(contents[0] == contents[2], "\(type)")
            #expect(contents[1] == contents[2], "\(type)")
            #expect(conversion.record.bundle.entry?.first?.fullUrl == plain[index].record.bundle.entry?.first?.fullUrl, "\(type)")
        }
    }

    @Test("The metadata extension never carries the sync pair, under either setting and every metadata policy")
    func metadataNeverCarriesTheSyncPair() throws {
        let custom = Self.metadata.merging(["com.example.note": "kept"]) { $1 }
        for system in [nil, Self.store] {
            for policy in [HealthKitFHIRExporter.MetadataPolicy.all, .nonIdentifying, .omit] {
                var inputs = Self.inputs(disclosing: system)
                inputs.options.metadata = policy
                let conversions = try [Self.heartRate(inputs, metadata: custom)] + Self.documents(inputs, metadata: custom)
                // The same records without the pair: the pair adds nothing to what the extension preserves or excludes.
                let unpaired = custom.filter { !Self.syncKeys.contains($0.key) }
                let plain = try [Self.heartRate(inputs, metadata: unpaired)] + Self.documents(inputs, metadata: unpaired)
                for (conversion, plain) in zip(conversions, plain) {
                    let type = conversion.source.typeIdentifier
                    #expect(!Self.statesSyncMetadata(conversion), "\(type)")
                    #expect(conversion.withheldMetadataKeys.isEmpty, "\(type)")
                    #expect(conversion.metadataSummary == plain.metadataSummary, "\(type)")
                    #expect(conversion.metadataSummary.preservedSampleKeys + conversion.metadataSummary.excludedSampleKeys >= 1, "\(type)")
                }
            }
        }
    }

    @Test("A sync pair of a source without a bundle identifier is reported as withheld and exported in no element")
    func unattributablePairIsWithheld() throws {
        for policy in [HealthKitFHIRExporter.MetadataPolicy.all, .nonIdentifying, .omit] {
            var inputs = Self.inputs()
            inputs.options.metadata = policy
            let conversion = try Self.heartRate(inputs, writer: .unattributed)
            let json = String(decoding: conversion.record.json, as: UTF8.self)
            #expect(conversion.withheldMetadataKeys == Self.syncKeys)
            #expect(conversion.warnings == [Warnings.unmodeled])
            #expect(!json.contains("writer-record"))
            #expect(!json.contains("sync-abc"))
            #expect(!Self.statesSyncMetadata(conversion))
            #expect(Self.syncIdentifiers(in: conversion).isEmpty)
            #expect(conversion.metadataSummary == .init(preservedSampleKeys: 0, unsupportedSampleKeys: 0, excludedSampleKeys: 0))
        }
    }

    @Test("Only the primary output states the readable sync identifier: a workout's segments and an ECG's heart rate do not")
    func childrenStateNoReadableSyncIdentifier() throws {
        let original = GoldenFixtures.workout(withEvents: true, device: GoldenFixtures.watch, userEntered: true)
        let workout = try StoredSampleFixtures.stored(
            StoredSampleFixtures.withMetadata(original, (original.metadata ?? [:]).merging(Warnings.syncPair) { $1 }),
            uuid: GoldenFixtures.uuid(0xA5),
            writer: GoldenFixtures.foreignWriter
        )
        let record = try GoldenCase.electrocardiogramRecord(uuid: 0xA6, symptoms: [])
        _ = try StoredSampleFixtures.withMetadata(record.electrocardiogram, Self.metadata)
        let conversions = try [
            AssemblyFixtures.conversion(workout, Self.inputs()),
            #require(try AssemblyFixtures.conversions(ExporterFixtures.electrocardiogram(record, symptoms: []), Self.inputs()).first)
        ]
        for conversion in conversions {
            let observations = (conversion.record.bundle.entry ?? []).compactMap { $0.resource?.get(if: Observation.self) }
            try #require(observations.count > 1, "\(conversion.source.typeIdentifier)")
            #expect(observations[0].identifier?.filter(Self.isSyncIdentifier).count == 1)
            for child in observations.dropFirst() {
                #expect(child.identifier?.contains { (try? RoledIdentifier($0)) == nil } == false, "\(conversion.source.typeIdentifier)")
            }
            #expect(Self.syncIdentifiers(in: conversion).count == 1)
            #expect(conversion.withheldMetadataKeys.isEmpty)
        }
    }

    @Test("A deployment system inside the namespace of readable sync identifiers refuses the native identifier system")
    func derivedNamespaceIsReserved() throws {
        let store: IdentifierSystem = "https://study.example.org/fhir/NamingSystem/healthkit-store"
        var inputs = Self.inputs(disclosing: store)
        inputs.graphIdentifierSystem = "https://study.example.org/fhir/NamingSystem/healthkit-store/healthkit-sync-identifier/org"
        #expect(throws: HealthKitFHIRExporter.ConfigurationError.reservedNativeIdentifierSystem(store)) {
            try ExporterFixtures.exporter(inputs)
        }
        inputs.graphIdentifierSystem = "https://study.example.org/fhir/NamingSystem/healthkit-store/healthkit-sync-identifiers"
        _ = try ExporterFixtures.exporter(inputs)
    }

    @Test("A native identifier system the sync identifier's path cannot extend is refused at configuration, and only then")
    func nonExtensibleSystemIsRefused() throws {
        let systems: [IdentifierSystem] = [
            "urn:oid:2.16.840.1.113883.3.1",
            "urn:uuid:6f1b2c4e-8a7d-4b3f-9c2e-1d5a7b9e3f20",
            "https://study.example.org/store?participant=42",
            "https://study.example.org/store#participant-42"
        ]
        for system in systems {
            #expect(throws: HealthKitFHIRExporter.ConfigurationError.nativeIdentifierSystemNotExtensible(system)) {
                try ExporterFixtures.exporter(Self.inputs(disclosing: system))
            }
            // Without the sync identifier, nothing extends the system: the UUID alone may use it.
            var uuidOnly = Self.inputs(disclosing: system)
            uuidOnly.options.syncIdentifier = .omit
            _ = try ExporterFixtures.exporter(uuidOnly)
        }
        _ = try ExporterFixtures.exporter(Self.inputs(disclosing: "https://study.example.org/store/participant-42"))
    }

    @Test("A native identifier typed as a readable sync identifier is refused at configuration")
    func syncIdentifierTypeIsReserved() throws {
        let typeSystem: IdentifierSystem = "https://grovealliance.org/fhir/healthkit/CodeSystem/healthkit-identifier-type"
        let reserved = try GovernedSourceIdentifierDisclosurePolicy.IdentifierType(system: typeSystem, code: "healthkit-sync-id")
        var inputs = Self.inputs()
        inputs.options.nativeIdentifier = .authorized(system: Self.store, type: reserved)
        inputs.options.syncIdentifier = .authorized
        #expect(throws: HealthKitFHIRExporter.ConfigurationError.reservedNativeIdentifierType(reserved)) {
            try ExporterFixtures.exporter(inputs)
        }
        let other = try GovernedSourceIdentifierDisclosurePolicy.IdentifierType(system: typeSystem, code: "healthkit-uuid")
        inputs.options.nativeIdentifier = .authorized(system: Self.store, type: other)
        inputs.options.syncIdentifier = .authorized
        _ = try ExporterFixtures.exporter(inputs)
    }

    @Test("A document's readable sync identifier is valid only beside the UUID, the writer record and its version")
    func graphValidationGovernsTheDocumentIdentifier() throws {
        let conversion = try #require(try Self.documents(Self.inputs()).first)

        /// Validates the record after `edit` changed its document.
        func validate(_ edit: (inout DocumentReference) throws -> Void) throws {
            var bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: conversion.record.json)
            var document = try #require(bundle.entry?.first?.resource?.get(if: DocumentReference.self))
            try edit(&document)
            bundle.entry?[0].resource = .documentReference(document)
            _ = try ExchangeGraph(kind: .active, bundle: bundle)
        }
        /// Changes the system of the document's readable sync identifier.
        func resystem(_ text: String) -> (inout DocumentReference) throws -> Void {
            { document in
                let index = try #require(document.identifier?.firstIndex(where: Self.isSyncIdentifier))
                let identifier = try #require(document.identifier?[index])
                document.identifier?[index] = Identifier(system: FHIRPrimitive(FHIRURI(stringLiteral: text)), type: identifier.type, value: identifier.value)
            }
        }
        let store = Self.store.rawValue
        try validate { _ in }

        let edits: [(String, (inout DocumentReference) throws -> Void)] = [
            ("without the UUID", { $0.identifier?.removeAll { $0.system?.value?.url.absoluteString == store } }),
            ("without the writer record", { $0.identifier?.removeAll { (try? RoledIdentifier($0).role) == .writerRecord } }),
            ("without the version", { $0.extension?.removeAll { $0.url == Canonicals.writerRecordVersion } }),
            ("twice", { document in
                let sync = try #require(document.identifier?.first(where: Self.isSyncIdentifier))
                document.identifier?.append(sync)
            }),
            ("under the UUID's system", resystem(store)),
            ("under another store's system", resystem("https://other.example.org/store/healthkit-sync-identifier/org.example")),
            ("without a writer segment", resystem("\(store)/healthkit-sync-identifier/")),
            ("with an escaped writer segment", resystem("\(store)/healthkit-sync-identifier/org.example%2Fwriter")),
            ("with a writer segment outside the bundle identifier grammar", resystem("\(store)/healthkit-sync-identifier/org.example_writer")),
            ("without a store scope", resystem("/healthkit-sync-identifier/org")),
            ("with a second type coding", { document in
                let index = try #require(document.identifier?.firstIndex(where: Self.isSyncIdentifier))
                let identifier = try #require(document.identifier?[index])
                let other = Coding(code: "other", system: "https://study.example.org/fhir/CodeSystem/identifier-type")
                let type = CodeableConcept(coding: (identifier.type?.coding ?? []) + [other])
                document.identifier?[index] = Identifier(system: identifier.system, type: type, value: identifier.value)
            })
        ]
        for (description, edit) in edits {
            #expect(throws: ExchangeGraphError.ruleViolation(.sensorRecordingDocumentIdentityAndContent), "a sync identifier \(description)") {
                try validate(edit)
            }
        }
    }

    @Test("An Observation's readable sync identifier is valid only beside the UUID, the writer record and its version")
    func graphValidationGovernsTheObservationIdentifier() throws {
        let conversion = try Self.heartRate(Self.inputs())

        /// Validates the record after `edit` changed its Observation.
        func validate(_ edit: (inout Observation) throws -> Void) throws {
            var bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: conversion.record.json)
            let index = try #require(bundle.entry?.firstIndex { $0.resource?.get(if: Observation.self) != nil })
            var observation = try #require(bundle.entry?[index].resource?.get(if: Observation.self))
            try edit(&observation)
            bundle.entry?[index].resource = .observation(observation)
            _ = try ExchangeGraph(kind: .active, bundle: bundle)
        }
        let store = Self.store.rawValue
        try validate { _ in }

        let edits: [(String, (inout Observation) throws -> Void)] = [
            ("without the UUID", { $0.identifier?.removeAll { $0.system?.value?.url.absoluteString == store } }),
            ("without the writer record", { $0.identifier?.removeAll { (try? RoledIdentifier($0).role) == .writerRecord } }),
            ("without the version", { $0.extension?.removeAll { $0.url == Canonicals.writerRecordVersion } }),
            ("twice", { observation in
                let sync = try #require(observation.identifier?.first(where: Self.isSyncIdentifier))
                observation.identifier?.append(sync)
            }),
            ("under another store's system", { observation in
                let index = try #require(observation.identifier?.firstIndex(where: Self.isSyncIdentifier))
                let identifier = try #require(observation.identifier?[index])
                let system = "https://other.example.org/store/healthkit-sync-identifier/org.example"
                observation.identifier?[index] = Identifier(system: FHIRPrimitive(FHIRURI(stringLiteral: system)), type: identifier.type, value: identifier.value)
            })
        ]
        for (description, edit) in edits {
            let error = #expect(throws: ExchangeGraphError.self, "a sync identifier \(description)") {
                try validate(edit)
            }
            guard case .invalidEntries? = error else {
                Issue.record("a sync identifier \(description) failed as \(String(describing: error))")
                continue
            }
        }
    }
}

#endif
