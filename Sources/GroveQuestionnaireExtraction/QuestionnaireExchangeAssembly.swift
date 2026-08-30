//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Schmiedmayer Lab and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveFHIRContract
public import ModelsR4


/// Everything one projection needs beyond the pair itself.
///
/// The same context serves an app projecting its own responses and a server projecting
/// received ones: whoever projects holds the identity scope and creates the event, exactly
/// as the HealthKit converter does for on-device conversion. A received response carries its
/// writer facts in the writer-context extension; a local projection states them directly.
public struct QuestionnaireExtractionContext: Sendable {
    /// The Patient the exchange Bundle carries; every subject and performer resolves to it.
    public let patient: ModelsR4.Patient
    public let eventIdentifier: ExchangeEventIdentifier
    public let identityScope: PseudonymousIdentityScope
    public let repositoryScope: BusinessIdentifier
    public let entryNodeIdentifierSystem: IdentifierSystem
    public let conversionInstant: Date
    /// Writer facts for a local projection; a received response supplies its own instead.
    public let localWriter: QuestionnaireWriterContext?

    public init(
        patient: ModelsR4.Patient,
        eventIdentifier: ExchangeEventIdentifier,
        identityScope: PseudonymousIdentityScope,
        repositoryScope: BusinessIdentifier,
        entryNodeIdentifierSystem: IdentifierSystem,
        conversionInstant: Date,
        localWriter: QuestionnaireWriterContext? = nil
    ) {
        self.patient = patient
        self.eventIdentifier = eventIdentifier
        self.identityScope = identityScope
        self.repositoryScope = repositoryScope
        self.entryNodeIdentifierSystem = entryNodeIdentifierSystem
        self.conversionInstant = conversionInstant
        self.localWriter = localWriter
    }
}


/// Projects one Questionnaire/Response pair into a complete Grove exchange graph.
///
/// The Bundle carries the Patient, the response, the writer's application and host snapshots,
/// one Observation per extracted measurement, and the conversion Provenance, exactly as the
/// questionnaire guide's worked example documents. Every internal reference is the literal
/// deterministic URN of another entry, so the graph resolves without any repository.
public enum QuestionnaireExchangeProjection {
    static let adapterID = "questionnaire"

    /// Extracts every marked measurement and returns the exchange bundle carrying them.
    public static func exchangeGraph(
        questionnaire: ModelsR4.Questionnaire,
        response: ModelsR4.QuestionnaireResponse,
        context: QuestionnaireExtractionContext
    ) throws -> ExchangeGraph {
        let extracted = try QuestionnaireObservationExtractor(
            questionnaire: questionnaire,
            response: response
        ).extract()
        let frame = try GraphFrame(response: response, context: context)
        var entries = try frame.supportEntries()
        var observationURLs: [String] = []
        for measurement in extracted {
            let (entry, url) = try frame.observationEntry(for: measurement)
            entries.append(entry)
            observationURLs.append(url)
        }
        entries.append(try frame.provenanceEntry(
            targets: observationURLs,
            ordinal: UInt64(entries.count)
        ))
        try ExchangeIdentity.validate(entries: entries)
        return try frame.graph(entries: entries)
    }
}


// MARK: Frame

/// The shared state of one projection run: the validated response facts and the deterministic
/// identities every entry and internal reference resolves against.
private struct GraphFrame {
    let context: QuestionnaireExtractionContext
    let response: ModelsR4.QuestionnaireResponse
    let authored: DateTime
    let sourceType: String
    let nativeRecordID: String
    let sourceRecord: BusinessIdentifier
    let patientNode: ExchangeNodeKey
    let patientReference: Reference
    let responseNode: ExchangeNodeKey
    let responseURL: String
    let host: IdentifiedDevice?
    let application: IdentifiedDevice
    let applicationURL: String

    init(response: ModelsR4.QuestionnaireResponse, context: QuestionnaireExtractionContext) throws {
        guard let writer = try response.writerContext() ?? context.localWriter else {
            throw ObservationExtractionError.writerContextMissing
        }
        guard let nativeRecordID = response.identifier?.value?.value?.string else {
            throw ObservationExtractionError.responseIdentifierMissing
        }
        guard let canonical = QuestionnaireCanonicalIdentity(response.questionnaire) else {
            throw ObservationExtractionError.versionedQuestionnaireCanonicalMissing
        }
        guard let authored = response.authored?.value else {
            throw ObservationExtractionError.responseNotCompleted(status: "authored missing")
        }
        self.context = context
        self.response = response
        self.authored = authored
        self.nativeRecordID = nativeRecordID
        let sourceType = "\(canonical.url.absoluteString)|\(canonical.version)"
        self.sourceType = sourceType
        self.sourceRecord = try context.identityScope.sourceRecord(
            adapterID: QuestionnaireExchangeProjection.adapterID,
            sourceType: sourceType,
            repositoryScope: context.repositoryScope,
            nativeRecordID: nativeRecordID
        )
        let patientNode = try Self.nodeKey("patient", ordinal: 0, context: context)
        self.patientNode = patientNode
        self.patientReference = Reference(
            reference: try ExchangeIdentity.fullURL(for: patientNode.identifier).asFHIRStringPrimitive()
        )
        let responseNode = try Self.nodeKey("questionnaire-response", ordinal: 1, context: context)
        self.responseNode = responseNode
        self.responseURL = try ExchangeIdentity.fullURL(for: responseNode.identifier)
        let host = try Self.hostDevice(writer: writer, context: context)
        self.host = host
        let application = try Self.applicationDevice(
            writer: writer,
            context: context,
            hostIdentity: host?.identity,
            hostURL: try host.map { try ExchangeIdentity.fullURL(for: $0.identity) }
        )
        self.application = application
        self.applicationURL = try ExchangeIdentity.fullURL(for: application.identity)
    }

    static func nodeKey(
        _ role: String,
        ordinal: UInt64,
        context: QuestionnaireExtractionContext
    ) throws -> ExchangeNodeKey {
        try ExchangeNodeKey(
            system: context.entryNodeIdentifierSystem,
            eventIdentifier: context.eventIdentifier,
            nodeRole: role,
            ordinal: CanonicalNonnegativeDecimal(ordinal)
        )
    }
}


// MARK: Entries

extension GraphFrame {
    func supportEntries() throws -> [BundleEntry] {
        // The exchange copy of the response resolves its actor references inside the Bundle:
        // a literal repository reference cannot resolve here.
        var carriedResponse = response
        carriedResponse.subject = patientReference
        if carriedResponse.author != nil {
            carriedResponse.author = patientReference
        }
        if carriedResponse.source != nil {
            carriedResponse.source = patientReference
        }

        var entries = [
            try ExchangeIdentity.entry(nodeKey: patientNode, resource: ResourceProxy(with: context.patient)),
            try ExchangeIdentity.entry(nodeKey: responseNode, resource: ResourceProxy(with: carriedResponse))
        ]
        if let host {
            entries.append(try ExchangeIdentity.entry(
                identifier: host.identity,
                resource: ResourceProxy(with: host.resource)
            ))
        }
        entries.append(try ExchangeIdentity.entry(
            identifier: application.identity,
            resource: ResourceProxy(with: application.resource)
        ))
        return entries
    }

    func observationEntry(for measurement: ExtractedMeasurement) throws -> (entry: BundleEntry, url: String) {
        let output = try context.identityScope.sourceOutput(
            adapterID: QuestionnaireExchangeProjection.adapterID,
            sourceType: sourceType,
            repositoryScope: context.repositoryScope,
            nativeRecordID: nativeRecordID,
            outputRole: measurement.contract.id,
            outputDiscriminator: measurement.linkID
        )
        let entry = try ExchangeIdentity.entry(
            identifier: output,
            resource: ResourceProxy(with: try observation(for: measurement, output: output))
        )
        return (entry, try ExchangeIdentity.fullURL(for: output))
    }

    func provenanceEntry(targets: [String], ordinal: UInt64) throws -> BundleEntry {
        try ExchangeIdentity.entry(
            nodeKey: try Self.nodeKey("conversion-provenance", ordinal: ordinal, context: context),
            resource: ResourceProxy(with: try provenance(targets: targets))
        )
    }

    func graph(entries: [BundleEntry]) throws -> ExchangeGraph {
        let bundle = Bundle(
            entry: entries,
            identifier: context.eventIdentifier.businessIdentifier.fhirIdentifier,
            meta: Meta(profile: [Profile.groveMobileExchangeBundle]),
            timestamp: FHIRPrimitive(try Instant(date: context.conversionInstant, timeZone: Self.utcTimeZone)),
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
            timeZone: authored.timeZone ?? utcTimeZone
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

    func observation(for measurement: ExtractedMeasurement, output sourceOutput: BusinessIdentifier) throws -> Observation {
        let status: ObservationStatus = response.status.value == .amended ? .amended : .final
        var observation = Observation(
            code: Self.codeableConcept(measurement.contract.code),
            status: FHIRPrimitive(status)
        )
        observation.meta = Meta(profile: [measurement.contract.profile])
        observation.identifier = [sourceRecord.fhirIdentifier, sourceOutput.fhirIdentifier]
        observation.subject = patientReference
        observation.performer = [patientReference]
        if !measurement.categories.isEmpty {
            observation.category = measurement.categories
        }
        // Observation-based extraction: the response's exact authored instant is both the
        // effective time and the issue time of every extracted Observation.
        observation.effective = .dateTime(FHIRPrimitive(authored))
        observation.issued = try Self.instant(from: authored)
        Self.apply(measurement.value, to: &observation)
        observation.extension = [
            Extension(
                url: Canonicals.recordingMethod,
                value: .codeableConcept(CodeableConcept(coding: [
    Coding(
                        code: "manual-entry",
                        display: "Manual entry",
                        system: Canonicals.recordingMethodCodeSystem
                    )
                ]))
            ),
            Extension(
                url: Canonicals.gatewayDevice,
                value: .reference(Reference(reference: applicationURL.asFHIRStringPrimitive()))
            )
        ]
        observation.derivedFrom = [Reference(reference: responseURL.asFHIRStringPrimitive())]
        return observation
    }
}


// MARK: Devices

extension GraphFrame {
    struct IdentifiedDevice {
        let resource: Device
        let identity: BusinessIdentifier
    }

    static func hostDevice(
        writer: QuestionnaireWriterContext,
        context: QuestionnaireExtractionContext
    ) throws -> IdentifiedDevice? {
        guard let model = writer.hostModel, let osVersion = writer.hostOperatingSystemVersion else {
            return nil
        }
        let identity = try context.identityScope.deviceSnapshot(
            eventIdentifier: context.eventIdentifier,
            deviceRole: .host,
            sourceDeviceToken: "questionnaire-host|\(model)|\(osVersion)"
        )
        var device = Device()
        device.meta = Meta(profile: [Profile.groveHostDevice])
        device.identifier = [identity.fhirIdentifier]
        device.status = FHIRPrimitive(.active)
        device.modelNumber = model.asFHIRStringPrimitive()
        device.version = [
    DeviceVersion(
                type: CodeableConcept(coding: [
    Coding(
                        code: "os-version",
                        system: Canonicals.groveApplicationVersionType
                    )
                ]),
                value: osVersion.asFHIRStringPrimitive()
            )
        ]
        return IdentifiedDevice(resource: device, identity: identity)
    }

    static func applicationDevice(
        writer: QuestionnaireWriterContext,
        context: QuestionnaireExtractionContext,
        hostIdentity: BusinessIdentifier?,
        hostURL: String?
    ) throws -> IdentifiedDevice {
        var token = "questionnaire-application|\(writer.applicationIdentifier.systemValue)"
            + "|\(writer.applicationIdentifier.value)|\(writer.applicationVersion)"
        if let hostIdentity {
            token += "|\(hostIdentity.value)"
        }
        let identity = try context.identityScope.deviceSnapshot(
            eventIdentifier: context.eventIdentifier,
            deviceRole: .application,
            sourceDeviceToken: token
        )
        var device = Device()
        device.meta = Meta(profile: [Profile.groveApplicationDevice])
        device.identifier = [
            identity.fhirIdentifier,
            writer.applicationIdentifier.fhirIdentifier
        ]
        device.status = FHIRPrimitive(.active)
        device.deviceName = [
    DeviceDeviceName(
                name: writer.applicationName.asFHIRStringPrimitive(),
                type: FHIRPrimitive(.userFriendlyName)
            )
        ]
        var versions = [
    DeviceVersion(
                type: CodeableConcept(coding: [
    Coding(
                        code: "531975",
                        system: FHIRPrimitive(FHIRURI(stringLiteral: mdcSystem))
                    )
                ]),
                value: writer.applicationVersion.asFHIRStringPrimitive()
            )
        ]
        if let build = writer.applicationBuild {
            versions.append(DeviceVersion(
                type: CodeableConcept(coding: [
    Coding(
                        code: "build",
                        system: Canonicals.groveApplicationVersionType
                    )
                ]),
                value: build.asFHIRStringPrimitive()
            ))
        }
        device.version = versions
        if let hostURL {
            device.parent = Reference(reference: hostURL.asFHIRStringPrimitive())
        }
        return IdentifiedDevice(resource: device, identity: identity)
    }
}


// MARK: Provenance

extension GraphFrame {
    static let participantType = "http://terminology.hl7.org/CodeSystem/provenance-participant-type"
    static let lifecycleEvent = "http://terminology.hl7.org/CodeSystem/iso-21089-lifecycle"
    static let mdcSystem = "urn:iso:std:iso:11073:10101"
    static let utcTimeZone = TimeZone(identifier: "UTC") ?? .current

    func provenance(targets: [String]) throws -> Provenance {
        Provenance(
            activity: CodeableConcept(coding: [
    Coding(
                    code: "transform",
                    display: "Transform/Translate Record Lifecycle Event",
                    system: FHIRPrimitive(FHIRURI(stringLiteral: Self.lifecycleEvent))
                )
            ]),
            agent: [
    ProvenanceAgent(
                    type: CodeableConcept(coding: [
    Coding(
                            code: "assembler",
                            display: "Assembler",
                            system: FHIRPrimitive(FHIRURI(stringLiteral: Self.participantType))
                        )
                    ]),
                    who: Reference(reference: applicationURL.asFHIRStringPrimitive())
                )
            ],
            entity: [
    ProvenanceEntity(
                    role: FHIRPrimitive(.source),
                    what: Reference(identifier: sourceRecord.fhirIdentifier)
                )
            ],
            meta: Meta(profile: [Profile.groveMobileConversionProvenance]),
            occurred: .dateTime(FHIRPrimitive(try DateTime(
                date: context.conversionInstant,
                timeZone: authored.timeZone ?? Self.utcTimeZone
            ))),
            recorded: FHIRPrimitive(try Instant(date: context.conversionInstant, timeZone: Self.utcTimeZone)),
            target: targets.map { Reference(reference: $0.asFHIRStringPrimitive()) }
        )
    }
}
