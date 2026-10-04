//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import ModelsR4


// MARK: Frame

/// The event-scoped identities of one projection, which every entry and internal reference resolves against.
struct GraphFrame {
    let extracted: ExtractedResponse
    let context: QuestionnaireExtractionContext
    let patientNode: EntryNodeKey
    let patientReference: Reference
    let studies: StudyContext
    let responseNode: EntryNodeKey
    let responseURL: String
    let host: IdentifiedDevice?
    let application: IdentifiedDevice
    let applicationURL: String

    init(extracted: ExtractedResponse, context: QuestionnaireExtractionContext) throws {
        self.extracted = extracted
        self.context = context
        let patientNode = try Self.nodeKey("patient", context: context)
        self.patientNode = patientNode
        let patientReference = Reference(reference: try patientNode.identifier.fullURLString.asFHIRStringPrimitive())
        self.patientReference = patientReference
        self.studies = try StudyContext(
            studies: context.studies,
            subjectReference: patientReference,
            event: context.eventIdentifier,
            identityScope: context.identityScope
        )
        let responseNode = try Self.nodeKey("questionnaire-response", context: context)
        self.responseNode = responseNode
        self.responseURL = try responseNode.identifier.fullURLString
        let host = try Self.hostDevice(writer: extracted.writer, context: context)
        self.host = host
        let application = try Self.applicationDevice(
            writer: extracted.writer,
            context: context,
            hostURL: try host.map { try $0.identity.fullURLString }
        )
        self.application = application
        self.applicationURL = try application.identity.fullURLString
    }

    /// The ordinal counts within the node role, not across the Bundle, so a graph carrying one
    /// node per keyless role numbers every one of them zero.
    static func nodeKey(_ role: String, context: QuestionnaireExtractionContext) throws -> EntryNodeKey {
        try EntryNodeKey(
            system: context.identityScope.systems.entryNode,
            event: context.eventIdentifier,
            nodeRole: role,
            ordinal: 0
        )
    }
}


// MARK: Entries

extension GraphFrame {
    func supportEntries() throws -> [BundleEntry] {
        // The exchange copy resolves the response's actor references inside the Bundle: a literal
        // repository reference cannot resolve here, and the extraction has already established that
        // author and source, where stated, are the subject.
        var carriedResponse = extracted.response
        carriedResponse.subject = patientReference
        if carriedResponse.author != nil {
            carriedResponse.author = patientReference
        }
        if carriedResponse.source != nil {
            carriedResponse.source = patientReference
        }

        var entries = [try BundleEntry(identifier: patientNode.identifier, resource: ResourceProxy(with: context.patient))]
        entries += studies.entries
        entries.append(try BundleEntry(identifier: responseNode.identifier, resource: ResourceProxy(with: carriedResponse)))
        for device in [host, application].compactMap(\.self) {
            entries.append(try BundleEntry(identifier: device.identity, resource: ResourceProxy(with: device.resource)))
        }
        return entries
    }

    func observationEntry(for measurement: ExtractedMeasurement) throws -> (entry: BundleEntry, url: String) {
        let output = try extracted.sourceRecord.output(role: measurement.contract.id, discriminator: "single")
        let entry = try BundleEntry(
            identifier: output,
            resource: ResourceProxy(with: try observation(for: measurement, output: output))
        )
        return (entry, try output.fullURLString)
    }

    func provenanceEntry(targets: [String]) throws -> BundleEntry {
        // The writer's application assembled the outputs; `occurred` keeps the offset the response was authored at.
        try BundleEntry(
            identifier: try Self.nodeKey("conversion-provenance", context: context).identifier,
            resource: ResourceProxy(with: try ExchangeGraphAssembler.conversionProvenance(
                of: extracted.sourceRecord,
                targetURLs: targets,
                assemblerURL: applicationURL,
                profile: Profile.groveMobileConversionProvenance,
                at: context.conversionInstant,
                occurredOffset: extracted.authored.timeZone ?? .utc
            ))
        )
    }

    func graph(entries: [BundleEntry]) throws -> ExchangeGraph {
        let bundle = Bundle(
            entry: entries,
            identifier: context.eventIdentifier.identifier.fhirIdentifier,
            meta: Meta(profile: [Profile.groveMobileExchangeBundle]),
            timestamp: FHIRPrimitive(try ExchangeInstant.fhirInstant(context.conversionInstant)),
            type: FHIRPrimitive(.collection)
        )
        return try ExchangeGraph(
            kind: .active,
            eventIdentifier: context.eventIdentifier,
            bundle: bundle
        )
    }
}


// MARK: Observations

extension GraphFrame {
    static func apply(_ value: ExtractedValue, to observation: inout Observation) {
        switch value {
        case .quantity(let quantity):
            observation.value = .quantity(quantity)
        case .boolean(let flag):
            observation.value = .boolean(FHIRPrimitive(FHIRBool(flag)))
        case .codeableConcept(let concept):
            observation.value = .codeableConcept(concept)
        case .components(let components):
            observation.component = components.map { component in
                ObservationComponent(
                    code: Self.codeableConcept(component.code),
                    value: .quantity(component.value)
                )
            }
        }
    }

    static func instant(from authored: DateTime) throws -> FHIRPrimitive<Instant> {
        FHIRPrimitive(try Instant(
            date: try authored.asNSDate(),
            timeZone: authored.timeZone ?? .utc
        ))
    }

    static func codeableConcept(_ coding: CodingContract) -> CodeableConcept {
        CodeableConcept(coding: [
            Coding(
                code: coding.code.asFHIRStringPrimitive(),
                display: coding.display?.asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: coding.system))
            )
        ])
    }

    func observation(for measurement: ExtractedMeasurement, output sourceOutput: RoledIdentifier) throws -> Observation {
        let response = extracted.response
        let status: ObservationStatus = response.status.value == .amended ? .amended : .final
        var observation = Observation(
            code: Self.codeableConcept(measurement.contract.code),
            status: FHIRPrimitive(status)
        )
        observation.meta = Meta(profile: [measurement.contract.profile])
        observation.identifier = [extracted.sourceRecord.identifier.fhirIdentifier, sourceOutput.fhirIdentifier]
        observation.subject = patientReference
        if response.author != nil {
            observation.performer = [patientReference]
        }
        if !measurement.categories.isEmpty {
            observation.category = measurement.categories
        }
        // Observation-based extraction: the response's exact authored instant is both the
        // effective time and the issue time of every extracted Observation.
        observation.effective = .dateTime(FHIRPrimitive(extracted.authored))
        observation.issued = try Self.instant(from: extracted.authored)
        Self.apply(measurement.value, to: &observation)
        observation.extension = [
            Extension(
                url: Canonicals.recordingMethod,
                value: .coding(Coding(
                    code: "manual-entry",
                    display: "Manual entry",
                    system: Canonicals.recordingMethodCodeSystem
                ))
            ),
            Extension(
                url: Canonicals.gatewayDevice,
                value: .reference(Reference(reference: applicationURL.asFHIRStringPrimitive()))
            )
        ] + studies.studyReferences.map { Extension(url: Canonicals.researchStudy, value: .reference($0)) }
        observation.derivedFrom = [Reference(reference: responseURL.asFHIRStringPrimitive())]
        return observation
    }
}


// MARK: Devices

extension GraphFrame {
    /// The writer's host snapshot, when the writer context names both its model and its operating-system version.
    static func hostDevice(
        writer: QuestionnaireWriterContext,
        context: QuestionnaireExtractionContext
    ) throws -> IdentifiedDevice? {
        guard let model = writer.hostModel, let osVersion = writer.hostOperatingSystemVersion else {
            return nil
        }
        let identity = try context.identityScope.deviceSnapshot(
            event: context.eventIdentifier,
            role: .host,
            sourceDeviceToken: "\(model)|\(osVersion)"
        )
        var device = ExchangeGraphAssembler.hostDevice(operatingSystemVersion: osVersion, modelNumber: model)
        device.identifier = [identity.fhirIdentifier]
        return IdentifiedDevice(resource: device, identity: identity)
    }

    /// The writer's application snapshot, carrying the writer's own identifier and naming its host when there is one.
    static func applicationDevice(
        writer: QuestionnaireWriterContext,
        context: QuestionnaireExtractionContext,
        hostURL: String?
    ) throws -> IdentifiedDevice {
        let identity = try context.identityScope.deviceSnapshot(
            event: context.eventIdentifier,
            role: .application,
            sourceDeviceToken: [writer.applicationIdentifier.value, writer.applicationVersion, writer.applicationBuild]
                .compactMap(\.self)
                .joined(separator: "|")
        )
        var device = ExchangeGraphAssembler.applicationDevice(
            name: writer.applicationName,
            version: writer.applicationVersion,
            build: writer.applicationBuild,
            profile: Profile.groveApplicationDevice
        )
        device.identifier = [identity.fhirIdentifier, writer.applicationIdentifier.fhirIdentifier]
        device.parent = hostURL.map { Reference(reference: $0.asFHIRStringPrimitive()) }
        return IdentifiedDevice(resource: device, identity: identity)
    }
}
