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
        let sourceRecord: BusinessIdentifier
        let fullURL: String
        let resourceType: String
    }

    private struct ActiveOutputSummary {
        var sourceRecords: Set<BusinessIdentifier> = []
        var resourceTypesByURL: [String: String] = [:]

        mutating func append(_ output: ActiveOutput) {
            sourceRecords.insert(output.sourceRecord)
            resourceTypesByURL[output.fullURL] = output.resourceType
        }
    }

    static func rule(for error: ExchangeIdentityError) -> ExchangeGraphRule {
        switch error {
        case .duplicateEntryKeyExtension, .missingIdentifierSystem, .missingIdentifierValue,
             .invalidEntryKeyRole:
            .entryNodeKey
        case .incorrectFullURL, .duplicateFullURL:
            .deterministicFullURL
        case .unresolvedInternalReference:
            .resolvedReference
        case .containedResourcesProhibited:
            .containedResourceProhibited
        case .incorrectInternalReferenceType:
            .referenceDeclaredType
        case .entryKeyPriorityMismatch:
            .sourceOutputRequired
        case .identifierSystemRoleMismatch:
            .identitySystemRole
        case .invalidEntryNodeValue, .invalidEntryNodeRole:
            .entryNodeDigest
        default:
            .entryNodeKey
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
                    throw .ruleViolation(.entryResourceType)
                }
            case .retraction:
                guard resource.resourceType == ResourceType.provenance.rawValue
                        || resource.resourceType == ResourceType.device.rawValue else {
                    throw .ruleViolation(.retractionNoClinicalCopy)
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
                    throw ExchangeGraphError.ruleViolation(.containedResourceProhibited)
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
        for entry in entries {
            let keys = entry.extension?.filter { $0.url == Canonicals.entryNodeKey } ?? []
            guard keys.count == 1,
                  case .identifier(let identifier)? = keys.first?.value else {
                throw .ruleViolation(.entryNodeKey)
            }
            let businessIdentifier: BusinessIdentifier
            do {
                businessIdentifier = try BusinessIdentifier(identifier)
            } catch {
                throw .ruleViolation(.entryNodeKey)
            }
            if businessIdentifier.role == .entryNode {
                do {
                    _ = try ExchangeNodeKey(
                        businessIdentifier,
                        eventIdentifier: eventIdentifier
                    )
                } catch {
                    throw .ruleViolation(.entryNodeDigest)
                }
            } else if !ExchangeIdentity.isCanonicalOpaqueIdentifierValue(businessIdentifier.value) {
                throw .ruleViolation(.entryNodeDigest)
            }
        }
    }

    static func validateActive(entries: [BundleEntry]) throws(ExchangeGraphError) {
        try validateActiveProfileClaims(entries: entries)
        let provenance = try validatedActiveProvenance(entries: entries)
        guard hasExactLifecycleCoding(provenance, kind: .active) else {
            throw .ruleViolation(.lifecycleCoding)
        }
        let outputs = try validateActiveEntries(entries)
        try validateRecordingDocuments(entries, sourceDerivedOutputCount: outputs.resourceTypesByURL.count)
        try validateActiveTargets(provenance, resourceTypesByURL: outputs.resourceTypesByURL)
        let sourceEntity = try exactSourceEntity(in: provenance)
        guard outputs.sourceRecords.contains(sourceEntity) else {
            throw .ruleViolation(.transformProvenance)
        }
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
            throw .ruleViolation(.transformProvenance)
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
            throw .ruleViolation(.sourceOutputRequired)
        }
        guard summary.sourceRecords.count == 1, !summary.resourceTypesByURL.isEmpty else {
            throw .ruleViolation(.sourceOutputRequired)
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
            throw ExchangeIdentityError.duplicateEntryIdentifier(key)
        }
        if case .device(let device)? = entry.resource {
            try validateDeviceIdentity(device, entryKey: key, identifiers: identifiers)
        }
        guard key.role == .sourceOutput else {
            if key.role == .sourceArtifact || key.role == .sourceRecord {
                throw ExchangeIdentityError.entryKeyPriorityMismatch
            }
            return nil
        }
        let sourceOutputs = identifiers.filter { $0.role == .sourceOutput }
        let sourceRecords = identifiers.filter { $0.role == .sourceRecord }
        guard sourceOutputs == [key],
              sourceRecords.count == 1,
              ExchangeIdentity.isCanonicalOpaqueIdentifierValue(key.value),
              ExchangeIdentity.isCanonicalOpaqueIdentifierValue(sourceRecords[0].value),
              let fullURL = entry.fullUrl?.value?.url.absoluteString,
              let resource = entry.resource,
              isActiveOutput(resource) else {
            throw ExchangeIdentityError.entryKeyPriorityMismatch
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
        identifiers: [BusinessIdentifier]
    ) throws(ExchangeGraphError) {
        let writerCount = identifiers.filter { $0.role == .writerRecord }.count
        guard document.content.count == 1,
              identifiers.filter({ $0.role == .sourceRecord }).count == 1,
              identifiers.filter({ $0.role == .sourceOutput }).count == 1,
              identifiers.filter({ $0.role == .sourceArtifact }).count == 1,
              writerCount <= 1,
              identifiers.count == 3 + writerCount else {
            throw .ruleViolation(.recordingDocumentIdentity)
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
            let typed: [BusinessIdentifier]
            do {
                typed = try ExchangeIdentity.typedResourceIdentifiers(in: entry.resource)
            } catch {
                throw .ruleViolation(.recordingDocumentIdentity)
            }
            guard recordingDocumentIdentifiersAreValid(
                document,
                typed: typed,
                sourceDerivedOutputCount: sourceDerivedOutputCount
            ) else {
                throw .ruleViolation(.recordingDocumentIdentity)
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
            throw .ruleViolation(.transformProvenance)
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
        typed: [BusinessIdentifier],
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
        guard let businessIdentifier = try? BusinessIdentifier(identifier),
              businessIdentifier.role == nil else {
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
        guard hasExactLifecycleCoding(provenance, kind: .retraction) else {
            throw .ruleViolation(.lifecycleCoding)
        }
        _ = try exactSourceEntity(in: provenance)
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
                rule: .deviceProfile
            )
            try validateIdentifierRoles(in: resource, claim: claim, rule: .recordingDeviceDualIdentity)
            guard let key = try? entryKey(entry) else {
                throw .ruleViolation(.recordingDeviceDualIdentity)
            }
            let identifiers = (try? ExchangeIdentity.typedResourceIdentifiers(in: resource)) ?? []
            try validateDeviceIdentity(device, entryKey: key, identifiers: identifiers)
        default:
            throw .ruleViolation(.retractionNoClinicalCopy)
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
              retractionAssemblerIsDevice(assembler, entries: entries),
              !provenance.target.isEmpty else {
            throw .ruleViolation(.retractionNoClinicalCopy)
        }
        return provenance
    }

    private static func validateRetractionTargets(
        _ targets: [Reference]
    ) throws(ExchangeGraphError) {
        var logicalTargets: Set<RetractionTarget> = []
        for target in targets {
            let logicalTarget = try validatedRetractionTarget(target)
            guard logicalTargets.insert(logicalTarget).inserted else {
                throw .ruleViolation(.retractionRoleTargetType)
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
              let businessIdentifier = try? BusinessIdentifier(identifier) else {
            throw .ruleViolation(.retractionLogicalTarget)
        }
        guard ExchangeIdentity.isCanonicalOpaqueIdentifierValue(businessIdentifier.value) else {
            throw .ruleViolation(.retractionOpaqueTarget)
        }
        let roles = target.extension?.filter { $0.url == Canonicals.retractionTargetRole } ?? []
        guard roles.count == 1,
              case .code(let roleCode)? = roles.first?.value,
              let rawRole = roleCode.value?.string,
              let role = RetractionTargetRole(rawValue: rawRole) else {
            throw .ruleViolation(.retractionTargetRole)
        }
        do {
            return try RetractionTarget(
                identifier: businessIdentifier,
                resourceType: resourceType,
                role: role
            )
        } catch RetractionTargetError.identifierRoleMismatch,
                RetractionTargetError.resourceTypeMismatch {
            throw .ruleViolation(.retractionRoleTargetType)
        } catch {
            throw .ruleViolation(.retractionTargetRole)
        }
    }
}
