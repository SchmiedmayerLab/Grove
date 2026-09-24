//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


public enum ExchangeGraphError: Error, Equatable, Sendable {
    case notCollectionBundle
    case missingTimestamp
    case missingEventIdentifier
    case invalidEventIdentifier
    case eventIdentifierMismatch
    case invalidEntries(String)
    case ruleViolation(ExchangeGraphRule)
    case contractViolation(ProducerDiagnostic)

    /// The machine-readable producer diagnostic this failure reports.
    ///
    /// A failure the registry does not name reports the registered unclassified diagnostic rather
    /// than borrowing another rule's code.
    public var diagnostic: ProducerDiagnostic {
        switch self {
        case .ruleViolation(let rule):
            rule.diagnostic
        case .contractViolation(let diagnostic):
            diagnostic
        case .notCollectionBundle, .missingTimestamp, .missingEventIdentifier, .invalidEventIdentifier,
             .eventIdentifierMismatch, .invalidEntries:
            ExchangeGraphRule.mobileExchangeUnclassified.diagnostic
        }
    }
}


extension ExchangeGraphRule {
    /// The diagnostic this rule reports at the location a Swift producer checks it.
    package var diagnostic: ProducerDiagnostic {
        diagnostic(at: location)
    }

    /// Where the Swift producer checks each rule it raises; the conformance corpus fixes these paths.
    package var location: String {
        switch self {
        case .mobileExchangeEntryNodeKey: "Bundle.entry[0]"
        case .mobileExchangeDeterministicFullUrl: "Bundle.entry[1].fullUrl"
        case .mobileExchangeResolvedReference: "Bundle.entry[2].resource.subject.reference"
        case .mobileOutputFixedQuantityUnit: "Bundle.entry[2].resource.valueQuantity.code"
        case .mobileOutputQuantityValueDomain: "Bundle.entry[2].resource.valueQuantity.value"
        case .mobileExchangeEventIdentity: "Bundle.identifier.value"
        case .mobileExchangeEntryNodeDigest, .mobileExchangeEntryNodeOrdinal: "Bundle.entry[0].extension.valueIdentifier.value"
        case .mobileOutputSourceOutputRequired: "Bundle.entry[2].resource.identifier"
        case .mobileExchangeTransformProvenance, .mobileSupportConnected, .mobileExchangeCollectionEntryOperation,
             .mobileExchangeEntryRequired, .mobileExchangeOutputRequired, .mobileRetractionProvenance,
             .mobileSupportStudyContext: "Bundle.entry"
        case .mobileRetractionLogicalTarget: "Provenance.target[0]"
        case .mobileRetractionTargetRole: "Provenance.target[0].extension"
        case .mobileRetractionNativeRecordIdentifier: "Provenance.target[0].extension.valueIdentifier.type"
        case .mobileRetractionOpaqueTarget: "Provenance.target[0].identifier.value"
        case .mobileRetractionNoClinicalCopy: "Bundle.entry[0].resource"
        case .mobileExchangeLifecycleCoding: "Provenance.activity.coding"
        case .mobileOutputSemanticProfile: "Observation.meta.profile"
        case .mobileExchangeReferenceTargetType: "Observation.subject.reference"
        case .mobileExchangeReferenceDeclaredType: "Observation.subject.type"
        case .mobileExchangeLogicalSourceEntity: "Provenance.entity[0].what"
        case .mobileRetractionRoleTargetType: "Provenance.target[0].type"
        case .mobileExchangeSingleSourceEntity: "Provenance.entity"
        case .mobileExchangeReferenceShape, .mobileExchangeLogicalPatientReference: "Observation.subject"
        case .mobileExchangeEntryResourceType: "Bundle.entry[0].resource.resourceType"
        case .mobileOutputAdapterOnlyProfile: "Specimen.meta.profile"
        case .mobileExchangeContainedResourceProhibited: "Bundle.entry[2].resource.contained"
        case .mobileOutputDocumentProfile: "DocumentReference.meta.profile"
        case .healthkitClinicalFhirRepresentation: "DocumentReference.content[0]"
        case .mobileSupportDeviceProfile: "Device.meta.profile"
        case .mobileExchangeProvenanceProfile: "Provenance.meta.profile"
        case .mobileSupportQuestionnaireResponseProfile: "QuestionnaireResponse.meta.profile"
        case .mobileDeviceRecordingDeviceDualIdentity: "Device.identifier"
        case .sensorRecordingDocumentIdentityAndContent: "DocumentReference.identifier"
        case .mobileExchangeOpaqueResourceIdentity: "Bundle.entry[0].resource.identifier"
        case .mobileOmissionRecordingDevice: "Observation.device"
        case .mobileOmissionSourceOffset: "Observation.effective"
        case .mobileOmissionUnmodeledMetadata: "Observation.extension"
        default: "Bundle"
        }
    }

    /// The diagnostic this rule reports at an element only the finding knows.
    package func diagnostic(at location: String) -> ProducerDiagnostic {
        ProducerDiagnostic(code: rawValue, reason: reason, location: location, severity: severity)
    }
}
