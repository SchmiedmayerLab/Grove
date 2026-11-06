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

/// The shared nodes of one projection, which every entry and internal reference resolves against. Each is keyed after
/// the nodes it references.
struct GraphFrame {
    /// The discriminator of every Observation's source-output identity: a response extracts each measurement once,
    /// so its contract's id alone tells the outputs apart.
    static let outputDiscriminator = "single"

    let extracted: ExtractedResponse
    let context: QuestionnaireExtractionContext
    let patientEntry: BundleEntry
    let patientReference: Reference
    let studies: StudyContext
    let responseEntry: BundleEntry
    let responseURL: String
    let host: IdentifiedDevice?
    let application: IdentifiedDevice
    let applicationURL: String

    init(extracted: ExtractedResponse, context: QuestionnaireExtractionContext) throws {
        self.extracted = extracted
        self.context = context
        let patientEntry = try StudyContext.patientEntry(context.patient, subject: context.subject, identityScope: context.identityScope)
        self.patientEntry = patientEntry
        let patientReference = Reference(reference: patientEntry.fullUrl?.value?.url.absoluteString.asFHIRStringPrimitive())
        self.patientReference = patientReference
        self.studies = try StudyContext(
            studies: context.studies,
            subject: context.subject,
            subjectReference: patientReference,
            identityScope: context.identityScope
        )
        let responseEntry = try Self.responseEntry(extracted: extracted, patientReference: patientReference, context: context)
        self.responseEntry = responseEntry
        self.responseURL = responseEntry.fullUrl?.value?.url.absoluteString ?? ""
        let host = try Self.hostDevice(writer: extracted.writer, context: context)
        self.host = host
        let application = try Self.applicationDevice(
            writer: extracted.writer,
            context: context,
            hostURL: host?.url
        )
        self.application = application
        self.applicationURL = application.url
    }

    /// The response the record carries, keyed by its content. Its one `identifier` holds the submission's, so it repeats
    /// the key in a `grove-context-snapshot` extension, which replaces any the input carries: the key is derived, and its
    /// digest leaves that extension out.
    private static func responseEntry(
        extracted: ExtractedResponse,
        patientReference: Reference,
        context: QuestionnaireExtractionContext
    ) throws -> BundleEntry {
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
        let key = try context.identityScope.contentSnapshot(
            of: carriedResponse,
            subject: context.subject,
            role: .context(.questionnaireResponse)
        )
        carriedResponse.extension = (carriedResponse.extension ?? []).filter { $0.url != Canonicals.contextSnapshot }
            + [Extension(url: Canonicals.contextSnapshot, value: .identifier(key.fhirIdentifier))]
        return try BundleEntry(identifier: key, resource: ResourceProxy(with: carriedResponse))
    }
}


// MARK: Entries

extension GraphFrame {
    func supportEntries() -> [BundleEntry] {
        var entries = [patientEntry]
        entries += studies.entries
        entries.append(responseEntry)
        for device in [host, application].compactMap(\.self) {
            entries.append(device.entry)
        }
        return entries
    }

    func observationEntry(for measurement: ExtractedMeasurement) throws -> (entry: BundleEntry, url: String) {
        let output = try extracted.sourceRecord.output(role: measurement.contract.id, discriminator: Self.outputDiscriminator)
        let entry = try BundleEntry(
            identifier: output,
            resource: ResourceProxy(with: try observation(for: measurement, output: output))
        )
        return (entry, try output.fullURLString)
    }

    func provenance(targets: [String]) throws -> Provenance {
        // The writer's application assembled the outputs; `occurred` keeps the offset the response was authored at.
        try ExchangeGraphAssembler.conversionProvenance(
            of: extracted.sourceRecord,
            targetURLs: targets,
            assemblerURL: applicationURL,
            profile: Profile.groveMobileConversionProvenance,
            at: context.conversionInstant,
            occurredOffset: try Self.statedOffset(of: extracted.authored)
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

    /// The offset `authored` states, as a fixed zone; `Provenance.occurred` states the conversion instant at it.
    ///
    /// A response built in memory can carry a named zone, whose offset at the conversion instant can differ across a
    /// daylight-saving change, while its JSON keeps only the stated offset. Following the stated offset keeps `occurred` a
    /// function of those bytes, so either form of one response restates its record byte for byte.
    static func statedOffset(of authored: DateTime) throws -> TimeZone {
        guard let zone = authored.timeZone else {
            return .utc
        }
        return TimeZone(secondsFromGMT: zone.secondsFromGMT(for: try authored.asNSDate())) ?? zone
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
    /// The writer's host snapshot, when the writer context names the operating-system version every host snapshot states.
    /// The writer's model is the host's product type.
    static func hostDevice(
        writer: QuestionnaireWriterContext,
        context: QuestionnaireExtractionContext
    ) throws -> IdentifiedDevice? {
        guard let osVersion = writer.hostOperatingSystemVersion else {
            return nil
        }
        let host = try HostDevice(
            operatingSystemName: writer.hostOperatingSystemName,
            operatingSystemVersion: osVersion,
            operatingSystemBuild: writer.hostOperatingSystemBuild,
            productType: writer.hostModel
        )
        return try IdentifiedDevice(
            keying: ExchangeGraphAssembler.hostDevice(host),
            role: .host,
            subject: context.subject,
            identityScope: context.identityScope
        )
    }

    /// The writer's application snapshot, carrying the writer's own identifier and naming its host when there is one.
    static func applicationDevice(
        writer: QuestionnaireWriterContext,
        context: QuestionnaireExtractionContext,
        hostURL: String?
    ) throws -> IdentifiedDevice {
        var device = ExchangeGraphAssembler.applicationDevice(
            name: writer.applicationName,
            version: writer.applicationVersion,
            build: writer.applicationBuild,
            profile: Profile.groveApplicationDevice
        )
        device.identifier = [writer.applicationIdentifier.fhirIdentifier]
        device.parent = hostURL.map { Reference(reference: $0.asFHIRStringPrimitive()) }
        return try IdentifiedDevice(keying: device, role: .application, subject: context.subject, identityScope: context.identityScope)
    }
}
