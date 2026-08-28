//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The lifecycle builder mirrors the normative FHIR graph and keeps its target/reference shape visible.
// swiftlint:disable file_types_order function_body_length multiline_literal_brackets type_contents_order

public import Foundation
public import ModelsR4


/// The role a prior logical output played in the source event now being retracted.
public enum RetractionTargetRole: String, CaseIterable, Hashable, Sendable {
    case primaryOutput = "primary-output"
    case sourceArtifact = "source-artifact"
    case childOutput = "child-output"
    case specimen
    case deviceSnapshot = "device-snapshot"
}


/// One complete logical target of a retraction assertion.
public struct RetractionTarget: Hashable, Sendable {
    public let identifier: BusinessIdentifier
    public let resourceType: ResourceType
    public let role: RetractionTargetRole

    public init(
        identifier: BusinessIdentifier,
        resourceType: ResourceType,
        role: RetractionTargetRole
    ) throws {
        let expectedIdentifierRole: GroveIdentifierRole = switch role {
        case .primaryOutput, .sourceArtifact, .childOutput, .specimen:
            .sourceOutput
        case .deviceSnapshot:
            .deviceSnapshot
        }
        guard identifier.role == expectedIdentifierRole else {
            throw RetractionTargetError.identifierRoleMismatch(
                targetRole: role,
                identifierRole: identifier.role
            )
        }
        let allowedResourceTypes: Set<ResourceType> = switch role {
        case .primaryOutput:
            [.observation, .visionPrescription, .medicationAdministration, .medicationStatement]
        case .sourceArtifact:
            [.documentReference]
        case .childOutput:
            [.observation]
        case .specimen:
            [.specimen]
        case .deviceSnapshot:
            [.device]
        }
        guard allowedResourceTypes.contains(resourceType) else {
            throw RetractionTargetError.resourceTypeMismatch(role: role, resourceType: resourceType)
        }
        self.identifier = identifier
        self.resourceType = resourceType
        self.role = role
    }

    var reference: Reference {
        Reference(
            extension: [Extension(
                url: Canonicals.retractionTargetRole,
                value: .code(role.rawValue.asFHIRStringPrimitive())
            )],
            identifier: identifier.fhirIdentifier,
            type: FHIRPrimitive(FHIRURI(stringLiteral: resourceType.rawValue))
        )
    }
}


public enum RetractionTargetError: Error, Equatable, Sendable {
    case identifierRoleMismatch(
        targetRole: RetractionTargetRole,
        identifierRole: GroveIdentifierRole?
    )
    case resourceTypeMismatch(role: RetractionTargetRole, resourceType: ResourceType)
}


/// Explicit inputs for one retraction assertion.
public struct RetractionEventContext: Sendable {
    public let eventIdentifier: ExchangeEventIdentifier
    public let entryNodeIdentifierSystem: IdentifierSystem
    public let producer: Reference
    public let sourceRecord: BusinessIdentifier
    public let sourceRetractionTime: Date
    public let recordedAt: Date
    public let repositoryBundleID: RepositoryID?
    public let repositoryProvenanceID: RepositoryID?

    public init(
        eventIdentifier: ExchangeEventIdentifier,
        entryNodeIdentifierSystem: IdentifierSystem,
        producer: Reference,
        sourceRecord: BusinessIdentifier,
        sourceRetractionTime: Date,
        recordedAt: Date,
        repositoryBundleID: RepositoryID? = nil,
        repositoryProvenanceID: RepositoryID? = nil
    ) {
        self.eventIdentifier = eventIdentifier
        self.entryNodeIdentifierSystem = entryNodeIdentifierSystem
        self.producer = producer
        self.sourceRecord = sourceRecord
        self.sourceRetractionTime = sourceRetractionTime
        self.recordedAt = recordedAt
        self.repositoryBundleID = repositoryBundleID
        self.repositoryProvenanceID = repositoryProvenanceID
    }
}


/// Builds a lifecycle assertion without copying or mutilating prior clinical resources.
public enum RetractionEventBuilder {
    private static let participantType: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/provenance-participant-type"

    /// Builds and validates one retraction assertion graph for the supplied logical targets.
    public static func build(
        targets: [RetractionTarget],
        context: RetractionEventContext
    ) throws -> ExchangeGraph {
        guard !targets.isEmpty else {
            throw RetractionEventError.emptyTargets
        }
        guard Set(targets).count == targets.count else {
            throw RetractionEventError.duplicateTarget
        }
        do {
            _ = try TypedReference.validate(context.producer, expectedResourceType: .device)
        } catch {
            throw RetractionEventError.invalidProducer
        }
        guard context.sourceRecord.role == .sourceRecord,
              ExchangeIdentity.isCanonicalOpaqueIdentifierValue(context.sourceRecord.value) else {
            throw RetractionEventError.invalidSourceRecord
        }

        var provenance = Provenance(
            activity: CodeableConcept(coding: [Coding(
                code: GroveLifecycleContract.sourceRecordRetracted.asFHIRStringPrimitive(),
                display: "Source record retracted".asFHIRStringPrimitive(),
                system: Canonicals.lifecycleEventCodeSystem
            )]),
            agent: [ProvenanceAgent(
                type: CodeableConcept(coding: [Coding(
                    code: "assembler".asFHIRStringPrimitive(),
                    display: "Assembler".asFHIRStringPrimitive(),
                    system: participantType
                )]),
                who: context.producer
            )],
            entity: [ProvenanceEntity(
                role: FHIRPrimitive(.source),
                what: Reference(identifier: context.sourceRecord.fhirIdentifier)
            )],
            meta: Meta(profile: [GroveLifecycleContract.retractionProvenanceProfile]),
            occurred: .dateTime(FHIRPrimitive(try DateTime(date: context.sourceRetractionTime))),
            recorded: FHIRPrimitive(try Instant(date: context.recordedAt)),
            target: targets.map(\.reference)
        )
        provenance.id = context.repositoryProvenanceID?.primitive
        let nodeKey = try ExchangeNodeKey(
            system: context.entryNodeIdentifierSystem,
            eventIdentifier: context.eventIdentifier,
            nodeRole: "retraction-provenance",
            ordinal: 0
        )
        let entry = try ExchangeIdentity.entry(
            nodeKey: nodeKey,
            resource: ResourceProxy(with: provenance)
        )
        var bundle = Bundle(
            entry: [entry],
            identifier: context.eventIdentifier.businessIdentifier.fhirIdentifier,
            meta: Meta(profile: [GroveLifecycleContract.retractionBundleProfile]),
            timestamp: FHIRPrimitive(try Instant(date: context.recordedAt)),
            type: FHIRPrimitive(.collection)
        )
        bundle.id = context.repositoryBundleID?.primitive
        return try ExchangeGraph(
            kind: .retraction,
            eventIdentifier: context.eventIdentifier,
            bundle: bundle
        )
    }
}


public enum RetractionEventError: Error, Equatable, Sendable {
    case emptyTargets
    case duplicateTarget
    case invalidEventIdentifier
    case invalidProducer
    case invalidSourceRecord
}
