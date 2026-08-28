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
public struct ExchangeGraph: Sendable {
    public let kind: ExchangeGraphKind
    public let eventIdentifier: ExchangeEventIdentifier
    public let bundle: ModelsR4.Bundle

    public init(
        kind: ExchangeGraphKind,
        eventIdentifier: ExchangeEventIdentifier,
        bundle: ModelsR4.Bundle
    ) throws(ExchangeGraphError) {
        try Self.validateHeader(
            bundle,
            eventIdentifier: eventIdentifier
        )
        let entries = try Self.validatedEntries(bundle, kind: kind)
        try Self.validateEntryResourcePolicy(kind: kind, entries: entries)
        try Self.validateEntryNodeDigests(entries: entries, eventIdentifier: eventIdentifier)
        try Self.validateEntryIdentities(in: bundle, entries: entries)
        try Self.validateGovernedReferenceTargets(entries: entries)
        try Self.validateLifecycle(kind: kind, entries: entries)
        self.kind = kind
        self.eventIdentifier = eventIdentifier
        self.bundle = bundle
    }

    /// Decodes and validates a serialized event while preserving rule diagnostics for mutations
    /// that make a resource impossible for ModelsR4 to decode (for example, changing only its
    /// resourceType to a closed-out type).
    public init(
        kind: ExchangeGraphKind,
        jsonData: Data
    ) throws(ExchangeGraphError) {
        try Self.validateSerializedEntryPolicy(kind: kind, data: jsonData)
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
            throw .ruleViolation(.eventIdentity)
        }
        try self.init(
            kind: kind,
            eventIdentifier: eventIdentifier,
            bundle: decodedBundle
        )
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
        let actual: BusinessIdentifier
        do {
            actual = try BusinessIdentifier(identifier)
        } catch {
            throw .invalidEventIdentifier
        }
        do {
            _ = try ExchangeEventIdentifier(actual)
        } catch {
            throw .ruleViolation(.eventIdentity)
        }
        guard actual == eventIdentifier.businessIdentifier, actual.role == .event else {
            throw .eventIdentifierMismatch
        }
    }

    private static func validatedEntries(
        _ bundle: ModelsR4.Bundle,
        kind: ExchangeGraphKind
    ) throws(ExchangeGraphError) -> [BundleEntry] {
        guard bundle.meta?.profile?.contains(kind.profile) == true else {
            throw .missingProfile(kind.profile.value?.url.absoluteString ?? "")
        }
        guard let entries = bundle.entry, !entries.isEmpty else {
            throw .ruleViolation(.entryNodeKey)
        }
        guard entries.allSatisfy({
            $0.search == nil && $0.request == nil && $0.response == nil
        }) == true else {
            throw .ruleViolation(.collectionHasRequestOrResponse)
        }
        return entries
    }

    private static func validateEntryIdentities(
        in bundle: ModelsR4.Bundle,
        entries: [BundleEntry]
    ) throws(ExchangeGraphError) {
        do {
            try ExchangeIdentity.validateIdentifierSystemRoles(in: bundle)
            try ExchangeIdentity.validate(entries: entries)
        } catch let error as ExchangeIdentityError {
            throw .ruleViolation(Self.rule(for: error))
        } catch {
            throw .invalidEntries(String(reflecting: type(of: error)))
        }
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
    public func entry(fullURL: String) -> BundleEntry? {
        bundle.entry?.first { $0.fullUrl?.value?.url.absoluteString == fullURL }
    }
}
