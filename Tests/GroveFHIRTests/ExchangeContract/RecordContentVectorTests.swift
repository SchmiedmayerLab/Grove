//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
import Testing


/// The content digests and the keys they derive, against the shared vectors and the corpora keyed by the published key.
@Suite(.enabled(if: groveFHIRIsAvailable, "Requires the grove-fhir checkout used by FHIR Output Conformance"))
struct RecordContentVectorTests {
    private struct BundleManifest: Decodable {
        struct Bundle: Decodable {
            let path: String
        }

        let bundles: [String: Bundle]
    }

    private static let subject = BusinessIdentifier(
        system: "https://study.example.org/fhir/identifiers/participant",
        nonemptyValue: "participant-001"
    )

    private static var receiverLifecycleCorpus: URL {
        groveFHIRRoot.appendingPathComponent(ExchangeContract.equalityVectorCorpus, isDirectory: true)
    }

    private static func parse(_ text: String) throws -> LosslessJSONValue {
        try LosslessJSONValue(parsing: Data(text.utf8))
    }

    private static func provenanceEntry(in bundle: LosslessJSONValue) throws -> LosslessJSONValue {
        let entries = try #require(bundle.object?["entry"]?.array)
        return try #require(entries.first { $0.resource?.resourceType == "Provenance" })
    }

    private static func expectKeysRecompute(in data: Data, scope: OpaqueIdentityScope, label: String) throws {
        let bundle = try LosslessJSONValue(parsing: data)
        let entries = try #require(bundle.object?["entry"]?.array, "\(label)")
        let profiles = bundle.object?["meta"]?.object?["profile"]?.array ?? []
        let isRetraction = profiles.contains { $0.string?.hasSuffix("grove-mobile-retraction-bundle") == true }
        for (index, entry) in entries.enumerated() {
            let stated = try #require(entry.entryKey, "\(label) entry \(index)")
            let expected = try expectedKey(of: entry, in: entries, scope: scope, isRetraction: isRetraction)
            #expect(stated == expected, "\(label) entry \(index)")
            #expect(try entry.object?["fullUrl"]?.string == stated.fullURLString, "\(label) entry \(index)")
        }
    }

    /// What the entry's key recomputes to; an output's key is its typed identifier, which no digest derives.
    private static func expectedKey(
        of entry: LosslessJSONValue,
        in entries: [LosslessJSONValue],
        scope: OpaqueIdentityScope,
        isRetraction: Bool
    ) throws -> BusinessIdentifier {
        let resource = try #require(entry.resource)
        func snapshot(_ role: OpaqueIdentityScope.NodeRole) throws -> BusinessIdentifier {
            try scope.contentSnapshot(subject: subject, role: role, contentDigest: resource.contentDigest).identifier
        }
        switch try #require(resource.resourceType) {
        case "Device":
            let profiles = (resource.object?["meta"]?.object?["profile"]?.array ?? []).compactMap(\.string)
            if profiles.contains(where: { $0.hasSuffix("-application-device") }) {
                return try snapshot(.application)
            }
            return try snapshot(profiles.contains { $0.hasSuffix("/grove-host-device") } ? .host : .recordingDevice)
        case "Patient":
            return try snapshot(.context(.patient))
        case "ResearchStudy":
            return try snapshot(.context(.researchStudy))
        case "ResearchSubject":
            return try snapshot(.context(.researchSubject))
        case "PlanDefinition":
            return try snapshot(.context(.planDefinition))
        case "QuestionnaireResponse":
            return try snapshot(.context(.questionnaireResponse))
        case "Provenance":
            return try provenanceKey(resource, in: entries, scope: scope, isRetraction: isRetraction)
        default:
            return try #require(entry.entryKey)
        }
    }

    private static func provenanceKey(
        _ provenance: LosslessJSONValue,
        in entries: [LosslessJSONValue],
        scope: OpaqueIdentityScope,
        isRetraction: Bool
    ) throws -> BusinessIdentifier {
        let sourceRecord = try #require(provenance.sourceRecord)
        guard !isRetraction else {
            return try scope.recordRetraction(sourceRecord: sourceRecord).identifier
        }
        let targets = (provenance.object?["target"]?.array ?? []).compactMap { $0.object?["reference"]?.string }
        let outputs = try targets.map { target in
            try #require(entries.first { $0.object?["fullUrl"]?.string == target }?.resource)
        }
        let digest = try LosslessJSONValue.recordContentDigest(provenance: provenance, outputs: outputs)
        return try scope.recordVersion(sourceRecord: sourceRecord, contentDigest: digest).identifier
    }

    @Test("Every record content vector is reproduced")
    func recordContentVectors() throws {
        for vector in try ExchangeProtocolCatalog.current.testVectors.recordContents {
            let digest = try LosslessJSONValue.recordContentDigest(
                provenance: Self.parse(vector.provenance),
                outputs: vector.outputs.map(Self.parse)
            )
            #expect(digest == vector.recordContentDigest, "\(vector.id)")
        }
    }

    @Test("A record's digest sees its content and not the record's own id or key")
    func recordContentExclusions() throws {
        let vectors = try ExchangeProtocolCatalog.current.testVectors
        let vector = try #require(vectors.recordContents.first { $0.id == "heart-rate-72" })
        let provenance = try Self.parse(vector.provenance)
        let outputs = try vector.outputs.map(Self.parse)
        func digest(_ provenance: LosslessJSONValue, _ outputs: [LosslessJSONValue]) throws -> String {
            try LosslessJSONValue.recordContentDigest(provenance: provenance, outputs: outputs)
        }

        // Reformatted bytes state the same tokens, so they give the same version.
        let reformatted = try JSONSerialization.data(
            withJSONObject: JSONSerialization.jsonObject(with: Data(vector.provenance.utf8)),
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        #expect(try digest(LosslessJSONValue(parsing: reformatted), outputs) == vector.recordContentDigest)

        let stripped = try #require(provenance.object).filter { $0.key != "id" && $0.key != "extension" }
        #expect(try digest(.object(stripped), outputs) == vector.recordContentDigest)
        var otherID = stripped
        otherID["id"] = .string("another-id")
        #expect(try digest(.object(otherID), outputs) == vector.recordContentDigest)
        let outputsWithID = try outputs.map { output in
            var members = try #require(output.object)
            members["id"] = .string("another-id")
            return LosslessJSONValue.object(members)
        }
        #expect(try digest(provenance, outputsWithID) == vector.recordContentDigest)

        // Any other extension stays in the digest.
        var otherExtension = stripped
        otherExtension["extension"] = .array([.object(["url": .string("https://example.org/other")])])
        #expect(try digest(.object(otherExtension), outputs) != vector.recordContentDigest)
    }

    @Test("Two lexemes are two versions of one source record, with one retraction key")
    func lexemesAreVersions() throws {
        let vectors = try ExchangeProtocolCatalog.current.testVectors
        let scope = try vectors.scope
        let integer = try #require(vectors.recordContents.first { $0.id == "heart-rate-72" })
        let decimal = try #require(vectors.recordContents.first { $0.id == "heart-rate-72-0" })
        let sourceRecord = try #require(Self.parse(integer.provenance).sourceRecord)
        #expect(try Self.parse(decimal.provenance).sourceRecord == sourceRecord)
        #expect(integer.recordContentDigest != decimal.recordContentDigest)
        #expect(try scope.recordVersion(sourceRecord: sourceRecord, contentDigest: integer.recordContentDigest)
            != scope.recordVersion(sourceRecord: sourceRecord, contentDigest: decimal.recordContentDigest))
        #expect(try scope.recordRetraction(sourceRecord: sourceRecord).role == .recordRetraction)
    }

    @Test("A digest refuses what is not a record or a shared node")
    func digestRefusals() throws {
        let vectors = try ExchangeProtocolCatalog.current.testVectors
        let vector = try #require(vectors.recordContents.first)
        let provenance = try Self.parse(vector.provenance)
        let output = try Self.parse(try #require(vector.outputs.first))
        #expect(throws: ExchangeIdentityError.invalidDigestContent("The record content starts with a Provenance")) {
            try LosslessJSONValue.recordContentDigest(provenance: output, outputs: [output])
        }
        #expect(throws: ExchangeIdentityError.invalidDigestContent("A record states exactly one output per Provenance.target")) {
            try LosslessJSONValue.recordContentDigest(provenance: provenance, outputs: [])
        }
        #expect(throws: ExchangeIdentityError.invalidDigestContent("Observation carries no content-snapshot key")) {
            try output.contentDigest
        }
    }

    @Test("A record version keeps its key and fullUrl, and refuses anything else")
    func recordVersions() throws {
        let vectors = try ExchangeProtocolCatalog.current.testVectors
        for vector in vectors.fullUrls where vector.id.hasPrefix("record-") {
            let role: GroveIdentifierRole = vector.id.hasPrefix("record-version") ? .recordVersion : .recordRetraction
            let identifier = try BusinessIdentifier(system: IdentifierSystem(vector.system), value: vector.value)
            let version = try RecordVersion(RoledIdentifier(identifier: identifier, role: role))
            #expect(version.fullURL == vector.fullUrl, "\(vector.id)")
            #expect(version.identifier.identifier == identifier, "\(vector.id)")
        }
        let scope = try vectors.scope
        #expect(throws: ExchangeIdentityError.invalidIdentifierRole("context-snapshot")) {
            try RecordVersion(RoledIdentifier(identifier: Self.subject, role: .contextSnapshot))
        }
        #expect(throws: ExchangeIdentityError.invalidRecordVersion("participant-001")) {
            let identifier = try BusinessIdentifier(system: scope.systems.recordVersion, value: "participant-001")
            return try RecordVersion(RoledIdentifier(identifier: identifier, role: .recordVersion))
        }
    }

    @Test("Every entry key of the Mobile corpus recomputes under the published key")
    func mobileCorpusKeys() throws {
        let scope = try ExchangeProtocolCatalog.current.testVectors.scope
        for name in ["exchange-bundle", "retraction-bundle", "source-record-target-retraction-bundle"] {
            let url = groveFHIRRoot.appendingPathComponent("Conformance/corpora/mobile-exchange/\(name).json")
            try Self.expectKeysRecompute(in: Data(contentsOf: url), scope: scope, label: name)
        }
    }

    @Test("Every entry key of the receiver-lifecycle corpus recomputes, except the altered retry's")
    func receiverLifecycleKeys() throws {
        let scope = try ExchangeProtocolCatalog.current.testVectors.scope
        let corpus = Self.receiverLifecycleCorpus
        let manifest = try JSONDecoder().decode(BundleManifest.self, from: Data(contentsOf: corpus.appendingPathComponent("bundles.json")))
        #expect(!manifest.bundles.isEmpty)
        for (name, bundle) in manifest.bundles where name != ExchangeContract.equalityAlteredRetryVector {
            try Self.expectKeysRecompute(in: Data(contentsOf: corpus.appendingPathComponent(bundle.path)), scope: scope, label: name)
        }
    }

    @Test("Formatting changes no key, a lexeme is a new version, and an altered retry repeats a key it does not earn")
    func retryVectors() throws {
        let scope = try ExchangeProtocolCatalog.current.testVectors.scope
        func document(_ name: String) throws -> LosslessJSONValue {
            try LosslessJSONValue(parsing: Data(contentsOf: Self.receiverLifecycleCorpus.appendingPathComponent("resources/\(name).json")))
        }
        func statedKey(_ bundle: LosslessJSONValue) throws -> BusinessIdentifier {
            try #require(Self.provenanceEntry(in: bundle).entryKey)
        }
        let original = try document("original")
        let reformatted = try document(ExchangeContract.equalityFormattingVector)
        let lexeme = try document(ExchangeContract.equalityDecimalLexemeVector)
        let altered = try document(ExchangeContract.equalityAlteredRetryVector)

        #expect(original == reformatted)
        #expect(original.canonicalBytes() == reformatted.canonicalBytes())
        #expect(try statedKey(original) == statedKey(reformatted))
        #expect(original != lexeme)
        #expect(try statedKey(original) != statedKey(lexeme))
        #expect(try statedKey(original) == statedKey(altered))
        let entries = try #require(altered.object?["entry"]?.array)
        let recomputed = try Self.expectedKey(of: Self.provenanceEntry(in: altered), in: entries, scope: scope, isRetraction: false)
        #expect(try recomputed != statedKey(altered))
    }
}
