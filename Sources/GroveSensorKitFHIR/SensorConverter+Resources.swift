//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Each builder keeps one complete FHIR resource projection adjacent for auditability.
// swiftlint:disable function_parameter_count multiline_literal_brackets discouraged_optional_collection

import CryptoKit
import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import ModelsR4

extension SensorConverter {
    static func primaryResource(
        _ record: SensorRecord,
        sourceRecord: BusinessIdentifier,
        sourceOutput: BusinessIdentifier,
        sourceArtifact: BusinessIdentifier?,
        context: SensorConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> SensorPrimaryResource {
        switch record {
        case .sampledData(let record):
            return .observation(try observation(
                record,
                sourceRecord: sourceRecord,
                sourceOutput: sourceOutput,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            ))
        case .electrocardiogram(let record):
            return .observation(try observation(
                record,
                sourceRecord: sourceRecord,
                sourceOutput: sourceOutput,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            ))
        case .recordingDocument(let record):
            return .recordingDocument(try document(
                record,
                sourceRecord: sourceRecord,
                sourceOutput: sourceOutput,
                sourceArtifact: sourceArtifact,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            ))
        }
    }

    static func observation(
        _ record: SensorSampledDataRecord,
        sourceRecord: BusinessIdentifier,
        sourceOutput: BusinessIdentifier,
        context: SensorConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        var profiles = [Profile.groveSensorSampledDataObservation]
        if let adapterProfile = record.adapterProfile {
            profiles.append(adapterProfile)
        }
        var observation = Observation(code: record.code.concept, status: FHIRPrimitive(.final))
        observation.meta = Meta(profile: profiles)
        observation.identifier = [sourceRecord.fhirIdentifier, sourceOutput.fhirIdentifier]
        observation.subject = context.subject
        observation.effective = .period(try period(start: record.start, end: record.end))
        observation.device = recordingDeviceURL.map(reference)
        observation.extension = contextExtensions(context, converterURL: converterURL)
        observation.value = .sampledData(try sampledData(
            samples: record.samples,
            dimensions: record.dimensions,
            periodMilliseconds: record.periodMilliseconds,
            origin: record.origin,
            unitCode: record.unitCode,
            unitDisplay: record.unitDisplay
        ))
        return observation
    }

    static func observation(
        _ record: SensorECGRecord,
        sourceRecord: BusinessIdentifier,
        sourceOutput: BusinessIdentifier,
        context: SensorConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        var profiles = [Profile.groveSensorEcgObservation]
        if let adapterProfile = record.adapterProfile {
            profiles.append(adapterProfile)
        }
        var observation = Observation(
            code: CodeableConcept(coding: [Coding(
                code: "11524-6".asFHIRStringPrimitive(),
                display: "EKG study".asFHIRStringPrimitive(),
                system: "http://loinc.org".asFHIRURIPrimitive()
            )]),
            status: FHIRPrimitive(.final)
        )
        observation.meta = Meta(profile: profiles)
        observation.identifier = [sourceRecord.fhirIdentifier, sourceOutput.fhirIdentifier]
        observation.subject = context.subject
        observation.effective = .period(try period(start: record.start, end: record.end))
        observation.device = recordingDeviceURL.map(reference)
        observation.extension = contextExtensions(context, converterURL: converterURL)
        observation.component = try record.channels.map { channel in
            ObservationComponent(
                code: channel.lead.concept,
                value: .sampledData(try sampledData(
                    samples: channel.millivolts,
                    dimensions: 1,
                    periodMilliseconds: record.periodMilliseconds,
                    origin: channel.originMillivolts,
                    unitCode: "mV",
                    unitDisplay: "mV"
                ))
            )
        }
        return observation
    }

    static func document(
        _ record: SensorRecordingDocument,
        sourceRecord: BusinessIdentifier,
        sourceOutput: BusinessIdentifier,
        sourceArtifact: BusinessIdentifier?,
        context: SensorConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> DocumentReference {
        var profiles = [Profile.groveSensorRecordingDocument]
        if let adapterProfile = record.adapterProfile {
            profiles.append(adapterProfile)
        }
        var authors = recordingDeviceURL.map { [reference($0)] } ?? []
        authors.append(reference(converterURL))
        let related = context.researchStudies + record.related.map {
            Reference(identifier: $0.fhirIdentifier)
        }
        guard let sourceArtifact else {
            throw SensorConversionError.invalidExchangeIdentity("recording document has no source-artifact identity")
        }
        var document = DocumentReference(
            author: authors,
            content: [DocumentReferenceContent(
                attachment: try attachment(record),
                format: Coding(
                    code: record.format.rawValue.asFHIRStringPrimitive(),
                    system: SensorKitContract.recordingFormatCodeSystem.asFHIRURIPrimitive(),
                    version: SensorKitCatalog.current.version.asFHIRStringPrimitive()
                )
            )],
            context: related.isEmpty ? nil : DocumentReferenceContext(related: related),
            date: FHIRPrimitive(try Instant(date: context.recordedAt)),
            identifier: [
                sourceRecord.fhirIdentifier,
                sourceOutput.fhirIdentifier,
                sourceArtifact.fhirIdentifier
            ],
            meta: Meta(profile: profiles),
            status: FHIRPrimitive(.current),
            subject: context.subject,
            type: record.type.concept
        )
        document.id = context.repositoryIDs.record?.primitive
        return document
    }

    static func sampledData(
        samples: [Double],
        dimensions: Int,
        periodMilliseconds: Double,
        origin: Double,
        unitCode: String,
        unitDisplay: String?
    ) throws -> SampledData {
        SampledData(
            data: samples.map(fhirNumber).joined(separator: " ").asFHIRStringPrimitive(),
            dimensions: FHIRPrimitive(FHIRPositiveInteger(Int32(dimensions))),
            origin: Quantity(
                code: unitCode.asFHIRStringPrimitive(),
                system: ucum,
                unit: unitDisplay?.asFHIRStringPrimitive(),
                value: try GroveFHIRDecimal(origin).primitive
            ),
            period: try GroveFHIRDecimal(periodMilliseconds).primitive
        )
    }

    static func fhirNumber(_ value: Double) -> String {
        String(groveFHIRPlainDecimal: value)
    }

    static func period(start: Date, end: Date) throws -> Period {
        Period(
            end: FHIRPrimitive(try DateTime(date: end)),
            start: FHIRPrimitive(try DateTime(date: start))
        )
    }

    static func attachment(_ record: SensorRecordingDocument) throws -> Attachment {
        let bytes: Data
        switch record.payload {
        case .inline(let data), .sidecar(_, let data):
            bytes = data
        }
        guard let size = Int32(exactly: bytes.count) else {
            throw SensorConversionError.payloadTooLarge(byteCount: bytes.count)
        }
        var attachment = Attachment(
            contentType: record.contentType.asFHIRStringPrimitive(),
            hash: FHIRPrimitive(Base64Binary(with: Data(Insecure.SHA1.hash(data: bytes)))),
            size: FHIRPrimitive(FHIRUnsignedInteger(size)),
            title: record.title.asFHIRStringPrimitive()
        )
        switch record.payload {
        case .inline(let data):
            attachment.data = FHIRPrimitive(Base64Binary(with: data))
        case .sidecar(let path, _):
            attachment.url = FHIRPrimitive(FHIRURI(stringLiteral: path))
        }
        return attachment
    }

    static func contextExtensions(
        _ context: SensorConversionContext,
        converterURL: String
    ) -> [Extension]? {
        var extensions = context.researchStudies.map { study in
            Extension(url: Canonicals.researchStudy, value: .reference(study))
        }
        if context.converterWasGateway {
            extensions.append(Extension(
                url: Canonicals.gatewayDevice,
                value: .reference(reference(converterURL))
            ))
        }
        return extensions.isEmpty ? nil : extensions
    }

    static func applicationDevice(_ application: SensorApplication) -> Device {
        var device = Device()
        device.meta = Meta(profile: [Profile.groveApplicationDevice])
        device.status = FHIRPrimitive(.active)
        device.deviceName = [DeviceDeviceName(
            name: application.name.asFHIRStringPrimitive(),
            type: FHIRPrimitive(.userFriendlyName)
        )]
        if let version = application.version {
            device.version = [DeviceVersion(
                type: CodeableConcept(coding: [Coding(
                    code: "531975".asFHIRStringPrimitive(),
                    display: "MDC_ID_PROD_SPEC_SW".asFHIRStringPrimitive(),
                    system: mdc
                )]),
                value: version.asFHIRStringPrimitive()
            )]
        }
        if let build = application.build {
            device.version = (device.version ?? []) + [DeviceVersion(
                type: CodeableConcept(coding: [Coding(
                    code: "build".asFHIRStringPrimitive(),
                    display: "Build".asFHIRStringPrimitive(),
                    system: Canonicals.groveApplicationVersionType
                )]),
                value: build.asFHIRStringPrimitive()
            )]
        }
        return device
    }

    static func hostDevice(_ host: SensorHostDevice) -> Device {
        var device = Device()
        device.meta = Meta(profile: [Profile.groveHostDevice])
        device.status = FHIRPrimitive(.active)
        device.manufacturer = host.manufacturer?.asFHIRStringPrimitive()
        device.modelNumber = host.modelNumber?.asFHIRStringPrimitive()
        if let name = host.name {
            device.deviceName = [DeviceDeviceName(
                name: name.asFHIRStringPrimitive(),
                type: FHIRPrimitive(.userFriendlyName)
            )]
        }
        device.version = [DeviceVersion(
            type: CodeableConcept(coding: [Coding(
                code: "os-version".asFHIRStringPrimitive(),
                display: "Operating system version".asFHIRStringPrimitive(),
                system: Canonicals.groveApplicationVersionType
            )]),
            value: host.operatingSystemVersion.asFHIRStringPrimitive()
        )]
        return device
    }

    static func recordingDevice(
        _ source: SensorRecordingDevice,
        identity: BusinessIdentifier,
        snapshot: BusinessIdentifier
    ) -> Device {
        var device = Device()
        device.meta = Meta(profile: [Profile.groveRecordingDevice])
        device.status = FHIRPrimitive(.active)
        device.identifier = [snapshot.fhirIdentifier, identity.fhirIdentifier]
        if let name = source.name {
            device.deviceName = [DeviceDeviceName(
                name: name.asFHIRStringPrimitive(),
                type: FHIRPrimitive(.userFriendlyName)
            )]
        }
        device.manufacturer = source.manufacturer?.asFHIRStringPrimitive()
        device.modelNumber = source.modelNumber?.asFHIRStringPrimitive()
        return device
    }

    static func provenance(
        sourceIdentifier: Identifier,
        targetURL: String,
        converterURL: String,
        recordedAt: Date
    ) throws -> Provenance {
        Provenance(
            activity: CodeableConcept(coding: [Coding(
                code: "transform".asFHIRStringPrimitive(),
                display: "Transform/Translate Record Lifecycle Event".asFHIRStringPrimitive(),
                system: lifecycleEvent
            )]),
            agent: [ProvenanceAgent(
                type: CodeableConcept(coding: [Coding(
                    code: "assembler".asFHIRStringPrimitive(),
                    display: "Assembler".asFHIRStringPrimitive(),
                    system: participantType
                )]),
                who: reference(converterURL)
            )],
            entity: [ProvenanceEntity(
                role: FHIRPrimitive(.source),
                what: Reference(identifier: sourceIdentifier)
            )],
            meta: Meta(profile: [GroveLifecycleContract.conversionProvenanceProfile]),
            occurred: .dateTime(FHIRPrimitive(try DateTime(date: recordedAt))),
            recorded: FHIRPrimitive(try Instant(date: recordedAt)),
            target: [reference(targetURL)]
        )
    }

    static func reference(_ url: String) -> Reference {
        Reference(reference: url.asFHIRStringPrimitive())
    }
}
