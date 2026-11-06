//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
import ModelsR4


/// One source-record revision: its outputs, its one conversion or retraction Provenance, and the shared nodes they
/// reference literally.
///
/// A record is the unit of conversion, of staging and of retry; ``ExchangeBundlePacker`` packs records into the Bundles
/// that travel. Stage ``json`` verbatim and read it back with ``init(validating:)``.
public struct ExchangeRecord: Sendable, Hashable {
    /// Whether a record states a source-record revision or takes a whole source record back.
    public enum Kind: Sendable, Hashable {
        case active
        case retraction

        var graphKind: ExchangeGraph.Kind {
            switch self {
            case .active: .active
            case .retraction: .retraction
            }
        }
    }

    /// One Bundle entry of ``json``: its fullUrl and where its canonical bytes sit.
    struct Entry: Sendable, Hashable {
        let fullURL: String
        let range: Swift.Range<Int>
    }

    public let kind: Kind
    /// The participant the record is about; `nil` only when its bytes state no one pair: a retraction read back from
    /// bytes, whose Provenance and Devices name no subject, or an output subject resolving to a Patient with several.
    public let subject: BusinessIdentifier?
    public let sourceRecord: BusinessIdentifier
    /// The Provenance's entry key; a conversion Provenance repeats it in its `grove-record-version` extension.
    public let version: RecordVersion
    /// The fullUrls of the outputs, in `Provenance.target` order; empty for a retraction.
    public let outputFullURLs: [String]
    /// The fullUrls of the entries that are neither an output nor the Provenance.
    public let sharedNodeFullURLs: Set<String>
    /// The record as a one-record Bundle, in `grove-canonical-json-v0`: no `Bundle.identifier`, and `Bundle.timestamp`
    /// states `Provenance.recorded`, as ``ExchangeBundlePacker`` restates it when the record travels.
    public let json: Data
    /// Every entry of ``json``, in Bundle order.
    let entries: [Entry]

    /// A record of `entries`, each a fullUrl and that entry's canonical bytes.
    init(
        kind: Kind,
        subject: BusinessIdentifier?,
        sourceRecord: BusinessIdentifier,
        version: RecordVersion,
        outputFullURLs: [String],
        entries: [(fullURL: String, json: Data)],
        timestamp: String
    ) {
        let bundle = kind.graphKind.bundleBytes(entries: entries.map(\.json), timestamp: timestamp)
        self.kind = kind
        self.subject = subject
        self.sourceRecord = sourceRecord
        self.version = version
        self.outputFullURLs = outputFullURLs
        self.sharedNodeFullURLs = Set(entries.map(\.fullURL)).subtracting(outputFullURLs + [version.fullURL])
        self.json = bundle.json
        self.entries = zip(entries, bundle.ranges).map { Entry(fullURL: $0.fullURL, range: $1) }
    }

    /// Reads a record back from a one-record Bundle of either kind.
    ///
    /// Every structural rule of ``ExchangeGraph/init(validating:kind:)`` applies. The version is checked for shape only:
    /// it is keyed, so only ``verifyVersion(in:)`` can recompute it. ``json`` holds the canonical form of `json`.
    public init(validating json: Data) throws(ExchangeGraphError) {
        self = try ExchangeGraph.drainingTemporaries { () throws(ExchangeGraphError) in
            let graph = try ExchangeGraph(validating: json, kind: Self.statedKind(of: json))
            let records = try graph.records()
            guard records.count == 1 else {
                throw .invalidEntries("A record states exactly one lifecycle Provenance")
            }
            return records[0]
        }
    }

    /// The kind the Bundle's one exchange profile claims; a claim of neither or of both is left to the graph's own check.
    private static func statedKind(of json: Data) -> ExchangeGraph.Kind {
        let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        let profiles = (object?["meta"] as? [String: Any])?["profile"] as? [String] ?? []
        return profiles.contains(ExchangeGraph.Kind.retraction.profileValue) ? .retraction : .active
    }

    /// Recomputes the record's record-version or record-retraction key, which only a holder of the identity key can.
    ///
    /// - Throws: ``ExchangeGraphError/invalidRecordVersion`` unless the key recomputes under `scope`.
    public func verifyVersion(in scope: OpaqueIdentityScope) throws(ExchangeGraphError) {
        guard (try? recomputedVersion(in: scope)) == version.identifier else {
            throw .invalidRecordVersion
        }
    }

    private func recomputedVersion(in scope: OpaqueIdentityScope) throws -> RoledIdentifier {
        var resources: [String: LosslessJSONValue] = [:]
        for entry in entries {
            if case .object(let members) = try LosslessJSONValue(parsing: json.subdata(in: entry.range)) {
                resources[entry.fullURL] = members["resource"]
            }
        }
        guard let provenance = resources[version.fullURL] else {
            throw ExchangeGraphError.invalidRecordVersion
        }
        return try scope.lifecycleKey(
            kind: kind,
            sourceRecord: sourceRecord,
            provenance: provenance,
            outputs: outputFullURLs.compactMap { resources[$0] }
        )
    }
}


extension OpaqueIdentityScope {
    /// The key a lifecycle Provenance recomputes to: its source record's retraction key, or its record version.
    ///
    /// - Parameters:
    ///   - provenance: The Provenance's lossless tokens.
    ///   - outputs: The lossless tokens of the resources it targets, in target order.
    func lifecycleKey(
        kind: ExchangeRecord.Kind,
        sourceRecord: BusinessIdentifier,
        provenance: LosslessJSONValue,
        outputs: [LosslessJSONValue]
    ) throws(ExchangeIdentityError) -> RoledIdentifier {
        switch kind {
        case .active:
            let digest = try LosslessJSONValue.recordContentDigest(provenance: provenance, outputs: outputs)
            return try recordVersion(sourceRecord: sourceRecord, contentDigest: digest)
        case .retraction:
            return try recordRetraction(sourceRecord: sourceRecord)
        }
    }
}


extension ExchangeGraph.Kind {
    /// The kind's Bundle profile as its canonical text.
    var profileValue: String {
        profile.value?.url.absoluteString ?? ""
    }

    /// A Bundle of `entries`, each its canonical bytes, in `grove-canonical-json-v0`, and where each entry sits in it.
    ///
    /// The member names sort after `entry`, so the entries are spliced as they stand, never re-encoded.
    func bundleBytes(
        entries: [Data],
        timestamp: String,
        transportIdentifier: BusinessIdentifier? = nil
    ) -> (json: Data, ranges: [Swift.Range<Int>]) {
        var header: [String: LosslessJSONValue] = [
            "meta": .object(["profile": .array([.string(profileValue)])]),
            "resourceType": .string(ResourceType.bundle.rawValue),
            "timestamp": .string(timestamp),
            "type": .string("collection")
        ]
        if let transportIdentifier {
            header["identifier"] = .object([
                "system": .string(transportIdentifier.system.rawValue),
                "value": .string(transportIdentifier.value)
            ])
        }
        var json = Data(#"{"entry":["#.utf8)
        var ranges: [Swift.Range<Int>] = []
        ranges.reserveCapacity(entries.count)
        for (index, entry) in entries.enumerated() {
            if index > 0 {
                json.append(UInt8(ascii: ","))
            }
            ranges.append(json.count..<(json.count + entry.count))
            json.append(entry)
        }
        json.append(contentsOf: "],".utf8)
        json.append(LosslessJSONValue.object(header).canonicalBytes().dropFirst())
        return (json, ranges)
    }
}
