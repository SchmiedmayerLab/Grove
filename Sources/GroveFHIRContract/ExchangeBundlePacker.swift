//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Packs records of one kind and one subject into one exchange Bundle, stating each shared node once.
///
/// Shared nodes are content-addressed, so two records that reference the same fullUrl share its one entry. The packer
/// splices canonical entry tokens and never re-encodes a FHIR model, so packing changes no record.
public struct ExchangeBundlePacker: Sendable {
    /// Why a record cannot join this packer.
    public enum Failure: Error, Sendable, Equatable {
        /// The record is not of the packer's kind.
        case mixedKinds
        /// The record states another subject than the records already packed. A fresh packer would only hide it.
        case mixedSubjects
        /// The record states other tokens than a packed one under the same fullUrl, and the packer fails closed. A key
        /// is a digest of its content, so this is an integrity failure, such as a canonicalization change.
        case conflictingNode(fullURL: String)
    }

    /// What happened to a record the packer did not refuse.
    public enum Admission: Sendable, Equatable {
        /// The record's entries were added.
        case added
        /// The packer already holds this version and every entry the record states, or this retraction key, and keeps
        /// what it holds: the first accepted retraction of a source record wins.
        case duplicate
        /// The record belongs in the next Bundle: a second version of a source record already packed, whose outputs share
        /// their fullUrls with the first; the same version stating an entry this Bundle doesn't hold, such as a changed
        /// ResearchSubject, which stays outside the record version; or a record that would take this non-empty packer past
        /// a cap.
        case deferred
    }

    private let kind: ExchangeRecord.Kind
    private let maximumRecords: Int
    private let maximumBytes: Int
    private var subject: BusinessIdentifier?
    private var versions: [BusinessIdentifier: RecordVersion] = [:]
    private var nodes: [String: Data] = [:]
    /// The canonical bytes of every entry, in the order the Bundle states them.
    private var entries: [Data] = []

    /// Whether the Bundle has reached a cap: no further record can join without being deferred.
    public var isFull: Bool {
        recordCount == maximumRecords || byteCount >= maximumBytes
    }

    public private(set) var recordCount = 0
    /// The canonical bytes of the entries packed so far; the Bundle adds its short header to them.
    public private(set) var byteCount = 0

    /// - Parameters:
    ///   - kind: The kind of every record of the Bundle: active and retraction records never mix.
    ///   - maximumRecords: The most records one Bundle holds.
    ///   - maximumBytes: The most bytes of uncompressed entries one Bundle holds.
    public init(kind: ExchangeRecord.Kind, maximumRecords: Int = 2_000, maximumBytes: Int = 16 << 20) {
        self.kind = kind
        self.maximumRecords = maximumRecords
        self.maximumBytes = maximumBytes
    }

    /// Adds `record` to the Bundle, or reports why it does not join this one.
    ///
    /// `mixedSubjects` and `conflictingNode` compare `record` with the records already packed, and `mixedKinds` with the
    /// packer's kind, so an empty packer of the record's kind admits any one valid record, even one over `maximumBytes`:
    /// a caller that starts such a fresh packer on `conflictingNode` or `mixedKinds` never stalls. `mixedSubjects` reports
    /// a record of another subject, which a fresh packer would only hide. A record that states no subject, as a retraction
    /// read back from bytes, is compared with no one, so a caller that needs that check holds the subject itself.
    ///
    /// A record that would take a non-empty packer past `maximumRecords` or `maximumBytes` is `.deferred`, for the caller to
    /// put into the next Bundle. So is a version the packer holds when the record states an entry the packer doesn't, so
    /// that entry reaches the receiver too; only an active version that adds nothing is `.duplicate`, and a held
    /// retraction key always is.
    public mutating func add(_ record: ExchangeRecord) throws(Failure) -> Admission {
        guard record.kind == kind else {
            throw .mixedKinds
        }
        if let subject, let recordSubject = record.subject, subject != recordSubject {
            throw .mixedSubjects
        }
        if let packed = versions[record.sourceRecord] {
            if kind == .retraction {
                return .duplicate
            }
            guard packed == record.version else {
                return .deferred
            }
        }
        let added = try unpackedEntries(of: record)
        if versions[record.sourceRecord] != nil {
            return added.isEmpty ? .duplicate : .deferred
        }
        let addedBytes = added.reduce(0) { $0 + $1.json.count }
        guard recordCount == 0 || (recordCount < maximumRecords && byteCount + addedBytes <= maximumBytes) else {
            return .deferred
        }
        subject = subject ?? record.subject
        versions[record.sourceRecord] = record.version
        for entry in added {
            nodes[entry.fullURL] = entry.json
            entries.append(entry.json)
        }
        recordCount += 1
        byteCount += addedBytes
        return .added
    }

    /// The entries of `record` the packer does not hold yet, once every entry it holds states the same tokens.
    private func unpackedEntries(of record: ExchangeRecord) throws(Failure) -> [(fullURL: String, json: Data)] {
        var unpacked: [(fullURL: String, json: Data)] = []
        for entry in record.entries {
            let json = record.json.subdata(in: entry.range)
            guard let packed = nodes[entry.fullURL] else {
                unpacked.append((entry.fullURL, json))
                continue
            }
            guard packed == json else {
                throw .conflictingNode(fullURL: entry.fullURL)
            }
        }
        return unpacked
    }

    /// The Bundle of every packed record, validated as ``ExchangeGraph/init(validating:kind:)`` validates stored bytes.
    ///
    /// - Parameters:
    ///   - packedAt: `Bundle.timestamp`, which enters no identity.
    ///   - transportIdentifier: `Bundle.identifier`, which names no record and enters no identity.
    public consuming func bundle(
        packedAt: Date,
        transportIdentifier: BusinessIdentifier? = nil
    ) throws(ExchangeGraphError) -> ExchangeGraph {
        guard (try? ExchangeInstant.fhirInstant(packedAt)) != nil else {
            throw .invalidEntries("A Bundle's packing instant has no FHIR instant")
        }
        let bundle = kind.graphKind.bundleBytes(
            entries: entries,
            timestamp: ExchangeInstant.utcLexeme(packedAt),
            transportIdentifier: transportIdentifier
        )
        return try ExchangeGraph(validating: bundle.json, kind: kind.graphKind)
    }
}
