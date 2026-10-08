//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The read-back accessors unwrap what a validated graph always carries.
// swiftlint:disable force_unwrapping

#if canImport(HealthKit)

@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import ModelsR4
import Testing


/// Every graph one export call delivered for a record, read back: the record's own first, then its companions (an
/// ECG's symptoms). The accessors beside all read the record's own graph.
struct ExportedRecord {
    let all: [ExportedGraph]

    var primary: ExportedGraph { all[0] }
    var companions: [ExportedGraph] { Array(all.dropFirst()) }
    /// Every graph's warnings, in ``all`` order.
    var warnings: [ProducerDiagnostic] { all.flatMap(\.warnings) }

    var graph: ExchangeGraph { primary.graph }
    var bundle: ModelsR4.Bundle { primary.bundle }
    var identifiers: ExchangeGraphIdentifiers { primary.identifiers }
    var source: HealthKitFHIRExporter.Export.Source { primary.source }
    var sourceIdentifier: Identifier { primary.sourceIdentifier }
    var observation: Observation { primary.observation }
    var document: DocumentReference { primary.document }
    var provenance: Provenance { primary.provenance }
    var converterApplication: Device { primary.converterApplication }
    var converterHost: Device { primary.converterHost }
    var recordingDevice: Device? { primary.recordingDevice }
    var writer: Device? { primary.writer }
    var writerHost: Device? { primary.writerHost }

    /// The graphs of `exports`; the first refusal among them is thrown, and a call that delivered nothing throws too.
    init(_ exports: [HealthKitFHIRExporter.Export]) throws {
        for export in exports {
            if case .refused(let error) = export.outcome {
                throw error
            }
        }
        guard !exports.isEmpty else {
            throw ExportFixtureError.nothingExported
        }
        all = try exports.map(ExportedGraph.init)
    }
}


/// One exported graph, read back the way the tests assert it: each resource by the role it plays, and the identities
/// the graph states for them, found through the Provenance's links rather than reported by the exporter.
struct ExportedGraph {
    let graph: ExchangeGraph
    let source: HealthKitFHIRExporter.Export.Source
    let warnings: [ProducerDiagnostic]
    let identifiers: ExchangeGraphIdentifiers

    var bundle: ModelsR4.Bundle { graph.bundle }
    var sourceIdentifier: Identifier { identifiers.sourceRecord.fhirIdentifier }
    var observation: Observation { graph.resource(Observation.self, at: identifiers.primaryOutput)! }
    var document: DocumentReference { graph.resource(DocumentReference.self, at: identifiers.primaryOutput)! }
    var provenance: Provenance { graph.bundle.entry!.lazy.compactMap { $0.resource?.get(if: Provenance.self) }.first! }
    var converterApplication: Device { graph.resource(Device.self, at: identifiers.applicationSnapshot)! }
    var converterHost: Device { graph.resource(Device.self, at: identifiers.hostSnapshot)! }
    var recordingDevice: Device? { identifiers.recordingDeviceSnapshot.flatMap { graph.resource(Device.self, at: $0) } }
    var writer: Device? { identifiers.writerSnapshot.flatMap { graph.resource(Device.self, at: $0) } }
    var writerHost: Device? { identifiers.writerHostSnapshot.flatMap { graph.resource(Device.self, at: $0) } }

    /// The graph `export` delivered, which must be an active graph.
    init(_ export: HealthKitFHIRExporter.Export) throws {
        guard let graph = export.graph else {
            throw ExportFixtureError.noGraph(export.outcome)
        }
        self.graph = graph
        self.source = export.source
        self.warnings = export.warnings
        self.identifiers = try Self.identifiers(of: graph)
    }

    /// The identities the graph's entries state: the Provenance's targets are the outputs, primary first; its assembler
    /// agent is the converting application, whose parent is the host; the author of its source entity is the writer,
    /// whose own host it names unless the writer is a snapshot the converter already states.
    private static func identifiers(of graph: ExchangeGraph) throws -> ExchangeGraphIdentifiers {
        let entries = graph.bundle.entry ?? []
        func entry(_ reference: Reference?) -> BundleEntry? {
            let url = reference?.reference?.value?.string
            return url.flatMap { url in entries.first { $0.fullUrl?.value?.url.absoluteString == url } }
        }
        func identity(_ entry: BundleEntry?, _ role: GroveIdentifierRole) -> RoledIdentifier? {
            let resource = entry?.resource
            let identifiers = resource?.get(if: Observation.self)?.identifier ?? resource?.get(if: DocumentReference.self)?.identifier
                ?? resource?.get(if: Device.self)?.identifier ?? []
            return identifiers.compactMap { try? RoledIdentifier($0) }.first { $0.role == role }
        }
        let provenanceEntry = entries.first { $0.resource?.get(if: Provenance.self) != nil }
        let provenance = try #require(provenanceEntry?.resource?.get(if: Provenance.self))
        let provenanceKey = provenanceEntry?.extension?.first { $0.url == Canonicals.entryNodeKey }.flatMap { key -> Identifier? in
            guard case .identifier(let identifier)? = key.value else {
                return nil
            }
            return identifier
        }
        let outputs = provenance.target.map(entry)
        let primary = outputs.first.flatMap(\.self)
        let application = entry(provenance.agent.first?.who)
        let author = provenance.entity?.first?.agent?.first { $0.type?.coding?.first?.code?.value?.string == "author" }
        let writer = entry(author?.who)
        let ownWriterHost = writer?.fullUrl != application?.fullUrl && writer?.fullUrl != nil
        let recording = entries.first { identity($0, .recordingDevice) != nil }
        return ExchangeGraphIdentifiers(
            event: graph.eventIdentifier.identifier,
            sourceRecord: try #require(identity(primary, .sourceRecord)),
            primaryOutput: try #require(identity(primary, .sourceOutput)),
            applicationSnapshot: try #require(identity(application, .deviceSnapshot)),
            hostSnapshot: try #require(identity(entry(application?.resource?.get(if: Device.self)?.parent), .deviceSnapshot)),
            provenance: try RoledIdentifier(try #require(provenanceKey)),
            childOutputs: outputs.dropFirst().compactMap { identity($0, .sourceOutput) },
            sourceArtifact: identity(primary, .sourceArtifact),
            recordingDeviceSnapshot: identity(recording, .deviceSnapshot),
            writerSnapshot: identity(writer, .deviceSnapshot),
            writerHostSnapshot: ownWriterHost ? identity(entry(writer?.resource?.get(if: Device.self)?.parent), .deviceSnapshot) : nil
        )
    }
}

#endif
