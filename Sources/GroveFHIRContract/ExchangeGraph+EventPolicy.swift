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
    private struct ActiveOutput {
        let sourceRecord: RoledIdentifier
        let fullURL: String
        let resourceType: String
    }

    private struct ActiveOutputSummary {
        var sourceRecords: Set<RoledIdentifier> = []
        var resourceTypesByURL: [String: String] = [:]

        mutating func append(_ output: ActiveOutput) {
            sourceRecords.insert(output.sourceRecord)
            resourceTypesByURL[output.fullURL] = output.resourceType
        }
    }

    static func rule(for error: ExchangeIdentityError) -> ExchangeGraphRule {
        switch error {
        case .identifierSystemRoleMismatch:
            .mobileExchangeIdentitySystemRole
        case .invalidIdentifierRole, .duplicateIdentifierRole:
            .mobileExchangeIdentifierRole
        case .invalidIdentifierSystem, .nonCanonicalIdentifierSystem, .missingIdentifierSystem:
            .mobileExchangeOpaqueResourceIdentity
        default:
            .mobileExchangeUnclassified
        }
    }

    static func validateEntryResourcePolicy(
        kind: ExchangeGraphKind,
        entries: [BundleEntry]
    ) throws(ExchangeGraphError) {
        let activeTypes = ExchangeContract.activeOutputResourceTypes
            .union(ExchangeContract.activeSupportingResourceTypes)
            .union([ExchangeContract.activeLifecycleResourceType])
        for entry in entries {
            guard let resource = entry.resource else {
                throw .invalidEntries("Bundle entry has no resource")
            }
            switch kind {
            case .active:
                guard activeTypes.contains(resource.resourceType) else {
                    throw .ruleViolation(.mobileExchangeEntryResourceType)
                }
            case .retraction:
                guard resource.resourceType == ResourceType.provenance.rawValue
                        || resource.resourceType == ResourceType.device.rawValue else {
                    throw .ruleViolation(.mobileRetractionNoClinicalCopy)
                }
            }
            do {
                let data = try JSONEncoder().encode(resource)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    throw ExchangeGraphError.invalidEntries("Bundle entry resource is not an object")
                }
                guard object["contained"] == nil,
                      !containsContainedReference(object) else {
                    throw ExchangeGraphError.ruleViolation(.mobileExchangeContainedResourceProhibited)
                }
            } catch let error as ExchangeGraphError {
                throw error
            } catch {
                throw .invalidEntries(String(reflecting: type(of: error)))
            }
        }
    }

    static func validateEntryNodeDigests(
        entries: [BundleEntry],
        eventIdentifier: ExchangeEventIdentifier
    ) throws(ExchangeGraphError) {
        var mintedPerNodeRole: [String: UInt64] = [:]
        for (index, entry) in entries.enumerated() {
            let keys = entry.extension?.filter { $0.url == Canonicals.entryNodeKey } ?? []
            guard keys.count == 1,
                  case .identifier(let identifier)? = keys.first?.value else {
                throw .ruleViolation(.mobileExchangeEntryNodeKey)
            }
            let key: RoledIdentifier
            do {
                key = try RoledIdentifier(identifier)
            } catch {
                throw .ruleViolation(.mobileExchangeEntryNodeKey)
            }
            let location = "Bundle.entry[\(index)].extension.valueIdentifier"
            if key.role == .entryNode {
                guard EntryNodeKey.claim(in: key) != nil else {
                    throw diagnostic(.mobileExchangeEntryKeySelection, location: location)
                }
                try validateEntryNodeOrdinal(key, location: location, mintedPerNodeRole: &mintedPerNodeRole)
                do {
                    _ = try EntryNodeKey(key, event: eventIdentifier)
                } catch {
                    throw diagnostic(.mobileExchangeEntryNodeDigest, location: "\(location).value")
                }
            } else if !ExchangeIdentity.isCanonicalOpaqueIdentifierValue(key.identifier.value) {
                throw diagnostic(.mobileExchangeOpaqueResourceIdentity, location: location)
            }
        }
    }

    /// The expected ordinal is counted from the Bundle's own per-role entry order rather than read
    /// back from the key, because the digest covers the ordinal the key itself states: a
    /// self-consistent key over a wrong ordinal would otherwise verify against its own claim.
    private static func validateEntryNodeOrdinal(
        _ identifier: RoledIdentifier,
        location: String,
        mintedPerNodeRole: inout [String: UInt64]
    ) throws(ExchangeGraphError) {
        guard let claim = EntryNodeKey.claim(in: identifier) else {
            return
        }
        let expected = mintedPerNodeRole[claim.nodeRole, default: 0]
        mintedPerNodeRole[claim.nodeRole] = expected + 1
        guard claim.ordinal.rawValue == String(expected) else {
            throw diagnostic(.mobileExchangeEntryNodeOrdinal, location: "\(location).value")
        }
    }

    static func validateActive(entries: [BundleEntry]) throws(ExchangeGraphError) {
        try validateActiveProfileClaims(entries: entries)
        let provenance = try validatedActiveProvenance(entries: entries)
        guard hasExactLifecycleCoding(provenance, kind: .active) else {
            throw .ruleViolation(.mobileExchangeLifecycleCoding)
        }
        let outputs = try validateActiveEntries(entries)
        try validateRecordingDocuments(entries, sourceDerivedOutputCount: outputs.resourceTypesByURL.count)
        try validateSourceMarkers(entries: entries)
        try validateActiveTargets(provenance, resourceTypesByURL: outputs.resourceTypesByURL)
        let sourceEntity = try exactSourceEntity(in: provenance)
        guard outputs.sourceRecords.contains(sourceEntity) else {
            throw .ruleViolation(.mobileExchangeTransformProvenance)
        }
        try validateStudyContext(entries: entries)
        try validateSupportingConnectivity(entries: entries)
    }

    private static func validatedActiveProvenance(
        entries: [BundleEntry]
    ) throws(ExchangeGraphError) -> Provenance {
        let provenanceEntries = entries.compactMap { entry -> Provenance? in
            guard case .provenance(let provenance)? = entry.resource else {
                return nil
            }
            return provenance
        }
        guard provenanceEntries.count == 1,
              let provenance = provenanceEntries.first,
              hasRequiredTimes(provenance),
              let assembler = exactAssembler(in: provenance),
              activeAssemblerResolves(assembler, entries: entries) else {
            throw .ruleViolation(.mobileExchangeTransformProvenance)
        }
        return provenance
    }

    private static func validateActiveEntries(
        _ entries: [BundleEntry]
    ) throws(ExchangeGraphError) -> ActiveOutputSummary {
        var summary = ActiveOutputSummary()
        do {
            for entry in entries {
                if let output = try validatedActiveOutput(from: entry) {
                    summary.append(output)
                }
            }
        } catch let error as ExchangeGraphError {
            throw error
        } catch {
            throw .ruleViolation(.mobileOutputSourceOutputRequired)
        }
        guard !summary.resourceTypesByURL.isEmpty else {
            throw .ruleViolation(.mobileExchangeOutputRequired)
        }
        guard summary.sourceRecords.count == 1 else {
            throw .ruleViolation(.mobileOutputSourceOutputRequired)
        }
        return summary
    }

    private static func validatedActiveOutput(
        from entry: BundleEntry
    ) throws -> ActiveOutput? {
        guard let key = try entryKey(entry) else {
            throw ExchangeIdentityError.missingIdentifierSystem
        }
        let identifiers = try ExchangeIdentity.typedResourceIdentifiers(in: entry.resource)
        guard Set(identifiers).count == identifiers.count else {
            throw ExchangeIdentityError.duplicateEntryIdentifier(key.identifier)
        }
        if case .device(let device)? = entry.resource {
            try validateDeviceIdentity(device, entryKey: key, identifiers: identifiers)
        }
        guard let resource = entry.resource, isActiveOutput(resource) else {
            return nil
        }
        let sourceOutputs = identifiers.filter { $0.role == .sourceOutput }
        let sourceRecords = identifiers.filter { $0.role == .sourceRecord }
        guard key.role == .sourceOutput,
              sourceOutputs == [key],
              sourceRecords.count == 1,
              let fullURL = entry.fullUrl?.value?.url.absoluteString else {
            throw ExchangeGraphError.ruleViolation(.mobileOutputSourceOutputRequired)
        }
        if case .documentReference(let document) = resource {
            try validateRecordingDocumentTypedIdentity(document, identifiers: identifiers)
        }
        return ActiveOutput(
            sourceRecord: sourceRecords[0],
            fullURL: fullURL,
            resourceType: resource.resourceType
        )
    }

    private static func validateRecordingDocumentTypedIdentity(
        _ document: DocumentReference,
        identifiers: [RoledIdentifier]
    ) throws(ExchangeGraphError) {
        let writerCount = identifiers.filter { $0.role == .writerRecord }.count
        guard document.content.count == 1,
              identifiers.filter({ $0.role == .sourceRecord }).count == 1,
              identifiers.filter({ $0.role == .sourceOutput }).count == 1,
              identifiers.filter({ $0.role == .sourceArtifact }).count == 1,
              writerCount <= 1,
              identifiers.count == 3 + writerCount else {
            throw .ruleViolation(.sensorRecordingDocumentIdentityAndContent)
        }
    }

    private static func validateRecordingDocuments(
        _ entries: [BundleEntry],
        sourceDerivedOutputCount: Int
    ) throws(ExchangeGraphError) {
        for entry in entries {
            guard case .documentReference(let document)? = entry.resource else {
                continue
            }
            let typed: [RoledIdentifier]
            do {
                typed = try ExchangeIdentity.typedResourceIdentifiers(in: entry.resource)
            } catch {
                throw .ruleViolation(.sensorRecordingDocumentIdentityAndContent)
            }
            guard recordingDocumentIdentifiersAreValid(
                document,
                typed: typed,
                sourceDerivedOutputCount: sourceDerivedOutputCount
            ) else {
                throw .ruleViolation(.sensorRecordingDocumentIdentityAndContent)
            }
        }
    }

    private static func validateActiveTargets(
        _ provenance: Provenance,
        resourceTypesByURL: [String: String]
    ) throws(ExchangeGraphError) {
        let provenanceTargets = provenance.target.compactMap { $0.reference?.value?.string }
        guard provenanceTargets.count == provenance.target.count,
              Set(provenanceTargets).count == provenanceTargets.count,
              Set(provenanceTargets) == Set(resourceTypesByURL.keys),
              provenance.target.allSatisfy({ target in
                  activeTargetIsValid(target, resourceTypesByURL: resourceTypesByURL)
              }) else {
            throw diagnostic(.mobileExchangeProvenanceTargets, location: "Provenance.target")
        }
    }

    /// An adapter's source marker belongs on that adapter's outputs alone, once each.
    private static func validateSourceMarkers(entries: [BundleEntry]) throws(ExchangeGraphError) {
        let marker = HealthKitContract.sourceTypeExtension.value?.url.absoluteString
        let adapterRoot = "\(Canonicals.root)/healthkit/"
        for entry in entries {
            guard let resource = entry.resource, isActiveOutput(resource) else {
                continue
            }
            let extensions: [[String: Any]]
            do {
                let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(resource)) as? [String: Any]
                extensions = object?["extension"] as? [[String: Any]] ?? []
            } catch {
                throw .invalidEntries(String(reflecting: type(of: error)))
            }
            let markers = extensions.filter { $0["url"] as? String == marker }.count
            let claimsAdapter = resourceProfiles(resource).contains { $0.hasPrefix(adapterRoot) }
            guard markers == (claimsAdapter ? 1 : 0) else {
                throw diagnostic(.mobileOutputAdapterSourceMarker, location: "\(resource.resourceType).extension")
            }
        }
    }

    private static func activeTargetIsValid(
        _ target: Reference,
        resourceTypesByURL: [String: String]
    ) -> Bool {
        guard target.identifier == nil,
              let reference = target.reference?.value?.string,
              let resourceType = resourceTypesByURL[reference] else {
            return false
        }
        if let targetType = target.type?.value?.url.absoluteString {
            return targetType == resourceType
        }
        return true
    }

    private static func recordingDocumentIdentifiersAreValid(
        _ document: DocumentReference,
        typed: [RoledIdentifier],
        sourceDerivedOutputCount: Int
    ) -> Bool {
        let all = document.identifier ?? []
        let roleSystem = Canonicals.identifierRoleCodeSystem.value?.url.absoluteString
        let nonGrove = all.filter { identifier in
            identifier.type?.coding?.contains {
                $0.system?.value?.url.absoluteString == roleSystem
            } != true
        }
        guard all.count == typed.count + nonGrove.count,
              nonGrove.count <= 1 else {
            return false
        }
        guard let governed = nonGrove.first else {
            return true
        }
        return sourceDerivedOutputCount == 1 && isGovernedSourceIdentifier(governed)
    }

    private static func isGovernedSourceIdentifier(_ identifier: Identifier) -> Bool {
        guard (try? BusinessIdentifier(identifier)) != nil,
              identifier.type?.coding?.contains(where: {
                  $0.system?.value?.url.absoluteString == Canonicals.identifierRoleCodeSystemValue
              }) != true else {
            return false
        }
        guard let type = identifier.type else {
            return true
        }
        let text = type.text?.value?.string
        if text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            return false
        }
        let codings = type.coding ?? []
        guard text != nil || !codings.isEmpty else {
            return false
        }
        return codings.allSatisfy { coding in
            guard let rawSystem = coding.system?.value?.url.absoluteString,
                  let system = try? IdentifierSystem(rawSystem),
                  let code = coding.code?.value?.string else {
                return false
            }
            return (try? GovernedSourceIdentifierType(
                system: system,
                code: code,
                display: coding.display?.value?.string
            )) != nil
        }
    }

    static func validateRetraction(entries: [BundleEntry]) throws(ExchangeGraphError) {
        for entry in entries {
            try validateRetractionEntry(entry)
        }
        let provenance = try validatedRetractionProvenance(entries: entries)
        guard !isTransformOnlyLifecycle(provenance) else {
            throw .ruleViolation(.mobileRetractionProvenance)
        }
        guard hasExactLifecycleCoding(provenance, kind: .retraction) else {
            throw .ruleViolation(.mobileExchangeLifecycleCoding)
        }
        _ = try exactSourceEntity(in: provenance)
        guard !provenance.target.isEmpty else {
            throw diagnostic(.mobileRetractionTargetRequired, location: "Provenance.target")
        }
        try validateRetractionTargets(provenance.target)
    }

    private static func validateRetractionEntry(
        _ entry: BundleEntry
    ) throws(ExchangeGraphError) {
        guard let resource = entry.resource else {
            throw .invalidEntries("Bundle entry has no resource")
        }
        switch resource {
        case .provenance(let provenance):
            try validateRetractionProvenanceProfile(provenance)
        case .device(let device):
            let claim = try validateDirectProfileClaim(
                profiles: device.meta?.profile ?? [],
                modes: ProfileClaims.deviceProfileModes,
                rule: .mobileSupportDeviceProfile
            )
            try validateIdentifierRoles(in: resource, claim: claim, rule: .mobileDeviceRecordingDeviceDualIdentity)
            guard let key = try? entryKey(entry) else {
                throw .ruleViolation(.mobileDeviceRecordingDeviceDualIdentity)
            }
            let identifiers = (try? ExchangeIdentity.typedResourceIdentifiers(in: resource)) ?? []
            try validateDeviceIdentity(device, entryKey: key, identifiers: identifiers)
        default:
            throw .ruleViolation(.mobileRetractionNoClinicalCopy)
        }
    }

    private static func validatedRetractionProvenance(
        entries: [BundleEntry]
    ) throws(ExchangeGraphError) -> Provenance {
        let resources = entries.compactMap(\.resource)
        let provenances = resources.compactMap { resource -> Provenance? in
            guard case .provenance(let provenance) = resource else {
                return nil
            }
            return provenance
        }
        guard provenances.count == 1,
              let provenance = provenances.first,
              provenance.meta?.profile?.contains(GroveLifecycleContract.retractionProvenanceProfile) == true,
              hasRequiredTimes(provenance),
              let assembler = exactAssembler(in: provenance),
              retractionAssemblerIsDevice(assembler, entries: entries) else {
            throw .ruleViolation(.mobileRetractionNoClinicalCopy)
        }
        return provenance
    }

    private static func validateRetractionTargets(
        _ targets: [Reference]
    ) throws(ExchangeGraphError) {
        var logicalTargets: Set<BusinessIdentifier> = []
        for (index, target) in targets.enumerated() {
            let logicalTarget = try validatedRetractionTarget(target)
            guard logicalTargets.insert(logicalTarget.identifier.identifier).inserted else {
                throw diagnostic(.mobileRetractionDistinctTarget, location: "Provenance.target[\(index)].identifier")
            }
        }
    }

    private static func validatedRetractionTarget(
        _ target: Reference
    ) throws(ExchangeGraphError) -> RetractionTarget {
        guard target.reference == nil,
              let type = target.type?.value?.url.absoluteString,
              let resourceType = ResourceType(rawValue: type),
              let identifier = target.identifier,
              let businessIdentifier = try? RoledIdentifier(identifier) else {
            throw .ruleViolation(.mobileRetractionLogicalTarget)
        }
        guard ExchangeIdentity.isCanonicalOpaqueIdentifierValue(businessIdentifier.identifier.value) else {
            throw .ruleViolation(.mobileRetractionOpaqueTarget)
        }
        let roles = target.extension?.filter { $0.url == Canonicals.retractionTargetRole } ?? []
        guard roles.count == 1,
              case .code(let roleCode)? = roles.first?.value,
              let rawRole = roleCode.value?.string,
              let role = RetractionTargetRole(rawValue: rawRole) else {
            throw .ruleViolation(.mobileRetractionTargetRole)
        }
        let natives = target.extension?.filter { $0.url == Canonicals.retractionTargetNativeIdentifier } ?? []
        guard natives.count <= 1 else {
            throw .ruleViolation(.mobileRetractionNativeRecordIdentifier)
        }
        var nativeRecordIdentifier: Identifier?
        if let native = natives.first {
            guard case .identifier(let disclosed)? = native.value else {
                throw .ruleViolation(.mobileRetractionNativeRecordIdentifier)
            }
            nativeRecordIdentifier = disclosed
        }
        do {
            return try RetractionTarget(
                identifier: businessIdentifier,
                resourceType: resourceType,
                role: role,
                nativeRecordIdentifier: nativeRecordIdentifier
            )
        } catch {
            switch error {
            case .identifierRoleMismatch, .resourceTypeMismatch:
                throw .ruleViolation(.mobileRetractionRoleTargetType)
            case .invalidNativeRecordIdentifier:
                throw .ruleViolation(.mobileRetractionNativeRecordIdentifier)
            }
        }
    }
}
