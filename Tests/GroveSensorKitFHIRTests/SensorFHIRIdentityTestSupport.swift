//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Fixed protocol-vector fixtures deliberately trap if a hard-coded identity becomes invalid.
// swiftlint:disable force_try type_contents_order

import CryptoKit
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
    static let converterHost = try! HostDevice(
        operatingSystemVersion: "20.1",
        name: "Test Host",
        manufacturer: "Example Device Company",
        modelNumber: "Phone One"
    )
    static let subjectIdentity = try! BusinessIdentifier(
        system: "https://grovealliance.org/fhir/testing/identifiers/participant",
        value: "example"
    )
    static let subject: Subject = .logical(subjectIdentity)
    static let repositoryScope = try! BusinessIdentifier(
        system: "https://grovealliance.org/fhir/testing/identifiers/repository",
        value: "primary"
    )
    static let identityScope = try! OpaqueIdentityScope(
        systems: DeploymentIdentifierSystems(
            opaque: OpaqueIdentitySystems(
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
            event: "https://grovealliance.org/fhir/testing/identifiers/exchange-event",
            entryNode: entryNodeIdentifierSystem
        ),
        keyID: "test",
        epoch: EventSequence(1),
        key: SymmetricKey(data: Data(repeating: 0x42, count: 32))
    )

    static func event(sequence: UInt64 = 1) throws -> ExchangeEventIdentifier {
        try ExchangeEventIdentifier(
            system: "https://grovealliance.org/fhir/testing/identifiers/exchange-event",
            producerInstance: producerInstance,
            sequence: EventSequence(sequence)
        )
    }

    static func eventContext(
        subject: Subject = subject,
        converter: ApplicationDevice,
        event: ExchangeEventIdentifier,
        converterWasGateway: Bool,
        conversionInstant: Date,
        studies: [StudyEnrollment] = [],
        repositoryIDs: [ExchangeGraphNode: RepositoryID] = [:]
    ) -> ExchangeEventContext {
        ExchangeEventContext(
            subject: subject,
            event: event,
            identityScope: identityScope,
            repositoryScope: repositoryScope,
            application: converter,
            host: converterHost,
            conversionInstant: conversionInstant,
            converterRole: converterWasGateway ? .gateway : .assembler,
            studies: studies,
            repositoryIDs: repositoryIDs
        )
    }

    static func sensorKitOutputs(
        sourceRecordID: SensorKitSourceRecordID,
        sourceToken: String,
        structuredDiscriminator: String?,
        includesNativeRecording: Bool
    ) throws -> [RoledIdentifier] {
        var outputs: [RoledIdentifier] = []
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


extension ApplicationDevice {
    static func test(name: String, bundleIdentifier: String, version: String) -> ApplicationDevice {
        try! ApplicationDevice(name: name, bundleIdentifier: bundleIdentifier, version: version)
    }
}


extension RecordingDevice {
    static func test(
        stableUnitToken: String,
        name: String? = nil,
        manufacturer: String? = nil,
        modelNumber: String? = nil
    ) -> RecordingDevice {
        try! RecordingDevice(stableUnitToken: stableUnitToken, name: name, manufacturer: manufacturer, modelNumber: modelNumber)
    }
}


extension RoledIdentifier {
    var value: String { identifier.value }
    var system: IdentifierSystem { identifier.system }
    var systemValue: String { identifier.system.rawValue }
}


/// Keeps the fixtures concise while production callers build the shared event context themselves.
extension SensorConversionContext {
    init(
        subject: Subject = SensorFHIRIdentityTestSupport.subject,
        converter: ApplicationDevice,
        graphIdentifierSystem: IdentifierSystem,
        recordingDevice: RecordingDevice? = nil,
        converterWasGateway: Bool = false,
        conversionInstant: Date,
        studies: [StudyEnrollment] = [],
        repositoryIDs: [ExchangeGraphNode: RepositoryID] = [:]
    ) {
        self.init(
            event: SensorFHIRIdentityTestSupport.eventContext(
                subject: subject,
                converter: converter,
                event: try! ExchangeEventIdentifier(
                    system: graphIdentifierSystem,
                    producerInstance: SensorFHIRIdentityTestSupport.producerInstance,
                    sequence: EventSequence(1)
                ),
                converterWasGateway: converterWasGateway,
                conversionInstant: conversionInstant,
                studies: studies,
                repositoryIDs: repositoryIDs
            ),
            adapterID: "sensor",
            recordingDevice: recordingDevice
        )
    }

    var graphIdentifierSystem: IdentifierSystem {
        eventIdentifier.identifier.system
    }
}


extension SensorKitConversionContext {
    init(
        subject: Subject = SensorFHIRIdentityTestSupport.subject,
        converter: ApplicationDevice,
        eventIdentifier: ExchangeEventIdentifier,
        visitLocationIdentifierSystem: IdentifierSystem = SensorFHIRIdentityTestSupport.visitLocationIdentifierSystem,
        sourceIdentifierDisclosurePolicy: GovernedSourceIdentifierDisclosurePolicy = .omit,
        recordingDevice: RecordingDevice? = nil,
        converterWasGateway: Bool = false,
        sourceTimeZone: TimeZone,
        conversionInstant: Date,
        studies: [StudyEnrollment] = [],
        repositoryIDs: [ExchangeGraphNode: RepositoryID] = [:]
    ) {
        self.init(
            event: SensorFHIRIdentityTestSupport.eventContext(
                subject: subject,
                converter: converter,
                event: eventIdentifier,
                converterWasGateway: converterWasGateway,
                conversionInstant: conversionInstant,
                studies: studies,
                repositoryIDs: repositoryIDs
            ),
            visitLocationIdentifierSystem: visitLocationIdentifierSystem,
            sourceIdentifierDisclosurePolicy: sourceIdentifierDisclosurePolicy,
            recordingDevice: recordingDevice,
            sourceTimeZone: sourceTimeZone
        )
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
