//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4


extension ExchangeGraph {
    /// The literal references of one Bundle, from which every record unit follows (`bundle.recordUnit`): a lifecycle
    /// Provenance, its targets, and the directed literal closure from them. A ResearchSubject joins every unit whose
    /// closure contains the study it references, so a shared node may lie in several units.
    struct RecordUnits {
        /// The fullUrls each entry references literally that are entries of the Bundle.
        private let references: [String: Set<String>]
        /// Each ResearchSubject's fullUrl and the fullUrl of the study it references.
        private let studiesByResearchSubject: [String: String]

        /// The units of a Bundle under validation.
        init(entries: [BundleEntry], document: ValidationDocument) throws {
            let fullURLs = entries.map { $0.fullUrl?.value?.url.absoluteString ?? "" }
            var literals: [String: Set<String>] = [:]
            for (index, fullURL) in fullURLs.enumerated() {
                literals[fullURL] = Set(try document.resourceObjects(at: index).compactMap { $0["reference"] as? String })
            }
            self.init(literals: literals, studiesByResearchSubject: Self.studies(in: entries))
        }

        /// The units of a validated Bundle, whose entry at each index states `tokens[index]`.
        init(entries: [BundleEntry], tokens: [LosslessJSONValue]) {
            let fullURLs = entries.map { $0.fullUrl?.value?.url.absoluteString ?? "" }
            var literals: [String: Set<String>] = [:]
            for (fullURL, token) in zip(fullURLs, tokens) {
                var references: Set<String> = []
                token.resource?.collectLiteralReferences(into: &references)
                literals[fullURL] = references
            }
            self.init(literals: literals, studiesByResearchSubject: Self.studies(in: entries))
        }

        private init(literals: [String: Set<String>], studiesByResearchSubject: [String: String]) {
            let fullURLs = Set(literals.keys)
            self.references = literals.mapValues { $0.intersection(fullURLs) }
            self.studiesByResearchSubject = studiesByResearchSubject
        }

        private static func studies(in entries: [BundleEntry]) -> [String: String] {
            var studies: [String: String] = [:]
            for entry in entries {
                if case .researchSubject(let researchSubject)? = entry.resource,
                   let fullURL = entry.fullUrl?.value?.url.absoluteString,
                   let study = researchSubject.study.reference?.value?.string {
                    studies[fullURL] = study
                }
            }
            return studies
        }

        /// The unit reached from `starts`, a record's Provenance and its targets.
        func unit(from starts: some Sequence<String>) -> Set<String> {
            var unit: Set<String> = []
            var pending = starts.filter { references[$0] != nil }
            while true {
                while let current = pending.popLast() {
                    guard unit.insert(current).inserted else {
                        continue
                    }
                    pending += references[current, default: []].filter { !unit.contains($0) }
                }
                pending = studiesByResearchSubject.filter { !unit.contains($0.key) && unit.contains($0.value) }.map(\.key)
                if pending.isEmpty {
                    return unit
                }
            }
        }
    }

    private static func key(of entry: BundleEntry) throws -> RoledIdentifier {
        guard case .identifier(let identifier)? = entry.extension?.first(where: { $0.url == Canonicals.entryKey })?.value else {
            throw ExchangeGraphError.ruleViolation(.mobileExchangeEntryKey)
        }
        return try RoledIdentifier(identifier)
    }

    /// The `node-role` component of a shared node's content snapshot, or `nil` when its key is no content snapshot.
    private static func nodeRole(of entry: BundleEntry, key: RoledIdentifier) -> OpaqueIdentityScope.NodeRole? {
        guard let resource = entry.resource, key.role == .deviceSnapshot || key.role == .contextSnapshot else {
            return nil
        }
        guard case .device(let device) = resource else {
            return ContextSnapshotRole(resourceType: resource.resourceType).map(OpaqueIdentityScope.NodeRole.context)
        }
        let profiles = device.meta?.profile ?? []
        if profiles.contains(Profile.groveRecordingDevice) {
            return .recordingDevice
        }
        return profiles.contains(Profile.groveHostDevice) ? .host : .application
    }

    /// The Bundle's records, in entry order: each lifecycle Provenance with its outputs and the shared nodes it reaches,
    /// as ``ExchangeRecord/json`` states them. No record is altered: each keeps its record version in any Bundle.
    ///
    /// - Throws: ``ExchangeGraphError/invalidEntries(_:)`` when a record's unit reaches a second lifecycle Provenance,
    ///   which validation already refuses as `mobile-exchange.cross-record-reference`.
    public func records() throws(ExchangeGraphError) -> [ExchangeRecord] {
        try records(subject: nil)
    }

    /// ``records()``, every record stating `subject` when the caller knows it, as the converter of a retraction does: no
    /// element of a retraction states it.
    func records(subject stated: BusinessIdentifier?) throws(ExchangeGraphError) -> [ExchangeRecord] {
        let entries = bundle.entry ?? []
        let tokens = try entryTokens(count: entries.count)
        let units = RecordUnits(entries: entries, tokens: tokens)
        let canonicalEntries = tokens.map { $0.canonicalBytes() }
        var indexes: [String: Int] = [:]
        for (index, entry) in entries.enumerated() {
            indexes[entry.fullUrl?.value?.url.absoluteString ?? ""] = index
        }
        let subject = stated ?? Self.bundleSubject(in: entries)
        let provenanceFullURLs = Set(entries.compactMap { entry -> String? in
            guard case .provenance? = entry.resource else {
                return nil
            }
            return entry.fullUrl?.value?.url.absoluteString ?? ""
        })
        var records: [ExchangeRecord] = []
        for (index, entry) in entries.enumerated() {
            guard case .provenance(let provenance)? = entry.resource else {
                continue
            }
            let outputs = kind == .active ? provenance.target.compactMap { $0.reference?.value?.string } : []
            let fullURL = entry.fullUrl?.value?.url.absoluteString ?? ""
            let unit = units.unit(from: [fullURL] + outputs)
            guard unit.intersection(provenanceFullURLs) == [fullURL] else {
                throw .invalidEntries("A record states exactly one lifecycle Provenance")
            }
            do {
                records.append(try ExchangeRecord(
                    kind: kind == .active ? .active : .retraction,
                    subject: subject,
                    sourceRecord: try Self.exactSourceEntity(in: provenance).identifier,
                    version: RecordVersion(Self.key(of: entry)),
                    outputFullURLs: outputs,
                    entries: unit.compactMap { indexes[$0] }.sorted().map { memberIndex in
                        (fullURL: entries[memberIndex].fullUrl?.value?.url.absoluteString ?? "", json: canonicalEntries[memberIndex])
                    },
                    timestamp: tokens[index].resource?.recorded ?? ""
                ))
            } catch let error as ExchangeGraphError {
                throw error
            } catch {
                throw .invalidEntries(String(reflecting: type(of: error)))
            }
        }
        return records
    }

    /// The lossless token of each of `count` entries.
    private func entryTokens(count: Int) throws(ExchangeGraphError) -> [LosslessJSONValue] {
        guard case .object(let root)? = try? LosslessJSONValue(parsing: json),
              case .array(let tokens)? = root["entry"],
              tokens.count == count else {
            throw .invalidEntries("A Bundle's tokens do not line up with its entries")
        }
        return tokens
    }

    /// Recomputes every key derived from content under `scope`'s key: each shared node's content snapshot, for which the
    /// Bundle must state one subject pair, and each lifecycle Provenance's key.
    ///
    /// An active graph that states no one subject has a content snapshot it cannot recompute, and is refused. A
    /// retraction states no subject at all, so its Device snapshots are checked for shape only.
    ///
    /// The validating initializers check these keys for shape only, because a receiver never holds a deployment's key.
    /// Only a holder of the identity key can run this, as the conformance kit does under the published test key. A key
    /// under another key id or epoch is left alone.
    package func validateDerivedKeys(in scope: OpaqueIdentityScope) throws(ExchangeGraphError) {
        let entries = bundle.entry ?? []
        let tokens = try entryTokens(count: entries.count)
        let subject = Self.bundleSubject(in: entries)
        var resources: [String: LosslessJSONValue] = [:]
        for (entry, token) in zip(entries, tokens) {
            resources[entry.fullUrl?.value?.url.absoluteString ?? ""] = token.resource
        }
        for (index, entry) in entries.enumerated() {
            guard let key = try? Self.key(of: entry),
                  key.identifier.value.hasPrefix("v0:\(scope.keyID):\(scope.epoch.rawValue):"),
                  let resource = tokens[index].resource else {
                continue
            }
            let location = "\(Self.entryKeyLocation(index)).value"
            if case .provenance(let provenance)? = entry.resource {
                let rule: ExchangeGraphRule = kind == .active ? .mobileExchangeRecordVersionKey : .mobileRetractionRetractionKey
                let targets = kind == .active ? provenance.target.compactMap { $0.reference?.value?.string } : []
                let expected = try? scope.lifecycleKey(
                    kind: kind == .active ? .active : .retraction,
                    sourceRecord: Self.exactSourceEntity(in: provenance).identifier,
                    provenance: resource,
                    outputs: targets.compactMap { resources[$0] }
                )
                guard expected == key else {
                    throw Self.diagnostic(rule, location: location)
                }
            } else if let role = Self.nodeRole(of: entry, key: key) {
                guard let subject else {
                    if kind == .active {
                        throw Self.diagnostic(.mobileExchangeContentSnapshotKey, location: location)
                    }
                    continue
                }
                let digest = try? resource.contentDigest
                guard let digest, (try? scope.contentSnapshot(subject: subject, role: role, contentDigest: digest)) == key else {
                    throw Self.diagnostic(.mobileExchangeContentSnapshotKey, location: location)
                }
            }
        }
    }
}


extension LosslessJSONValue {
    /// The `resource` member of a Bundle entry.
    fileprivate var resource: LosslessJSONValue? {
        guard case .object(let members) = self else {
            return nil
        }
        return members["resource"]
    }

    /// The `recorded` member of a Provenance.
    fileprivate var recorded: String? {
        guard case .object(let members) = self, case .string(let recorded)? = members["recorded"] else {
            return nil
        }
        return recorded
    }

    /// Adds every string stated as a `reference` member, anywhere in this value, to `references`.
    fileprivate func collectLiteralReferences(into references: inout Set<String>) {
        switch self {
        case .object(let members):
            if case .string(let reference)? = members["reference"] {
                references.insert(reference)
            }
            for member in members.values {
                member.collectLiteralReferences(into: &references)
            }
        case .array(let elements):
            for element in elements {
                element.collectLiteralReferences(into: &references)
            }
        case .string, .number, .boolean, .null:
            break
        }
    }
}
