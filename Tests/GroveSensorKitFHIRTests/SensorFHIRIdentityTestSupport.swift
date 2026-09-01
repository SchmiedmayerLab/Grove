//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Fixed protocol-vector fixtures deliberately trap if a hard-coded identity becomes invalid.
// swiftlint:disable force_try type_contents_order

import Foundation
import GroveFHIRContract
@testable import GroveSensorKitFHIR
import ModelsR4


enum SensorFHIRIdentityTestSupport {
    static let producerInstance = UUID(uuid: (
        0xaa, 0xaa, 0xaa, 0xaa, 0xbb, 0xbb, 0x4c, 0xcc,
        0x8d, 0xdd, 0xee, 0xee, 0xee, 0xee, 0xee, 0xee
    ))
    static let entryNodeIdentifierSystem: IdentifierSystem =
        "https://grovealliance.org/fhir/testing/identifiers/exchange-entry-node"
    static let visitLocationIdentifierSystem: IdentifierSystem =
        "https://grovealliance.org/fhir/testing/identifiers/sensorkit-location"
    static let converterHost = SensorHostDevice(
        sourceDeviceToken: "test-converter-host",
        operatingSystemVersion: "20.1",
        name: "Test Host",
        manufacturer: "Example Device Company",
        modelNumber: "Phone One"
    )

    static var subjectIdentity: BusinessIdentifier {
        get throws {
            try BusinessIdentifier(
                system: "https://grovealliance.org/fhir/testing/identifiers/participant",
                value: "example"
            )
        }
    }

    static let subject = Reference(
        identifier: try! subjectIdentity.fhirIdentifier,
        type: FHIRPrimitive(FHIRURI(stringLiteral: ResourceType.patient.rawValue))
    )

    static func logicalReference(
        resourceType: ResourceType,
        value: String
    ) throws -> Reference {
        let identifier = try BusinessIdentifier(
            system: "https://grovealliance.org/fhir/testing/identifiers/\(resourceType.rawValue.lowercased())",
            value: value
        )
        return Reference(
            identifier: identifier.fhirIdentifier,
            type: FHIRPrimitive(FHIRURI(stringLiteral: resourceType.rawValue))
        )
    }

    static var repositoryScope: BusinessIdentifier {
        get throws {
            try BusinessIdentifier(
                system: "https://grovealliance.org/fhir/testing/identifiers/repository",
                value: "primary"
            )
        }
    }

    static var identityScope: PseudonymousIdentityScope {
        get throws {
            try PseudonymousIdentityScope(
                systems: PseudonymousIdentitySystems(
                    sourceRecord: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/source-record/test/1",
                    sourceOutput: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/source-output/test/1",
                    writerRecord: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/writer-record/test/1",
                    providerRecord: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/provider-record/test/1",
                    providerOutput: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/provider-output/test/1",
                    sourceArtifact: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/source-artifact/test/1",
                    providerArtifact: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/provider-artifact/test/1",
                    sourceContext: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/source-context/test/1",
                    recordingDevice: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/recording-device/test/1",
                    deviceSnapshot: "https://grovealliance.org/fhir/testing/identifiers/pseudonym/device-snapshot/test/1"
                ),
                keyID: "test",
                epoch: 1,
                key: Data(repeating: 0x42, count: 32)
            )
        }
    }

    static func event(sequence: UInt64 = 1) throws -> ExchangeEventIdentifier {
        try ExchangeEventIdentifier(
            system: "https://grovealliance.org/fhir/testing/identifiers/exchange-event",
            producerInstance: producerInstance,
            sequence: sequence
        )
    }

    static func sensorKitOutputs(
        sourceRecordID: SensorKitSourceRecordID,
        sourceToken: String,
        structuredDiscriminator: String?,
        includesNativeRecording: Bool
    ) throws -> [BusinessIdentifier] {
        var outputs: [BusinessIdentifier] = []
        if let structuredDiscriminator {
            outputs.append(try identityScope.sourceOutput(
                adapterID: "sensorkit",
                sourceType: sourceToken,
                repositoryScope: repositoryScope,
                nativeRecordID: sourceRecordID.value,
                outputRole: "structured",
                outputDiscriminator: structuredDiscriminator
            ))
        }
        if includesNativeRecording {
            outputs.append(try identityScope.sourceOutput(
                adapterID: "sensorkit",
                sourceType: sourceToken,
                repositoryScope: repositoryScope,
                nativeRecordID: sourceRecordID.value,
                outputRole: "native-recording",
                outputDiscriminator: "single"
            ))
        }
        return outputs
    }
}


extension SensorConversionContext {
    init(
        subject: Reference,
        converter: SensorApplication,
        graphIdentifierSystem: IdentifierSystem,
        recordingDevice: SensorRecordingDevice? = nil,
        converterWasGateway: Bool = false,
        conversionInstant: Date,
        researchStudies: [Reference] = [],
        repositoryIDs: SensorRepositoryIDs = .init()
    ) {
        self.init(
            subject: subject,
            subjectIdentity: try! SensorFHIRIdentityTestSupport.subjectIdentity,
            converter: converter,
            converterHost: SensorFHIRIdentityTestSupport.converterHost,
            adapterID: "sensor",
            eventIdentifier: try! ExchangeEventIdentifier(
                system: graphIdentifierSystem,
                producerInstance: SensorFHIRIdentityTestSupport.producerInstance,
                sequence: 1
            ),
            entryNodeIdentifierSystem: SensorFHIRIdentityTestSupport.entryNodeIdentifierSystem,
            identityScope: try! SensorFHIRIdentityTestSupport.identityScope,
            repositoryScope: try! SensorFHIRIdentityTestSupport.repositoryScope,
            recordingDevice: recordingDevice,
            converterWasGateway: converterWasGateway,
            conversionInstant: conversionInstant,
            researchStudies: researchStudies,
            repositoryIDs: repositoryIDs
        )
    }

    var graphIdentifierSystem: IdentifierSystem {
        eventIdentifier.businessIdentifier.system
    }
}


extension SensorSampledDataRecord {
    init(
        identifier: BusinessIdentifier,
        sourceTypeIdentifier: String,
        code: SensorCode,
        start: Date,
        samples: [Double],
        dimensions: Int = 1,
        periodMilliseconds: Double,
        origin: Double = 0,
        unitCode: String,
        unitDisplay: String? = nil
    ) throws {
        try self.init(
            nativeRecordID: identifier.value,
            sourceTypeIdentifier: sourceTypeIdentifier,
            code: code,
            start: start,
            samples: samples,
            dimensions: dimensions,
            periodMilliseconds: periodMilliseconds,
            origin: origin,
            unitCode: unitCode,
            unitDisplay: unitDisplay
        )
    }
}


extension SensorECGRecord {
    init(
        identifier: BusinessIdentifier,
        sourceTypeIdentifier: String,
        start: Date,
        periodMilliseconds: Double,
        channels: [SensorECGChannel]
    ) throws {
        try self.init(
            nativeRecordID: identifier.value,
            sourceTypeIdentifier: sourceTypeIdentifier,
            start: start,
            periodMilliseconds: periodMilliseconds,
            channels: channels
        )
    }
}


extension SensorRecordingDocument {
    init(
        identifier: BusinessIdentifier,
        sourceTypeIdentifier: String,
        type: SensorCode,
        title: String,
        format: RegisteredRecordingFormat,
        payload: Payload,
        rawPayloadAdmission: SensorRawPayloadAdmission?,
        related: [BusinessIdentifier] = []
    ) throws {
        try self.init(
            nativeRecordID: identifier.value,
            sourceTypeIdentifier: sourceTypeIdentifier,
            type: type,
            title: title,
            format: format,
            payload: payload,
            rawPayloadAdmission: rawPayloadAdmission,
            related: related
        )
    }
}


extension SensorConverter {
    func convert<S: Sequence>(
        _ records: S,
        context: SensorConversionContext
    ) -> SensorBatchResult where S.Element == SensorRecord {
        convert(records) { _ in context }
    }
}
