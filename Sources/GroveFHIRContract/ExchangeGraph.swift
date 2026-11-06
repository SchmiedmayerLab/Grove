//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import ModelsR4


/// One validated exchange Bundle: one or more records of one kind and one subject, with their shared nodes.
///
/// Entries are owned only by the Bundle. Producers may expose stable entry keys, but do not retain
/// independent mutable resource copies that can drift from what is serialized and uploaded.
/// The graph keeps the JSON it was validated from, so lossless tokens stay available rather than a
/// model that has already normalized decimal lexemes, and so a consumer uploads exactly what was
/// validated: ``json``. The Bundle is a container: ``ExchangeBundlePacker`` packs ``ExchangeRecord``s into one, and
/// packing or repacking them changes no record.
public struct ExchangeGraph: Sendable {
    /// The semantic kind of a complete Grove exchange graph.
    public enum Kind: Hashable, Sendable {
        case active
        case retraction

        var profile: FHIRPrimitive<Canonical> {
            switch self {
            case .active:
                Profile.groveMobileExchangeBundle
            case .retraction:
                Profile.groveMobileRetractionBundle
            }
        }
    }

    /// Sorted members and unescaped slashes: the same tokens the default encoder emits, in one
    /// member order in every process, so a retry reproduces the bytes and a stored graph diffs by content.
    static var wireEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public let kind: Kind
    /// `Bundle.identifier`, an optional transport id: it names no record and enters no identity, and one that is no
    /// complete pair is carried without being read here.
    public let transportIdentifier: BusinessIdentifier?
    public let bundle: ModelsR4.Bundle
    /// The serialized graph exactly as it was validated.
    ///
    /// A graph built from a model holds that model's canonical encoding (sorted members, slashes
    /// unescaped); a graph re-validated from stored bytes holds those bytes unchanged. Upload and
    /// persist these bytes, not a re-encoding of ``bundle``.
    public let json: Data

    /// Validates a graph an adapter assembled, keeping its canonical encoding as ``json``.
    package init(kind: Kind, bundle: ModelsR4.Bundle) throws(ExchangeGraphError) {
        self.json = try Self.drainingTemporaries { () throws(ExchangeGraphError) in
            let encoded: (json: Data, tree: Any?)
            do {
                encoded = try Self.wireEncoding(of: bundle)
            } catch {
                throw .invalidEntries(String(reflecting: type(of: error)))
            }
            try Self.validate(
                kind: kind,
                bundle: bundle,
                document: encoded.tree.map { ValidationDocument(bundle: bundle, tree: $0) }
                    ?? ValidationDocument(bundle: bundle, jsonData: encoded.json)
            )
            return encoded.json
        }
        self.kind = kind
        self.transportIdentifier = bundle.identifier.flatMap { try? BusinessIdentifier($0) }
        self.bundle = bundle
    }

    /// Re-validates stored or received JSON before it is trusted again, and keeps exactly those bytes as ``json``.
    ///
    /// It applies every structural rule a built graph passes, including that each adapter output has exactly one conversion
    /// Provenance of its adapter; StructureDefinition and terminology conformance is the conformance lane's to prove. A
    /// content-derived key is checked for shape only, as only a holder of the identity key can recompute it.
    /// Bytes stating anything the FHIR model does not keep, a member it drops or a value it rewrites, are refused: the
    /// rules decide over what the model holds, and ``json`` is what travels, so such content would travel unchecked.
    /// A decimal may differ in lexeme only, as `72.0` and `72` state one value.
    ///
    /// Serialized checks run first, because Foundation keeps only one of duplicate members and
    /// decoding through `Foundation.URL` could normalize an identity system or collapse a
    /// prohibited resource type before the model sees it.
    public init(
        validating json: Data,
        kind: Kind
    ) throws(ExchangeGraphError) {
        self.bundle = try Self.drainingTemporaries { () throws(ExchangeGraphError) in
            try Self.decodeValidated(kind: kind, jsonData: json)
        }
        self.kind = kind
        self.transportIdentifier = bundle.identifier.flatMap { try? BusinessIdentifier($0) }
        self.json = json
    }

    /// The canonical encoding of `value`: ``WireJSONEncoder``'s bytes, which are `wireEncoder`'s, written directly, and
    /// the JSON they state, or `nil` when `wireEncoder` wrote them.
    static func wireEncoding(of value: some Encodable) throws -> (json: Data, tree: Any?) {
        guard let (json, tree) = try WireJSONEncoder.encodeKeepingTree(value) else {
            return (try wireEncoder.encode(value), nil)
        }
        return (json, tree)
    }

    private static func decodeValidated(kind: Kind, jsonData: Data) throws(ExchangeGraphError) -> ModelsR4.Bundle {
        do {
            var scanner = StrictJSONScanner(jsonData)
            try scanner.validate()
        } catch {
            throw .invalidEntries("Serialized Bundle is not strict JSON")
        }
        let serialized = Result<Any, any Error> { try JSONSerialization.jsonObject(with: jsonData) }
        try Self.validateSerializedEntryPolicy(kind: kind, json: serialized)
        do {
            try ExchangeIdentity.validateSerializedIdentifierSystems(inJSON: serialized.get())
        } catch {
            throw .ruleViolation(.mobileExchangeOpaqueResourceIdentity)
        }
        let decodedBundle: ModelsR4.Bundle
        do {
            decodedBundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: jsonData)
        } catch {
            throw .invalidEntries(String(reflecting: type(of: error)))
        }
        // The model checks read the decoded model's own encoding, not the stored bytes, and decide over what the
        // graph will hold; the bytes then must carry nothing more.
        try Self.validate(kind: kind, bundle: decodedBundle, document: ValidationDocument(bundle: decodedBundle, jsonData: nil))
        try Self.validateKeptContent(of: jsonData, serialized: serialized, decoded: decodedBundle)
        return decodedBundle
    }

    /// Whether the bytes state exactly what the decoded model encodes: the same members, elements and scalars. A number
    /// may differ in lexeme only, as the model rewrites a decimal such as `72.0`; a value the model rewrote, such as a
    /// canonical whose empty version it dropped or a decimal it rounded, is refused, as the rules decided over the
    /// rewritten value. Bytes with no `grove-canonical-json-v0` reading are refused at the first resource that has none.
    private static func validateKeptContent(
        of jsonData: Data,
        serialized: Result<Any, any Error>,
        decoded bundle: ModelsR4.Bundle
    ) throws(ExchangeGraphError) {
        guard let given = try? LosslessJSONValue(parsing: jsonData) else {
            throw diagnostic(.mobileExchangeCanonicalJson, location: firstNonCanonicalResource(in: serialized) ?? "Bundle")
        }
        guard let kept = try? LosslessJSONValue(parsing: wireEncoder.encode(bundle)), given.isKept(as: kept) else {
            throw .invalidEntries("Serialized Bundle carries content the model does not keep")
        }
    }

    /// Where the first entry resource without a canonical reading sits, or `nil` when every one has one.
    private static func firstNonCanonicalResource(in serialized: Result<Any, any Error>) -> String? {
        let root = (try? serialized.get()) as? [String: Any]
        let entries = root?["entry"] as? [[String: Any]] ?? []
        for (index, entry) in entries.enumerated() {
            if let resource = entry["resource"],
               let bytes = try? JSONSerialization.data(withJSONObject: resource),
               (try? LosslessJSONValue(parsing: bytes)) == nil {
                return "Bundle.entry[\(index)].resource"
            }
        }
        return nil
    }

    /// Runs `body` in its own autorelease pool where there is one, so the Foundation temporaries of
    /// encoding, parsing and validating one graph are released with that graph rather than with the
    /// caller's pool, which a batch conversion may not drain until thousands of graphs later.
    static func drainingTemporaries<T>(
        _ body: () throws(ExchangeGraphError) -> T
    ) throws(ExchangeGraphError) -> T {
        #if canImport(ObjectiveC)
        // `autoreleasepool` rethrows untyped errors, so the typed error crosses it inside a Result.
        let result = autoreleasepool {
            Result<T, ExchangeGraphError> { () throws(ExchangeGraphError) in try body() }
        }
        return try result.get()
        #else
        return try body()
        #endif
    }

    private static func validate(
        kind: Kind,
        bundle: ModelsR4.Bundle,
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        try validateHeader(bundle)
        let entries = try validatedEntries(bundle, kind: kind)
        try validateEntryResourcePolicy(kind: kind, entries: entries, document: document)
        try validateEntryIdentities(kind: kind, entries: entries, document: document)
        try validateGovernedReferenceTargets(entries: entries, document: document)
        try validateLifecycle(kind: kind, entries: entries, document: document)
    }

    /// `Bundle.identifier` is an untyped transport id, so any type on it, a Grove identifier role or another, is refused.
    private static func validateHeader(_ bundle: ModelsR4.Bundle) throws(ExchangeGraphError) {
        guard bundle.type.value == .collection else {
            throw .notCollectionBundle
        }
        guard bundle.timestamp != nil else {
            throw .missingTimestamp
        }
        guard bundle.identifier?.type == nil else {
            throw diagnostic(.mobileExchangeBundleIdentifier, location: "Bundle.identifier")
        }
    }

    private static func validatedEntries(
        _ bundle: ModelsR4.Bundle,
        kind: Kind
    ) throws(ExchangeGraphError) -> [BundleEntry] {
        let profiles = bundle.meta?.profile ?? []
        let exchangeProfiles = [Profile.groveMobileExchangeBundle, Profile.groveMobileRetractionBundle]
        guard profiles.filter(exchangeProfiles.contains) == [kind.profile] else {
            throw diagnostic(.mobileExchangeBundleProfile, location: "Bundle.meta.profile")
        }
        guard let entries = bundle.entry, !entries.isEmpty else {
            throw .ruleViolation(.mobileExchangeEntryRequired)
        }
        guard entries.allSatisfy({
            $0.search == nil && $0.request == nil && $0.response == nil
        }) == true else {
            throw .ruleViolation(.mobileExchangeCollectionEntryOperation)
        }
        return entries
    }

    private static func validateEntryIdentities(
        kind: Kind,
        entries: [BundleEntry],
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        try validateResourceIdentifiers(entries: entries, document: document)
        do {
            try ExchangeIdentity.validateIdentifierSystemRoles(in: document.bundleObjects())
        } catch let error as ExchangeIdentityError {
            throw .ruleViolation(Self.rule(for: error))
        } catch {
            throw .invalidEntries(String(reflecting: type(of: error)))
        }
        try validateEntryKeys(kind: kind, entries: entries, document: document)
    }

    private static func validateLifecycle(
        kind: Kind,
        entries: [BundleEntry],
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        switch kind {
        case .active:
            try Self.validateActive(entries: entries, document: document)
        case .retraction:
            try Self.validateRetraction(entries: entries, document: document)
        }
    }

    /// Returns the one entry with this fullUrl, if present.
    public func entry(fullURL: FHIRPrimitive<FHIRURI>) -> BundleEntry? {
        bundle.entry?.first { $0.fullUrl == fullURL }
    }
}
