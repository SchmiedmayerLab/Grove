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
    enum LifecycleKind {
        case active
        case retraction
    }

    struct ReferenceResolutionContext {
        let bundleResourceTypes: [String: String]

        func resourceType(for literal: String) -> String? {
            bundleResourceTypes[literal]
        }
    }

    static let transformSystem = "http://terminology.hl7.org/CodeSystem/iso-21089-lifecycle"
    static let participantSystem =
        "http://terminology.hl7.org/CodeSystem/provenance-participant-type"
    static let governedExtensionTargets: [String: Set<ResourceType>] = [
        "http://hl7.org/fhir/StructureDefinition/observation-gatewayDevice": [.device],
        "http://hl7.org/fhir/StructureDefinition/workflow-researchStudy": [.researchStudy]
    ]

    static func validateGovernedReferenceTargets(
        entries: [BundleEntry]
    ) throws(ExchangeGraphError) {
        var resourceTypesByFullURL: [String: String] = [:]
        for entry in entries {
            if let fullURL = entry.fullUrl?.value?.url.absoluteString,
               let resource = entry.resource {
                resourceTypesByFullURL[fullURL] = resource.resourceType
            }
        }
        let context = ReferenceResolutionContext(bundleResourceTypes: resourceTypesByFullURL)
        for entry in entries {
            try validateGovernedReferences(in: entry.resource, context: context)
            try validateGovernedExtensions(in: entry.resource, context: context)
        }
    }

    private static func validateGovernedReferences(
        in resource: ResourceProxy?,
        context: ReferenceResolutionContext
    ) throws(ExchangeGraphError) {
        switch resource {
        case .observation(let observation):
            try validateObservationReferences(observation, context: context)
        case .documentReference(let document):
            try validateReference(document.subject, expected: [.patient], context: context)
        case .visionPrescription(let prescription):
            try validateReference(prescription.patient, expected: [.patient], context: context)
        case .medicationAdministration(let administration):
            try validateReference(administration.subject, expected: [.patient], context: context)
            try validateReferences(administration.device ?? [], expected: [.device], context: context)
        case .medicationStatement(let statement):
            try validateReference(statement.subject, expected: [.patient], context: context)
        case .specimen(let specimen):
            try validateReference(specimen.subject, expected: [.patient], context: context)
            try validateReferences(specimen.parent ?? [], expected: [.specimen], context: context)
        case .device(let device):
            try validateReference(device.parent, expected: [.device], context: context)
            try validateReference(device.patient, expected: [.patient], context: context)
        case .researchSubject(let subject):
            try validateReference(subject.individual, expected: [.patient], context: context)
            try validateReference(subject.study, expected: [.researchStudy], context: context)
        case .researchStudy(let study):
            try validateReferences(study.`protocol` ?? [], expected: [.planDefinition], context: context)
        default:
            break
        }
    }

    private static func validateObservationReferences(
        _ observation: Observation,
        context: ReferenceResolutionContext
    ) throws(ExchangeGraphError) {
        try validateReference(observation.subject, expected: [.patient], context: context)
        try validateReference(observation.device, expected: [.device], context: context)
        try validateReferences(observation.hasMember ?? [], expected: [.observation], context: context)
        try validateReferences(
            observation.derivedFrom ?? [],
            expected: [.documentReference, .observation, .questionnaireResponse],
            context: context
        )
        try validateReferences(observation.focus ?? [], expected: [.location], context: context)
        try validateReference(observation.specimen, expected: [.specimen], context: context)
    }

    static func validateReferences(
        _ references: [Reference],
        expected: Set<ResourceType>,
        context: ReferenceResolutionContext
    ) throws(ExchangeGraphError) {
        for reference in references {
            try validateReference(reference, expected: expected, context: context)
        }
    }

    static func validateReference(
        _ reference: Reference?,
        expected: Set<ResourceType>,
        context: ReferenceResolutionContext
    ) throws(ExchangeGraphError) {
        guard let reference else {
            return
        }
        let expectedTokens = Set(expected.map(\.rawValue))
        let literal = reference.reference?.value?.string
        let identifier = reference.identifier
        guard (literal != nil) != (identifier != nil) else {
            throw .ruleViolation(.referenceShape)
        }
        if let literal {
            guard reference.identifier == nil else {
                throw .ruleViolation(.referenceShape)
            }
            guard !literal.hasPrefix("#") else {
                throw .ruleViolation(.containedResourceProhibited)
            }
            guard let actualType = context.resourceType(for: literal) else {
                throw .ruleViolation(.resolvedReference)
            }
            guard expectedTokens.contains(actualType) else {
                throw .ruleViolation(.referenceTargetType)
            }
            if let declaredType = reference.type?.value?.url.absoluteString,
               declaredType != actualType {
                throw .ruleViolation(.referenceDeclaredType)
            }
            return
        }
        guard reference.reference == nil, let identifier else {
            throw .ruleViolation(.referenceShape)
        }
        let logicalPatient = expected == [.patient]
        guard let declaredType = reference.type?.value?.url.absoluteString,
              expectedTokens.contains(declaredType),
              (try? BusinessIdentifier(identifier)) != nil else {
            throw .ruleViolation(logicalPatient ? .logicalPatientReference : .referenceShape)
        }
    }

    static func validateGovernedExtensions(
        in resource: ResourceProxy?,
        context: ReferenceResolutionContext
    ) throws(ExchangeGraphError) {
        guard let resource else {
            return
        }
        do {
            let data = try JSONEncoder().encode(resource)
            let object = try JSONSerialization.jsonObject(with: data)
            try validateGovernedExtensions(in: object, context: context)
        } catch let error as ExchangeGraphError {
            throw error
        } catch {
            throw .ruleViolation(.referenceTargetType)
        }
    }

    static func validateGovernedExtensions(
        in value: Any,
        context: ReferenceResolutionContext
    ) throws(ExchangeGraphError) {
        if let object = value as? [String: Any] {
            if let url = object["url"] as? String,
               let expected = governedExtensionTargets[url] {
                guard let rawReference = object["valueReference"] as? [String: Any] else {
                    throw .ruleViolation(.referenceShape)
                }
                let reference: Reference
                do {
                    let data = try JSONSerialization.data(withJSONObject: rawReference)
                    reference = try JSONDecoder().decode(Reference.self, from: data)
                } catch {
                    throw .ruleViolation(.referenceTargetType)
                }
                try validateReference(reference, expected: expected, context: context)
            }
            for child in object.values {
                try validateGovernedExtensions(in: child, context: context)
            }
        } else if let array = value as? [Any] {
            for child in array {
                try validateGovernedExtensions(in: child, context: context)
            }
        }
    }

    static func hasExactLifecycleCoding(
        _ provenance: Provenance,
        kind: LifecycleKind
    ) -> Bool {
        let codings = provenance.activity?.coding ?? []
        let iso = codings.filter { $0.system?.value?.url.absoluteString == transformSystem }
        let grove = codings.filter {
            $0.system?.value?.url.absoluteString
                == Canonicals.lifecycleEventCodeSystem.value?.url.absoluteString
        }
        switch kind {
        case .active:
            return iso.count == 1
                && iso[0].code?.value?.string == "transform"
                && grove.isEmpty
        case .retraction:
            return grove.count == 1
                && grove[0].code?.value?.string == GroveLifecycleContract.sourceRecordRetracted
                && iso.isEmpty
        }
    }

    static func hasRequiredTimes(_ provenance: Provenance) -> Bool {
        guard provenance.recorded.value != nil else {
            return false
        }
        switch provenance.occurred {
        case .dateTime(let dateTime):
            return dateTime.value != nil
        case .period(let period):
            return period.start?.value != nil || period.end?.value != nil
        case nil:
            return false
        }
    }

    static func exactAssembler(in provenance: Provenance) -> ProvenanceAgent? {
        let assemblers = provenance.agent.filter { agent in
            let participantCodings = agent.type?.coding?.filter {
                $0.system?.value?.url.absoluteString == participantSystem
            } ?? []
            return participantCodings.count == 1
                && participantCodings[0].code?.value?.string == "assembler"
        }
        guard assemblers.count == 1 else {
            return nil
        }
        return assemblers[0]
    }

    static func activeAssemblerResolves(
        _ assembler: ProvenanceAgent,
        entries: [BundleEntry]
    ) -> Bool {
        guard assembler.who.identifier == nil,
              let reference = assembler.who.reference?.value?.string,
              let entry = entries.first(where: {
                  $0.fullUrl?.value?.url.absoluteString == reference
              }),
              case .device(let device)? = entry.resource else {
            return false
        }
        return device.meta?.profile?.contains(Profile.groveApplicationDevice) == true
            || device.meta?.profile?.contains(HealthKitContract.applicationDeviceProfile) == true
    }

    static func retractionAssemblerIsDevice(
        _ assembler: ProvenanceAgent,
        entries: [BundleEntry]
    ) -> Bool {
        if assembler.who.reference != nil {
            return activeAssemblerResolves(assembler, entries: entries)
        }
        guard let identifier = assembler.who.identifier,
              assembler.who.type?.value?.url.absoluteString == ResourceType.device.rawValue,
              let businessIdentifier = try? BusinessIdentifier(identifier),
              businessIdentifier.role == .deviceSnapshot,
              ExchangeIdentity.isCanonicalOpaqueIdentifierValue(businessIdentifier.value) else {
            return false
        }
        return true
    }

    static func exactSourceEntity(
        in provenance: Provenance
    ) throws(ExchangeGraphError) -> BusinessIdentifier {
        guard provenance.entity?.count == 1,
              let entity = provenance.entity?.first else {
            throw .ruleViolation(.singleSourceEntity)
        }
        guard entity.role.value == .source,
              entity.what.reference == nil,
              let identifier = entity.what.identifier,
              let businessIdentifier = try? BusinessIdentifier(identifier),
              businessIdentifier.role == .sourceRecord,
              ExchangeIdentity.isCanonicalOpaqueIdentifierValue(businessIdentifier.value) else {
            throw .ruleViolation(.logicalSourceEntity)
        }
        return businessIdentifier
    }
}
