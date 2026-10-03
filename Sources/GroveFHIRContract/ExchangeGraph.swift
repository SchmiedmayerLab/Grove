//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import ModelsR4


/// The semantic kind of a complete Grove exchange graph; the kind now lives at ``ExchangeGraph/Kind``.
@available(*, deprecated, renamed: "ExchangeGraph.Kind", message: "Compatibility spelling; removed with the exporter rework's final cleanup.")
public typealias ExchangeGraphKind = ExchangeGraph.Kind


/// The one authoritative, validated value emitted by a Grove producer.
///
/// Entries are owned only by the Bundle. Producers may expose stable entry keys, but do not retain
/// independent mutable resource copies that can drift from what is serialized and uploaded.
/// The graph keeps the JSON it was validated from, so ``isSemanticallyEqual(to:)`` decides over
/// lossless tokens rather than over a model that has already normalized decimal lexemes, and so a
/// consumer uploads exactly what was validated: ``json``.
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
                GroveLifecycleContract.retractionBundleProfile
            }
        }
    }

    /// Sorted members and unescaped slashes: the same tokens the default encoder emits, in one
    /// member order in every process, so a retry reproduces the bytes and a stored graph diffs by content.
    private static var wireEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public let kind: Kind
    public let eventIdentifier: ExchangeEventIdentifier
    public let bundle: ModelsR4.Bundle
    /// The serialized graph exactly as it was validated.
    ///
    /// A graph built from a model holds that model's canonical encoding (sorted members, slashes
    /// unescaped); a graph re-validated from stored bytes holds those bytes unchanged. Upload and
    /// persist these bytes, not a re-encoding of ``bundle``.
    public let json: Data

    /// The event's business identifier, as `Bundle.identifier` states it.
    public var event: BusinessIdentifier { eventIdentifier.identifier.identifier }

    public init(
        kind: Kind,
        eventIdentifier: ExchangeEventIdentifier,
        bundle: ModelsR4.Bundle
    ) throws(ExchangeGraphError) {
        self.json = try Self.drainingTemporaries { () throws(ExchangeGraphError) in
            let json: Data
            do {
                json = try Self.wireEncoder.encode(bundle)
            } catch {
                throw .invalidEntries(String(reflecting: type(of: error)))
            }
            try Self.validate(
                kind: kind,
                eventIdentifier: eventIdentifier,
                bundle: bundle,
                document: ValidationDocument(bundle: bundle, jsonData: json)
            )
            return json
        }
        self.kind = kind
        self.eventIdentifier = eventIdentifier
        self.bundle = bundle
    }

    /// Re-validates stored or received JSON before it is trusted again, and keeps exactly those bytes as ``json``.
    ///
    /// Serialized checks run first, because Foundation keeps only one of duplicate members and
    /// decoding through `Foundation.URL` could normalize an identity system or collapse a
    /// prohibited resource type before the model sees it.
    public init(
        validating json: Data,
        kind: Kind
    ) throws(ExchangeGraphError) {
        (self.eventIdentifier, self.bundle) = try Self.drainingTemporaries { () throws(ExchangeGraphError) in
            try Self.decodeValidated(kind: kind, jsonData: json)
        }
        self.kind = kind
        self.json = json
    }

    /// ``init(validating:kind:)`` under its earlier spelling.
    @available(*, deprecated, renamed: "init(validating:kind:)", message: "Compatibility spelling; removed with the exporter rework's final cleanup.")
    public init(
        kind: Kind,
        jsonData: Data
    ) throws(ExchangeGraphError) {
        try self.init(validating: jsonData, kind: kind)
    }

    private static func decodeValidated(
        kind: Kind,
        jsonData: Data
    ) throws(ExchangeGraphError) -> (ExchangeEventIdentifier, ModelsR4.Bundle) {
        do {
            var scanner = StrictJSONScanner(jsonData)
            try scanner.validate()
        } catch {
            throw .invalidEntries("Serialized event is not strict JSON")
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
        guard let identifier = decodedBundle.identifier else {
            throw .missingEventIdentifier
        }
        let eventIdentifier: ExchangeEventIdentifier
        do {
            eventIdentifier = try ExchangeEventIdentifier(BusinessIdentifier(identifier))
        } catch {
            throw .ruleViolation(.mobileExchangeEventIdentity)
        }
        // The model checks read the decoded model's own encoding, not the stored bytes: those may still
        // carry members the model does not keep, and the checks decide over what the graph will hold.
        try Self.validate(
            kind: kind,
            eventIdentifier: eventIdentifier,
            bundle: decodedBundle,
            document: ValidationDocument(bundle: decodedBundle, jsonData: nil)
        )
        return (eventIdentifier, decodedBundle)
    }

    /// Runs `body` in its own autorelease pool where there is one, so the Foundation temporaries of
    /// encoding, parsing and validating one graph are released with that graph rather than with the
    /// caller's pool, which a batch conversion may not drain until thousands of graphs later.
    private static func drainingTemporaries<T>(
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
        eventIdentifier: ExchangeEventIdentifier,
        bundle: ModelsR4.Bundle,
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        try validateHeader(bundle, eventIdentifier: eventIdentifier)
        let entries = try validatedEntries(bundle, kind: kind)
        try validateEntryResourcePolicy(kind: kind, entries: entries, document: document)
        try validateEntryNodeDigests(entries: entries, eventIdentifier: eventIdentifier)
        try validateEntryIdentities(entries: entries, document: document)
        try validateGovernedReferenceTargets(entries: entries, document: document)
        try validateLifecycle(kind: kind, entries: entries, document: document)
    }

    private static func validateHeader(
        _ bundle: ModelsR4.Bundle,
        eventIdentifier: ExchangeEventIdentifier
    ) throws(ExchangeGraphError) {
        guard bundle.type.value == .collection else {
            throw .notCollectionBundle
        }
        guard bundle.timestamp != nil else {
            throw .missingTimestamp
        }
        guard let identifier = bundle.identifier else {
            throw .missingEventIdentifier
        }
        let actual: RoledIdentifier
        do {
            actual = try RoledIdentifier(identifier)
        } catch .duplicateIdentifierRole {
            throw diagnostic(.mobileExchangeIdentifierRole, location: "Bundle.identifier")
        } catch {
            throw .invalidEventIdentifier
        }
        do {
            _ = try ExchangeEventIdentifier(actual.identifier)
        } catch {
            throw .ruleViolation(.mobileExchangeEventIdentity)
        }
        guard actual == eventIdentifier.identifier else {
            throw .eventIdentifierMismatch
        }
    }

    private static func validatedEntries(
        _ bundle: ModelsR4.Bundle,
        kind: Kind
    ) throws(ExchangeGraphError) -> [BundleEntry] {
        let profiles = bundle.meta?.profile ?? []
        let exchangeProfiles = [Profile.groveMobileExchangeBundle, GroveLifecycleContract.retractionBundleProfile]
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
        entries: [BundleEntry],
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        try validateResourceIdentifiers(entries: entries, document: document)
        do {
            try ExchangeIdentity.validateIdentifierSystemRoles(inBundleJSON: document.bundleObject())
        } catch let error as ExchangeIdentityError {
            throw .ruleViolation(Self.rule(for: error))
        } catch {
            throw .invalidEntries(String(reflecting: type(of: error)))
        }
        try validateEntryKeys(entries: entries, document: document)
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
