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
    public let identifier: RoledIdentifier
    public let resourceType: ResourceType
    public let role: RetractionTargetRole
    /// The adapter's own record identifier for the retracted record, carried beside the opaque
    /// Grove identity so a consumer can delete the exact native record.
    ///
    /// It is disclosed only where the adapter's authorized-disclosure policy mints one — build it
    /// with ``GovernedSourceIdentifierDisclosurePolicy/identifier(for:)`` rather than by hand.
    public let nativeRecordIdentifier: Identifier?

    public init(
        identifier: RoledIdentifier,
        resourceType: ResourceType,
        role: RetractionTargetRole,
        nativeRecordIdentifier: Identifier? = nil
    ) throws(RetractionTargetError) {
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
        guard Self.statesNativeRecord(nativeRecordIdentifier) else {
            throw RetractionTargetError.invalidNativeRecordIdentifier
        }
        self.identifier = identifier
        self.resourceType = resourceType
        self.role = role
        self.nativeRecordIdentifier = nativeRecordIdentifier
    }

    /// A clear native identifier states the source store's own key; it never restates a Grove
    /// graph identity under a Grove role.
    private static func statesNativeRecord(_ identifier: Identifier?) -> Bool {
        guard let identifier else {
            return true
        }
        guard let system = identifier.system?.value?.url.absoluteString,
              (try? IdentifierSystem(system)) != nil,
              identifier.value?.value?.string.isEmpty == false else {
            return false
        }
        // Any coding in the Grove role system restates a graph identity, whether or not its code parses.
        return !(identifier.type?.coding ?? []).contains {
            $0.system?.value?.url.absoluteString == Canonicals.identifierRoleCodeSystemValue
        }
    }

    var reference: Reference {
        var extensions = [Extension(
            url: Canonicals.retractionTargetRole,
            value: .code(role.rawValue.asFHIRStringPrimitive())
        )]
        if let nativeRecordIdentifier {
            extensions.append(Extension(
                url: Canonicals.retractionTargetNativeIdentifier,
                value: .identifier(nativeRecordIdentifier)
            ))
        }
        return Reference(
            extension: extensions,
            identifier: identifier.fhirIdentifier,
            type: FHIRPrimitive(FHIRURI(stringLiteral: resourceType.rawValue))
        )
    }
}


public enum RetractionTargetError: Error, Equatable, Sendable {
    case identifierRoleMismatch(
        targetRole: RetractionTargetRole,
        identifierRole: GroveIdentifierRole
    )
    case resourceTypeMismatch(role: RetractionTargetRole, resourceType: ResourceType)
    /// The disclosed native identifier is incomplete or restates a Grove graph identity.
    case invalidNativeRecordIdentifier
}


/// A validated lifecycle assertion that names prior graph nodes without copying them.
///
/// The converting application is the assembler, referenced logically through its event-scoped
/// snapshot identity; the retraction occurred when the source deleted the record and was recorded
/// at the context's conversion instant.
public struct RetractionEvent: Sendable {
    public let graph: ExchangeGraph

    public init(
        targets: [RetractionTarget],
        context: ExchangeEventContext,
        sourceRecord: RoledIdentifier,
        retractedAt: Date
    ) throws(RetractionEventError) {
        guard !targets.isEmpty else {
            throw .emptyTargets
        }
        guard Set(targets.map(\.identifier.identifier)).count == targets.count else {
            throw .duplicateTarget
        }
        guard sourceRecord.role == .sourceRecord,
              ExchangeIdentity.isCanonicalOpaqueIdentifierValue(sourceRecord.identifier.value) else {
            throw .invalidSourceRecord
        }
        let assembler: RoledIdentifier
        do {
            assembler = try context.identityScope.deviceSnapshot(
                event: context.event,
                role: .application,
                sourceDeviceToken: context.application.bundleIdentifier
            )
        } catch {
            throw .opaqueIdentity(error)
        }
        let occurred: DateTime
        let recorded: Instant
        do {
            occurred = try DateTime(date: retractedAt)
            recorded = try Instant(date: context.conversionInstant)
        } catch {
            throw .invalidInstant
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
                    system: Canonicals.provenanceParticipantType
                )]),
                who: Reference(
                    identifier: assembler.fhirIdentifier,
                    type: FHIRPrimitive(FHIRURI(stringLiteral: ResourceType.device.rawValue))
                )
            )],
            entity: [ProvenanceEntity(
                role: FHIRPrimitive(.source),
                what: Reference(identifier: sourceRecord.fhirIdentifier)
            )],
            meta: Meta(profile: [GroveLifecycleContract.retractionProvenanceProfile]),
            occurred: .dateTime(FHIRPrimitive(occurred)),
            recorded: FHIRPrimitive(recorded),
            target: targets.map(\.reference)
        )
        provenance.id = context.repositoryIDs[.provenance]?.primitive
        let entry: BundleEntry
        do {
            let nodeKey = try EntryNodeKey(
                system: context.entryNodeIdentifierSystem,
                event: context.event,
                nodeRole: "retraction-provenance",
                ordinal: 0
            )
            entry = try BundleEntry(identifier: nodeKey.identifier, resource: ResourceProxy(with: provenance))
        } catch {
            throw .exchangeIdentity(error)
        }
        var bundle = ModelsR4.Bundle(
            entry: [entry],
            identifier: context.event.identifier.fhirIdentifier,
            meta: Meta(profile: [GroveLifecycleContract.retractionBundleProfile]),
            timestamp: FHIRPrimitive(recorded),
            type: FHIRPrimitive(.collection)
        )
        bundle.id = context.repositoryIDs[.bundle]?.primitive
        do {
            self.graph = try ExchangeGraph(kind: .retraction, eventIdentifier: context.event, bundle: bundle)
        } catch {
            throw .exchangeGraph(error)
        }
    }
}


public enum RetractionEventError: Error, Equatable, Sendable {
    case emptyTargets
    case duplicateTarget
    case invalidSourceRecord
    case invalidInstant
    case opaqueIdentity(OpaqueIdentityError)
    case exchangeIdentity(ExchangeIdentityError)
    case exchangeGraph(ExchangeGraphError)
}
