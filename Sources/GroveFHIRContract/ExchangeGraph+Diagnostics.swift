//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import ModelsR4


public enum ExchangeGraphError: Error, Equatable, Sendable {
    case notCollectionBundle
    case missingTimestamp
    case missingEventIdentifier
    case invalidEventIdentifier
    case eventIdentifierMismatch
    case missingProfile(String)
    case invalidEntries(String)
    case ruleViolation(ExchangeGraphRule)
    case contractViolation(ExchangeGraphDiagnostic)

    /// A machine-readable producer diagnostic when this failure corresponds to a normative rule.
    public var diagnostic: ExchangeGraphDiagnostic? {
        switch self {
        case .ruleViolation(let rule):
            rule.diagnostic
        case .contractViolation(let diagnostic):
            diagnostic
        default:
            nil
        }
    }
}


/// Exact structured producer diagnostic shared with the Grove conformance corpus.
public struct ExchangeGraphDiagnostic: Codable, Equatable, Hashable, Sendable {
    public enum Severity: String, Codable, Equatable, Hashable, Sendable {
        case error
    }

    public let code: String
    public let reason: String
    public let location: String
    public let severity: Severity

    public init(
        code: String,
        reason: String,
        location: String,
        severity: Severity = .error
    ) {
        self.code = code
        self.reason = reason
        self.location = location
        self.severity = severity
    }
}


/// Canonicals and terminology for active/retraction event graphs.
public enum GroveLifecycleContract {
    /// Profile required on active conversion Provenance resources.
    public static let conversionProvenanceProfile: FHIRPrimitive<Canonical> =
        "https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-conversion-provenance"
    /// Profile required on retraction assertion Bundles.
    public static let retractionBundleProfile: FHIRPrimitive<Canonical> =
        "https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-retraction-bundle"
    /// Profile required on retraction assertion Provenance resources.
    public static let retractionProvenanceProfile: FHIRPrimitive<Canonical> =
        "https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-retraction-provenance"
    /// Lifecycle activity code asserted by a retraction Provenance.
    public static let sourceRecordRetracted = "source-record-retracted"
}


/// Stable Grove producer-rule identifiers shared by the conformance corpus and SDKs.
public enum ExchangeGraphRule: String, Equatable, Sendable {
    case collectionHasRequestOrResponse = "mobile-exchange.collection-entry-operation"
    case entryNodeKey = "mobile-exchange.entry-node-key"
    case deterministicFullURL = "mobile-exchange.deterministic-full-url"
    case eventIdentity = "mobile-exchange.event-identity"
    case resolvedReference = "mobile-exchange.resolved-reference"
    case referenceShape = "mobile-exchange.reference-shape"
    case logicalPatientReference = "mobile-exchange.logical-patient-reference"
    case referenceTargetType = "mobile-exchange.reference-target-type"
    case referenceDeclaredType = "mobile-exchange.reference-declared-type"
    case entryResourceType = "mobile-exchange.entry-resource-type"
    case containedResourceProhibited = "mobile-exchange.contained-resource-prohibited"
    case entryNodeDigest = "mobile-exchange.entry-node-digest"
    case identitySystemRole = "mobile-exchange.identity-system-role"
    case sourceOutputRequired = "mobile-output.source-output-required"
    case semanticProfile = "mobile-output.semantic-profile"
    case adapterOnlyProfile = "mobile-output.adapter-only-profile"
    case documentProfile = "mobile-output.document-profile"
    case clinicalFHIRRepresentation = "healthkit-clinical.fhir-representation"
    case deviceProfile = "mobile-support.device-profile"
    case questionnaireResponseProfile = "mobile-support.questionnaire-response-profile"
    case supportConnected = "mobile-support.connected"
    case fixedQuantityUnit = "mobile-output.fixed-quantity-unit"
    case quantityValueDomain = "mobile-output.quantity-value-domain"
    case transformProvenance = "mobile-exchange.transform-provenance"
    case provenanceProfile = "mobile-exchange.provenance-profile"
    case lifecycleCoding = "mobile-exchange.lifecycle-coding"
    case logicalSourceEntity = "mobile-exchange.logical-source-entity"
    case singleSourceEntity = "mobile-exchange.single-source-entity"
    case recordingDeviceDualIdentity = "mobile-device.recording-device-dual-identity"
    case recordingDocumentIdentity = "sensor-recording-document.identity-and-content"
    case retractionLogicalTarget = "mobile-retraction.logical-target"
    case retractionTargetRole = "mobile-retraction.target-role"
    case retractionNativeRecordIdentifier = "mobile-retraction.native-record-identifier"
    case retractionRoleTargetType = "mobile-retraction.role-target-type"
    case retractionOpaqueTarget = "mobile-retraction.opaque-target"
    case retractionNoClinicalCopy = "mobile-retraction.no-clinical-copy"

    /// The corpus-authoritative diagnostic for this closed producer rule.
    public var diagnostic: ExchangeGraphDiagnostic {
        let reason: String
        let location: String
        switch self {
        case .entryNodeKey:
            reason = "Every Bundle entry must carry exactly one complete Grove exchange entry node key."
            location = "Bundle.entry[0]"
        case .deterministicFullURL:
            reason = "Bundle.entry.fullUrl must be the UUID version 5 value derived from its complete entry identifier."
            location = "Bundle.entry[1].fullUrl"
        case .resolvedReference:
            reason = "Every internal UUID URN reference must resolve to a Bundle entry fullUrl."
            location = "Bundle.entry[2].resource.subject.reference"
        case .fixedQuantityUnit:
            reason = "Every Quantity-valued catalog measurement uses the exact fixed system and code declared by its semantic profile contract."
            location = "Bundle.entry[2].resource.valueQuantity.code"
        case .quantityValueDomain:
            reason = "Every Quantity-valued catalog measurement stays within its reviewed representational minimum, "
                + "maximum, and integer-only domain without inventing a physiologic range."
            location = "Bundle.entry[2].resource.valueQuantity.value"
        case .eventIdentity:
            reason = "Bundle.identifier.value must be the canonical e0 producer UUID and positive sequence form."
            location = "Bundle.identifier.value"
        case .entryNodeDigest:
            reason = "An entry-node digest must be derived from the enclosing event identifier, role, and ordinal."
            location = "Bundle.entry[0].extension.valueIdentifier.value"
        case .identitySystemRole:
            reason = "Within one event graph, each Grove Identifier.system names exactly one Grove identifier role; "
                + "one namespace cannot change meaning between nodes."
            location = "Bundle"
        case .sourceOutputRequired:
            reason = "Every active clinical output must carry its exact typed source-output identity in addition to source-record identity."
            location = "Bundle.entry[2].resource.identifier"
        case .transformProvenance:
            reason = "An active event must contain exactly one transform Provenance and no retraction Provenance."
            location = "Bundle.entry"
        case .retractionLogicalTarget:
            reason = "A retraction target must be a typed logical Reference without a literal reference."
            location = "Provenance.target[0]"
        case .retractionTargetRole:
            reason = "Every retraction target must carry exactly one closed Grove target-role code."
            location = "Provenance.target[0].extension"
        case .retractionNativeRecordIdentifier:
            reason = "An optional retraction native record identifier carries one complete Identifier in the "
                + "adapter's own absolute native key space and never a Grove identifier-role coding."
            location = "Provenance.target[0].extension.valueIdentifier.type"
        case .retractionOpaqueTarget:
            reason = "A retraction target must use the exact canonical v0 HMAC identity previously emitted."
            location = "Provenance.target[0].identifier.value"
        case .retractionNoClinicalCopy:
            reason = "A retraction event contains its lifecycle Provenance and optional Device agents, never a copied or mutilated clinical resource."
            location = "Bundle.entry[0].resource"
        case .lifecycleCoding:
            reason = "A lifecycle Provenance must carry exactly one coding across the ISO transform "
                + "and Grove retraction lifecycle systems; translations from other systems remain open."
            location = "Provenance.activity.coding"
        case .semanticProfile:
            reason = "Every active Observation must directly claim one admitted Grove semantic profile shape; "
                + "an empty claim cannot bypass semantic validation."
            location = "Observation.meta.profile"
        case .referenceTargetType:
            reason = "Every governed Patient reference resolves to a Patient entry, not merely to any existing fullUrl."
            location = "Observation.subject.reference"
        case .referenceDeclaredType:
            reason = "When Reference.type is present it must equal the referenced entry's actual resourceType token."
            location = "Observation.subject.type"
        case .logicalSourceEntity:
            reason = "Lifecycle Provenance carries exactly one logical source-record Identifier entity and never a literal source Reference."
            location = "Provenance.entity[0].what"
        case .retractionRoleTargetType:
            reason = "Every retraction target role fixes its admitted resource type and Identifier role."
            location = "Provenance.target[0].type"
        case .singleSourceEntity:
            reason = "A lifecycle Provenance identifies exactly one source-record entity."
            location = "Provenance.entity"
        case .referenceShape:
            reason = "Each governed path has its declared singular or repeating shape and contains valid Reference objects "
                + "that are exclusively resolving-literal or identifier-only logical, never both."
            location = "Observation.subject"
        case .logicalPatientReference:
            reason = "An identifier-only logical Patient Reference carries the exact Patient type and one complete "
                + "absolute-system pseudonym Identifier without a Grove role or protocol-reserved system."
            location = "Observation.subject"
        case .entryResourceType:
            reason = "An active event admits only its closed output, supporting, and lifecycle resource type set."
            location = "Bundle.entry[0].resource.resourceType"
        case .adapterOnlyProfile:
            reason = "An adapter-only active output type must directly claim exactly its one admitted adapter profile."
            location = "Specimen.meta.profile"
        case .containedResourceProhibited:
            reason = "Mobile exchange events prohibit contained resources; every graph node must be an addressable Bundle entry."
            location = "Bundle.entry[2].resource.contained"
        case .documentProfile:
            reason = "Every active DocumentReference must directly claim exactly one admitted recording or clinical-document profile mode."
            location = "DocumentReference.meta.profile"
        case .clinicalFHIRRepresentation:
            reason = "A HealthKit clinical-record document carries the release-neutral "
                + "FHIR-resource format and one admitted versioned FHIR JSON media type."
            location = "DocumentReference.content[0]"
        case .deviceProfile:
            reason = "Every active Device must directly claim exactly one admitted Grove Device profile mode."
            location = "Device.meta.profile"
        case .provenanceProfile:
            reason = "The sole active lifecycle Provenance must directly claim exactly one admitted Mobile or adapter conversion profile."
            location = "Provenance.meta.profile"
        case .supportConnected:
            reason = "Every supporting resource must be connected to an output or the lifecycle Provenance."
            location = "Bundle.entry"
        case .collectionHasRequestOrResponse:
            reason = "A collection exchange entry never carries request, response, or search transaction metadata."
            location = "Bundle.entry"
        case .questionnaireResponseProfile:
            reason = "Every active QuestionnaireResponse must directly claim the Grove QuestionnaireResponse profile."
            location = "QuestionnaireResponse.meta.profile"
        case .recordingDeviceDualIdentity:
            reason = "A Device snapshot must match one exact Device profile and its required typed identities."
            location = "Device.identifier"
        case .recordingDocumentIdentity:
            reason = "A recording document carries exactly one source-record, source-output, and source-artifact identity and one content."
            location = "DocumentReference.identifier"
        }
        return ExchangeGraphDiagnostic(
            code: rawValue,
            reason: reason,
            location: location
        )
    }
}
