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
    static func validateActiveProfileClaims(
        entries: [BundleEntry]
    ) throws(ExchangeGraphError) {
        var activeProvenance: Provenance?
        for (index, entry) in entries.enumerated() {
            guard let resource = entry.resource else {
                throw .invalidEntries("Bundle entry has no resource")
            }
            if let provenance = try validateActiveProfileClaim(resource, entryIndex: index) {
                activeProvenance = provenance
            }
        }
        if let activeProvenance {
            try validateAdapterProvenanceTargets(activeProvenance, entries: entries)
        }
    }

    private static func validateActiveProfileClaim(
        _ resource: ResourceProxy,
        entryIndex: Int
    ) throws(ExchangeGraphError) -> Provenance? {
        switch resource {
        case .observation(let observation):
            try validateObservationProfileClaim(observation)
            try validateFixedMeasurementQuantity(observation, entryIndex: entryIndex)
        case .documentReference(let document):
            let claim = try validateDirectProfileClaim(
                profiles: document.meta?.profile ?? [],
                modes: ProfileClaims.documentProfileModes,
                rule: .documentProfile
            )
            try validateIdentifierRoles(
                in: resource,
                claim: claim,
                additionallyAllowed: [.writerRecord],
                rule: .recordingDocumentIdentity
            )
            guard document.content.count == 1 else {
                throw .ruleViolation(.recordingDocumentIdentity)
            }
            try validateClinicalFHIRRepresentation(document, claim: claim)
        case .device(let device):
            let claim = try validateDirectProfileClaim(
                profiles: device.meta?.profile ?? [],
                modes: ProfileClaims.deviceProfileModes,
                rule: .deviceProfile
            )
            try validateIdentifierRoles(in: resource, claim: claim, rule: .recordingDeviceDualIdentity)
        case .questionnaireResponse(let response):
            _ = try validateDirectProfileClaim(
                profiles: response.meta?.profile ?? [],
                modes: ProfileClaims.questionnaireResponseProfileModes,
                rule: .questionnaireResponseProfile
            )
        case .provenance(let provenance):
            try validateActiveProvenanceProfile(provenance)
            return provenance
        default:
            try validateAdapterOnlyOutputProfile(resource)
        }
        return nil
    }

    static func validateObservationProfileClaim(
        _ observation: Observation
    ) throws(ExchangeGraphError) {
        let profiles = canonicalStrings(observation.meta?.profile ?? [])
        let direct = Set(profiles)
        guard !profiles.isEmpty, direct.count == profiles.count else {
            throw .ruleViolation(.semanticProfile)
        }
        let exactModes = ProfileClaims.exactObservationProfileModes.map {
            Set(canonicalStrings($0))
        }
        if exactModes.contains(direct) {
            return
        }
        let singleProfiles = Set(canonicalStrings(ProfileClaims.singleObservationProfiles))
        if profiles.count == 1, direct.isSubset(of: singleProfiles) {
            return
        }
        let sharedProfiles = Set(canonicalStrings(ProfileClaims.sharedObservationProfiles))
        let adapterProfiles = Set(canonicalStrings(ProfileClaims.observationAdapterProfiles))
        let shared = direct.intersection(sharedProfiles)
        let adapters = direct.intersection(adapterProfiles)
        guard shared.count == 1,
              direct == shared.union(adapters) else {
            throw .ruleViolation(.semanticProfile)
        }
        guard let semanticProfile = shared.first else {
            throw .ruleViolation(.semanticProfile)
        }
        if let requiredAdapter = ProfileClaims.providerOwnedSemanticAdapters[semanticProfile]?.value?.url.absoluteString {
            guard adapters == [requiredAdapter] else {
                throw .ruleViolation(.semanticProfile)
            }
        } else if adapters.count > 1 {
            throw .ruleViolation(.semanticProfile)
        }
    }

    @discardableResult
    static func validateDirectProfileClaim(
        profiles: [FHIRPrimitive<Canonical>],
        modes: [DirectProfileClaim],
        rule: ExchangeGraphRule
    ) throws(ExchangeGraphError) -> DirectProfileClaim {
        let profileStrings = canonicalStrings(profiles)
        let direct = Set(profileStrings)
        let matches = modes.filter { mode in
            let expected = Set(canonicalStrings(mode.profiles))
            return profileStrings.count == direct.count
                && direct.count == expected.count
                && direct == expected
        }
        guard matches.count == 1, let match = matches.first else {
            throw .ruleViolation(rule)
        }
        return match
    }

    static func validateIdentifierRoles(
        in resource: ResourceProxy,
        claim: DirectProfileClaim,
        additionallyAllowed: Set<GroveIdentifierRole> = [],
        rule: ExchangeGraphRule
    ) throws(ExchangeGraphError) {
        do {
            let identifiers = try ExchangeIdentity.typedResourceIdentifiers(in: resource)
            let roles = identifiers.compactMap(\.role)
            guard roles.count == identifiers.count,
                  Set(identifiers).count == identifiers.count else {
                throw ExchangeGraphError.ruleViolation(rule)
            }
            let required = Set(claim.requiredIdentifierRoles.compactMap(GroveIdentifierRole.init))
            guard required.count == claim.requiredIdentifierRoles.count else {
                throw ExchangeGraphError.invalidEntries("Generated identifier role claim is invalid")
            }
            let allowed = required.union(additionallyAllowed)
            guard required.allSatisfy({ requiredRole in
                roles.filter { $0 == requiredRole }.count == 1
            }),
            roles.allSatisfy(allowed.contains),
            additionallyAllowed.allSatisfy({ optionalRole in
                roles.filter { $0 == optionalRole }.count <= 1
            }) else {
                throw ExchangeGraphError.ruleViolation(rule)
            }
        } catch let error as ExchangeGraphError {
            throw error
        } catch {
            throw .ruleViolation(rule)
        }
    }

    static func validateClinicalFHIRRepresentation(
        _ document: DocumentReference,
        claim: DirectProfileClaim
    ) throws(ExchangeGraphError) {
        guard canonicalStrings(claim.profiles)
            == [HealthKitContract.clinicalRecordProfile.value?.url.absoluteString].compactMap(\.self)
        else {
            return
        }
        guard let content = document.content.first,
              content.format?.code?.value?.string
                  == HealthKitContract.clinicalFHIRPayloadFormatCode,
              let contentType = content.attachment.contentType?.value?.string,
              HealthKitContract.clinicalFHIRContentTypeByRelease.values.contains(contentType) else {
            throw .ruleViolation(.clinicalFHIRRepresentation)
        }
    }

    static func validateActiveProvenanceProfile(
        _ provenance: Provenance
    ) throws(ExchangeGraphError) {
        let profiles = canonicalStrings(provenance.meta?.profile ?? [])
        let admitted = Set(canonicalStrings(ProfileClaims.activeProvenanceProfiles))
        guard profiles.count == 1, admitted.contains(profiles[0]) else {
            throw .ruleViolation(.provenanceProfile)
        }
    }

    static func validateRetractionProvenanceProfile(
        _ provenance: Provenance
    ) throws(ExchangeGraphError) {
        guard canonicalStrings(provenance.meta?.profile ?? [])
            == canonicalStrings(ProfileClaims.retractionProvenanceProfiles) else {
            throw .ruleViolation(.provenanceProfile)
        }
    }

    static func validateAdapterProvenanceTargets(
        _ provenance: Provenance,
        entries: [BundleEntry]
    ) throws(ExchangeGraphError) {
        guard let provenanceProfile = canonicalStrings(provenance.meta?.profile ?? []).first,
              let admittedProfiles = ProfileClaims.adapterProvenanceTargetProfiles[provenanceProfile]
        else {
            return
        }
        let admitted = Set(canonicalStrings(admittedProfiles))
        let resourcePairs: [(String, ResourceProxy)] = entries.compactMap { entry in
            guard let fullURL = entry.fullUrl?.value?.url.absoluteString,
                  let resource = entry.resource else {
                return nil
            }
            return (fullURL, resource)
        }
        let resourcesByFullURL = [String: ResourceProxy](
            uniqueKeysWithValues: resourcePairs
        )
        for target in provenance.target {
            guard let reference = target.reference?.value?.string,
                  let resource = resourcesByFullURL[reference],
                  !admitted.isDisjoint(with: Set(resourceProfiles(resource))) else {
                throw .ruleViolation(.provenanceProfile)
            }
        }
    }

    static func validateFixedMeasurementQuantity(
        _ observation: Observation,
        entryIndex: Int
    ) throws(ExchangeGraphError) {
        let claims = canonicalStrings(observation.meta?.profile ?? []).compactMap {
            ProfileClaims.fixedMeasurementQuantities[$0]
        }
        guard claims.count == 1,
              let claim = claims.first,
              case .quantity(let quantity)? = observation.value else {
            return
        }
        let contract = claim.quantity
        guard quantity.system?.value?.url.absoluteString == contract.system,
              quantity.code?.value?.string == contract.code else {
            throw .contractViolation(ExchangeGraphDiagnostic(
                code: ExchangeGraphRule.fixedQuantityUnit.rawValue,
                reason: ExchangeGraphRule.fixedQuantityUnit.diagnostic.reason,
                location: "Bundle.entry[\(entryIndex)].resource.valueQuantity.code"
            ))
        }
        if let domain = contract.valueDomain,
           let decimal = quantity.value?.value?.decimal {
            if !domain.contains(decimal) {
                throw .contractViolation(ExchangeGraphDiagnostic(
                    code: ExchangeGraphRule.quantityValueDomain.rawValue,
                    reason: ExchangeGraphRule.quantityValueDomain.diagnostic.reason,
                    location: "Bundle.entry[\(entryIndex)].resource.valueQuantity.value"
                ))
            }
        }
    }

    static func canonicalStrings(
        _ profiles: [FHIRPrimitive<Canonical>]
    ) -> [String] {
        profiles.compactMap { $0.value?.url.absoluteString }
    }

    static func resourceProfiles(_ resource: ResourceProxy) -> [String] {
        switch resource {
        case .observation(let resource): canonicalStrings(resource.meta?.profile ?? [])
        case .documentReference(let resource): canonicalStrings(resource.meta?.profile ?? [])
        case .specimen(let resource): canonicalStrings(resource.meta?.profile ?? [])
        case .visionPrescription(let resource): canonicalStrings(resource.meta?.profile ?? [])
        case .medicationAdministration(let resource): canonicalStrings(resource.meta?.profile ?? [])
        case .medicationStatement(let resource): canonicalStrings(resource.meta?.profile ?? [])
        default: []
        }
    }
}
