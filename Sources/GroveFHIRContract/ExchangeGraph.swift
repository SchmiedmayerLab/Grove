//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import ModelsR4


/// The semantic kind of a complete Grove exchange graph.
public enum ExchangeGraphKind: Hashable, Sendable {
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


/// The one authoritative, validated value emitted by a Grove producer.
///
/// Entries are owned only by the Bundle. Producers may expose stable entry keys, but do not retain
/// independent mutable resource copies that can drift from what is serialized and uploaded.
/// The graph keeps the JSON it was validated from, so ``isSemanticallyEqual(to:)`` decides over
/// lossless tokens rather than over a model that has already normalized decimal lexemes.
public struct ExchangeGraph: Sendable {
    public let kind: ExchangeGraphKind
    public let eventIdentifier: ExchangeEventIdentifier
    public let bundle: ModelsR4.Bundle
    let jsonData: Data

    public init(
        kind: ExchangeGraphKind,
        eventIdentifier: ExchangeEventIdentifier,
        bundle: ModelsR4.Bundle
    ) throws(ExchangeGraphError) {
        let jsonData: Data
        do {
            jsonData = try JSONEncoder().encode(bundle)
        } catch {
            throw .invalidEntries(String(reflecting: type(of: error)))
        }
        try Self.validate(kind: kind, eventIdentifier: eventIdentifier, bundle: bundle)
        self.kind = kind
        self.eventIdentifier = eventIdentifier
        self.bundle = bundle
        self.jsonData = jsonData
    }

    /// Re-validates stored or received JSON before it is trusted again.
    ///
    /// Serialized checks run first, because Foundation keeps only one of duplicate members and
    /// decoding through `Foundation.URL` could normalize an identity system or collapse a
    /// prohibited resource type before the model sees it.
    public init(
        kind: ExchangeGraphKind,
        jsonData: Data
    ) throws(ExchangeGraphError) {
        do {
            var scanner = StrictJSONScanner(jsonData)
            try scanner.validate()
        } catch {
            throw .invalidEntries("Serialized event is not strict JSON")
        }
        try Self.validateSerializedEntryPolicy(kind: kind, data: jsonData)
        do {
            try ExchangeIdentity.validateSerializedIdentifierSystems(in: jsonData)
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
        try Self.validate(kind: kind, eventIdentifier: eventIdentifier, bundle: decodedBundle)
        self.kind = kind
        self.eventIdentifier = eventIdentifier
        self.bundle = decodedBundle
        self.jsonData = jsonData
    }

    private static func validate(
        kind: ExchangeGraphKind,
        eventIdentifier: ExchangeEventIdentifier,
        bundle: ModelsR4.Bundle
    ) throws(ExchangeGraphError) {
        try validateHeader(bundle, eventIdentifier: eventIdentifier)
        let entries = try validatedEntries(bundle, kind: kind)
        try validateEntryResourcePolicy(kind: kind, entries: entries)
        try validateEntryNodeDigests(entries: entries, eventIdentifier: eventIdentifier)
        try validateEntryIdentities(in: bundle, entries: entries)
        try validateGovernedReferenceTargets(entries: entries)
        try validateLifecycle(kind: kind, entries: entries)
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
        kind: ExchangeGraphKind
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
        in bundle: ModelsR4.Bundle,
        entries: [BundleEntry]
    ) throws(ExchangeGraphError) {
        try validateResourceIdentifiers(entries: entries)
        do {
            try ExchangeIdentity.validateIdentifierSystemRoles(in: bundle)
        } catch let error as ExchangeIdentityError {
            throw .ruleViolation(Self.rule(for: error))
        } catch {
            throw .invalidEntries(String(reflecting: type(of: error)))
        }
        try validateEntryKeys(entries: entries)
    }

    private static func validateLifecycle(
        kind: ExchangeGraphKind,
        entries: [BundleEntry]
    ) throws(ExchangeGraphError) {
        switch kind {
        case .active:
            try Self.validateActive(entries: entries)
        case .retraction:
            try Self.validateRetraction(entries: entries)
        }
    }

    /// Returns the one entry with this fullUrl, if present.
    public func entry(fullURL: FHIRPrimitive<FHIRURI>) -> BundleEntry? {
        bundle.entry?.first { $0.fullUrl == fullURL }
    }
}
