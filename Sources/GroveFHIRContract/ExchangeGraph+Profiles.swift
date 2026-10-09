//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import ModelsR4


extension ExchangeGraph {
    /// The catalog's Observation profile claims as the sets the check compares, built once.
    private enum ObservationProfileSets {
        static let exactModes = ProfileClaims.exactObservationProfileModes.map { Set(canonicalStrings($0)) }
        static let single = Set(canonicalStrings(ProfileClaims.singleObservationProfiles))
        static let shared = Set(canonicalStrings(ProfileClaims.sharedObservationProfiles))
        static let adapters = Set(canonicalStrings(ProfileClaims.observationAdapterProfiles))
    }

    /// The system of the Android package name a Health Connect data origin is identified by (health-connect guide).
    static let androidPackageNameSystem = "https://grovealliance.org/fhir/health-connect/NamingSystem/android-package-name"

    /// Every adapter conversion claim in the pinned catalog's `adapterConversionProvenanceClaims` order, with the adapter
    /// output profiles its Provenance governs. The generator lists the source-neutral profile first, which has no targets.
    static let adapterConversionClaims: [(provenanceProfile: String, outputProfiles: Set<String>)] =
        canonicalStrings(ProfileClaims.activeProvenanceProfiles).compactMap { profile in
            ProfileClaims.adapterProvenanceTargetProfiles[profile].map {
                (provenanceProfile: profile, outputProfiles: Set(canonicalStrings($0)))
            }
        }

    static func validateActiveProfileClaims(
        entries: [BundleEntry],
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        var activeProvenance: Provenance?
        for (index, entry) in entries.enumerated() {
            guard let resource = entry.resource else {
                throw .invalidEntries("Bundle entry has no resource")
            }
            if let provenance = try validateActiveProfileClaim(resource, entryIndex: index, document: document) {
                activeProvenance = provenance
            }
        }
        if let activeProvenance {
            try validateDataOriginAgent(activeProvenance)
        }
    }

    private static func validateActiveProfileClaim(
        _ resource: ResourceProxy,
        entryIndex: Int,
        document validationDocument: ValidationDocument
    ) throws(ExchangeGraphError) -> Provenance? {
        switch resource {
        case .observation(let observation):
            try validateObservationProfileClaim(observation)
            try validateFixedMeasurementQuantity(observation, entryIndex: entryIndex)
        case .documentReference(let document):
            let claim = try validateDirectProfileClaim(
                profiles: document.meta?.profile ?? [],
                modes: ProfileClaims.documentProfileModes,
                rule: .mobileOutputDocumentProfile
            )
            try validateIdentifierRoles(
                atEntry: entryIndex,
                document: validationDocument,
                claim: claim,
                additionallyAllowed: [.writerRecord],
                rule: .sensorRecordingDocumentIdentityAndContent
            )
            guard document.content.count == 1 else {
                throw .ruleViolation(.sensorRecordingDocumentIdentityAndContent)
            }
            try validateClinicalFHIRRepresentation(document, claim: claim)
            try validateRecordingFormat(document)
            try validateEmbeddedIntegrity(document)
        case .device(let device):
            let claim = try validateDirectProfileClaim(
                profiles: device.meta?.profile ?? [],
                modes: ProfileClaims.deviceProfileModes,
                rule: .mobileSupportDeviceProfile
            )
            try validateIdentifierRoles(
                atEntry: entryIndex,
                document: validationDocument,
                claim: claim,
                rule: .mobileDeviceRecordingDeviceDualIdentity
            )
        case .questionnaireResponse(let response):
            _ = try validateDirectProfileClaim(
                profiles: response.meta?.profile ?? [],
                modes: ProfileClaims.questionnaireResponseProfileModes,
                rule: .mobileSupportQuestionnaireResponseProfile
            )
        case .provenance(let provenance):
            try validateAdapterProvenanceClaim(at: entryIndex, document: validationDocument)
            try validateActiveProvenanceProfile(provenance)
            return provenance
        default:
            try validateAdapterOnlyOutputProfile(resource, entryIndex: entryIndex, document: validationDocument)
        }
        return nil
    }

    static func validateObservationProfileClaim(
        _ observation: Observation
    ) throws(ExchangeGraphError) {
        let profiles = canonicalStrings(observation.meta?.profile ?? [])
        let direct = Set(profiles)
        guard !profiles.isEmpty, direct.count == profiles.count else {
            throw .ruleViolation(.mobileOutputSemanticProfile)
        }
        if ObservationProfileSets.exactModes.contains(direct) {
            return
        }
        if profiles.count == 1, direct.isSubset(of: ObservationProfileSets.single) {
            return
        }
        let shared = direct.intersection(ObservationProfileSets.shared)
        let adapters = direct.intersection(ObservationProfileSets.adapters)
        guard shared.count == 1,
              direct == shared.union(adapters) else {
            throw .ruleViolation(.mobileOutputSemanticProfile)
        }
        guard let semanticProfile = shared.first else {
            throw .ruleViolation(.mobileOutputSemanticProfile)
        }
        if let requiredAdapter = ProfileClaims.providerOwnedSemanticAdapters[semanticProfile]?.value?.url.absoluteString {
            guard adapters == [requiredAdapter] else {
                throw .ruleViolation(.mobileOutputSemanticProfile)
            }
        } else if adapters.count > 1 {
            throw .ruleViolation(.mobileOutputSemanticProfile)
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
        atEntry index: Int,
        document: ValidationDocument,
        claim: DirectProfileClaim,
        additionallyAllowed: Set<GroveIdentifierRole> = [],
        rule: ExchangeGraphRule
    ) throws(ExchangeGraphError) {
        do {
            let identifiers = try document.typedResourceIdentifiers(at: index)
            let roles = identifiers.map(\.role)
            guard Set(identifiers).count == identifiers.count else {
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
            throw .ruleViolation(.healthkitClinicalFhirRepresentation)
        }
    }

    /// A Provenance claiming an adapter's conversion profile claims it alone, exactly as written: the kit refuses any
    /// other claim beside it without a rule (profiles.py, validate_adapter_conversion_provenance), so Grove reports
    /// `mobile-exchange.unclassified`, before the profile-count rule.
    static func validateAdapterProvenanceClaim(at index: Int, document: ValidationDocument) throws(ExchangeGraphError) {
        let profiles = try writtenProfiles(at: index, document: document)
        let claimed = adapterConversionClaims.filter { profiles.contains($0.provenanceProfile) }
        guard claimed.isEmpty || (claimed.count == 1 && profiles == [claimed[0].provenanceProfile]) else {
            throw .invalidEntries("An adapter conversion Provenance claims more than its adapter's profile")
        }
    }

    static func validateActiveProvenanceProfile(
        _ provenance: Provenance
    ) throws(ExchangeGraphError) {
        let profiles = canonicalStrings(provenance.meta?.profile ?? [])
        let admitted = Set(canonicalStrings(ProfileClaims.activeProvenanceProfiles))
        guard profiles.count == 1, admitted.contains(profiles[0]) else {
            throw .ruleViolation(.mobileExchangeProvenanceProfile)
        }
    }

    static func validateRetractionProvenanceProfile(
        _ provenance: Provenance
    ) throws(ExchangeGraphError) {
        guard canonicalStrings(provenance.meta?.profile ?? [])
            == canonicalStrings(ProfileClaims.retractionProvenanceProfiles) else {
            throw .ruleViolation(.mobileExchangeProvenanceProfile)
        }
    }

    /// `mobile-exchange.adapter-provenance-graph` as the pinned kit decides it (graphs.py). Per adapter claim, in catalog
    /// order, the entries claiming one of its output profiles are grouped by their one source-record identity. Each group
    /// needs the event's Provenance to claim that adapter's conversion profile (else `Bundle.entry`) and to target exactly
    /// the group (else `Provenance.target`); an adapter Provenance without a group fails at `Provenance.entity`.
    ///
    /// Runs last, where the kit runs it (exchange_bundle.py:521): the sole Provenance, the source marker, the targets and
    /// the source entity are already valid, so one set comparison stands for the kit's per-target branches. A port of the
    /// kit's checks at :518-520 goes before this call; a port of its checks at :614-776 goes after it.
    static func validateAdapterProvenanceGraph(
        _ provenance: Provenance,
        sourceEntity: RoledIdentifier,
        entries: [BundleEntry],
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        var profiles: [Set<String>] = []
        var governed: Set<String> = []
        for (index, entry) in entries.enumerated() {
            profiles.append(try directProfiles(at: index, document: document))
            if case .provenance? = entry.resource {
                governed = profiles[index]
            }
        }
        let targets = Set(provenance.target.compactMap { $0.reference?.value?.string })
        for claim in adapterConversionClaims {
            let governs = governed.contains(claim.provenanceProfile)
            let groups = try adapterOutputGroups(claim.outputProfiles, profiles: profiles, entries: entries, document: document)
            for group in groups {
                guard governs, group.source == sourceEntity else {
                    throw diagnostic(.mobileExchangeAdapterProvenanceGraph, location: "Bundle.entry")
                }
                guard targets == group.fullURLs else {
                    throw diagnostic(.mobileExchangeAdapterProvenanceGraph, location: "Provenance.target")
                }
            }
            if governs, !groups.contains(where: { $0.source == sourceEntity }) {
                throw diagnostic(.mobileExchangeAdapterProvenanceGraph, location: "Provenance.entity")
            }
        }
    }

    /// The entries claiming any of `outputProfiles`, grouped by their one typed source-record identity, in entry order.
    private static func adapterOutputGroups(
        _ outputProfiles: Set<String>,
        profiles: [Set<String>],
        entries: [BundleEntry],
        document: ValidationDocument
    ) throws(ExchangeGraphError) -> [(source: RoledIdentifier, fullURLs: Set<String>)] {
        var groups: [(source: RoledIdentifier, fullURLs: Set<String>)] = []
        for (index, entry) in entries.enumerated() where !profiles[index].isDisjoint(with: outputProfiles) {
            let records = ((try? document.typedResourceIdentifiers(at: index)) ?? []).filter { $0.role == .sourceRecord }
            guard records.count == 1, let fullURL = entry.fullUrl?.value?.url.absoluteString else {
                // The kit fails this without a rule (graphs.py:30-38), so it reports mobile-exchange.unclassified.
                throw .invalidEntries("An adapter-profiled entry carries no single typed source-record identity")
            }
            if let existing = groups.firstIndex(where: { $0.source == records[0] }) {
                groups[existing].fullURLs.insert(fullURL)
            } else {
                groups.append((source: records[0], fullURLs: [fullURL]))
            }
        }
        return groups
    }

    /// The entry resource's `meta.profile` exactly as written, read from the parsed Bundle as the kit reads it.
    private static func directProfiles(at index: Int, document: ValidationDocument) throws(ExchangeGraphError) -> Set<String> {
        Set(try writtenProfiles(at: index, document: document))
    }

    /// The entry resource's `meta.profile` exactly as written and in order, read from the parsed Bundle.
    private static func writtenProfiles(at index: Int, document: ValidationDocument) throws(ExchangeGraphError) -> [String] {
        do {
            let object = try document.resourceObject(at: index) as? [String: Any]
            return (object?["meta"] as? [String: Any])?["profile"] as? [String] ?? []
        } catch {
            throw .invalidEntries(String(reflecting: type(of: error)))
        }
    }

    /// A Health Connect conversion names its data origin as the source entity's one agent: typed enterer and nothing
    /// else, an identifier-only Device reference to a non-blank Android package name. Each fault is located where
    /// the kit locates it (profiles.py:663-707): the agent list, its `who`, or that reference's identifier.
    static func validateDataOriginAgent(_ provenance: Provenance) throws(ExchangeGraphError) {
        guard provenance.meta?.profile?.contains(Profile.healthConnectConversionProvenance) == true else {
            return
        }
        let location = "Provenance.entity[0].agent"
        guard let agents = provenance.entity?.first?.agent, agents.count == 1, let agent = agents.first else {
            throw diagnostic(.healthConnectProvenanceDataOriginAgent, location: location)
        }
        let participantCodes = (agent.type?.coding ?? [])
            .filter { $0.system?.value?.url.absoluteString == participantSystem }
            .map { $0.code?.value?.string }
        guard participantCodes == ["enterer"],
              agent.who.reference == nil,
              agent.who.type?.value?.url.absoluteString == ResourceType.device.rawValue else {
            throw diagnostic(.healthConnectProvenanceDataOriginAgent, location: location + "[0].who")
        }
        guard agent.who.identifier?.system?.value?.url.absoluteString == androidPackageNameSystem,
              agent.who.identifier?.value?.value?.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw diagnostic(.healthConnectProvenanceDataOriginAgent, location: location + "[0].who.identifier")
        }
    }

    /// The attachment's format is a registered recording format and its content type one the registry names.
    static func validateRecordingFormat(_ document: DocumentReference) throws(ExchangeGraphError) {
        guard let content = document.content.first, let format = content.format else {
            return
        }
        let contentType = content.attachment.contentType?.value?.string
        guard format.version == nil,
              format.system?.value?.url.absoluteString == RegisteredRecordingFormat.codeSystem,
              let code = format.code?.value?.string,
              let registered = RegisteredRecordingFormat(rawValue: code),
              contentType.map({ registered.registeredContentTypes.contains($0) }) ?? true else {
            throw diagnostic(.sensorRecordingDocumentFormat, location: "DocumentReference.content[0].format.code")
        }
    }

    /// An embedded attachment's stated size and SHA-1 hash are those of its bytes.
    static func validateEmbeddedIntegrity(_ document: DocumentReference) throws(ExchangeGraphError) {
        guard let attachment = document.content.first?.attachment,
              let base64 = attachment.data?.value?.dataString,
              let data = Data(base64Encoded: base64) else {
            return
        }
        if let size = attachment.size?.value?.integer, Int(size) != data.count {
            throw diagnostic(.sensorRecordingDocumentEmbeddedIntegrity, location: "DocumentReference.content[0].attachment.size")
        }
        if let hash = attachment.hash?.value?.dataString,
           Data(base64Encoded: hash) != Data(Insecure.SHA1.hash(data: data)) {
            throw diagnostic(.sensorRecordingDocumentEmbeddedIntegrity, location: "DocumentReference.content[0].attachment.hash")
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
            throw .contractViolation(ProducerDiagnostic(
                code: ExchangeGraphRule.mobileOutputFixedQuantityUnit.rawValue,
                reason: ExchangeGraphRule.mobileOutputFixedQuantityUnit.reason,
                location: "Bundle.entry[\(entryIndex)].resource.valueQuantity.code"
            ))
        }
        if let domain = contract.valueDomain,
           let decimal = quantity.value?.value?.decimal {
            if !domain.contains(decimal) {
                throw .contractViolation(ProducerDiagnostic(
                    code: ExchangeGraphRule.mobileOutputQuantityValueDomain.rawValue,
                    reason: ExchangeGraphRule.mobileOutputQuantityValueDomain.reason,
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
