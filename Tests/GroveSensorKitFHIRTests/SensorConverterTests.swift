//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The graph tests keep full FHIR construction and relationship assertions together.
// swiftlint:disable function_body_length type_body_length

import Foundation
import GroveFHIRContract
@testable import GroveSensorKitFHIR
import ModelsR4
import Testing


@Suite
struct SensorFHIRConverterTests {
    private static let start = Date(timeIntervalSince1970: 1_787_009_400)
    private static let subject = SensorFHIRIdentityTestSupport.subject

    private static var context: SensorConversionContext {
        get throws {
            SensorConversionContext(
                subject: Self.subject,
                converter: SensorApplication(
                    sourceDeviceToken: "org.grovealliance.conformance-fixture",
                    name: "Grove Conformance Fixture",
                    version: "0.5.0"
                ),
                graphIdentifierSystem: "https://study.example.org/fhir/identifiers/sensor-graph",
                recordingDevice: SensorRecordingDevice(
                    identifier: try BusinessIdentifier(
                        system: "https://study.example.org/fhir/identifiers/recording-device",
                        value: "watch-42"
                    ),
                    stableUnitToken: "watch-42",
                    name: "Example Watch",
                    manufacturer: "Example",
                    modelNumber: "W42"
                ),
                converterWasGateway: true,
                recordedAt: Self.start.addingTimeInterval(20)
            )
        }
    }

    private static func sampledData() throws -> SensorSampledDataRecord {
        try SensorSampledDataRecord(
            identifier: BusinessIdentifier(
                system: "https://study.example.org/fhir/identifiers/sensorkit-record",
                value: "accelerometer-session-1"
            ),
            sourceTypeIdentifier: "SRSensor.accelerometer",
            code: SensorCode(
                system: "https://grovealliance.org/fhir/sensorkit/CodeSystem/sensorkit-sample-type",
                code: "accelerometer",
                display: "Accelerometer"
            ),
            start: Self.start,
            samples: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6],
            dimensions: 3,
            periodMilliseconds: 10,
            unitCode: "m/s2",
            unitDisplay: "m/s²"
        )
    }

    private static func recordingDocument(
        rawPayloadAdmission: SensorRawPayloadAdmission = .callerAuthorizedOpaquePayload
    ) throws -> SensorRecordingDocument {
        try SensorRecordingDocument(
            identifier: BusinessIdentifier(
                system: "https://study.example.org/fhir/identifiers/sensorkit-record",
                value: "ambient-light-session-1"
            ),
            sourceTypeIdentifier: "SRSensor.ambientLightSensor",
            type: SensorCode(
                system: "https://grovealliance.org/fhir/sensorkit/CodeSystem/sensorkit-sample-type",
                code: "ambient-light",
                display: "Ambient light recording"
            ),
            title: "Ambient light SensorKit batch",
            format: .nativeRecording,
            payload: .sidecar(path: "payloads/ambient-light/session-1.json", bytes: Data("[]".utf8)),
            rawPayloadAdmission: rawPayloadAdmission
        )
    }

    @Test
    func sampledDataGraphUsesBusinessIdentityAndInternalUUIDReferences() throws {
        let first = try SensorConverter().convert(.sampledData(Self.sampledData()), context: Self.context)
        let second = try SensorConverter().convert(.sampledData(Self.sampledData()), context: Self.context)
        let entries = try #require(first.bundle.entry)
        guard case .observation(let observation) = first.primaryResource else {
            Issue.record("Expected a sampled-data Observation")
            return
        }

        #expect(first.bundle.id == nil)
        #expect(observation.id == nil)
        #expect(first.recordingDevice?.id == nil)
        #expect(first.converterApplication.id == nil)
        #expect(first.provenance.id == nil)
        #expect(observation.meta?.profile == [Profile.groveSensorSampledDataObservation])
        #expect(first.bundle.meta?.profile == [Profile.groveMobileExchangeBundle])
        #expect(first.bundle.identifier == first.graphIdentifiers.event.fhirIdentifier)
        #expect(entries.count == 5)
        #expect(entries.compactMap(\.fullUrl) == second.bundle.entry?.compactMap(\.fullUrl))
        #expect(entries.allSatisfy { entry in
            entry.fullUrl?.value?.url.absoluteString.hasPrefix("urn:uuid:") == true
                && entry.extension?.filter {
                    $0.url == Canonicals.entryNodeKey
                }.count == 1
        })
        try ExchangeIdentity.validate(entries: entries)

        let fullURLs = Set(entries.compactMap { $0.fullUrl?.value?.url.absoluteString })
        #expect(fullURLs.contains(observation.device?.reference?.value?.string ?? ""))
        #expect(fullURLs.contains(first.provenance.target.first?.reference?.value?.string ?? ""))
        #expect(fullURLs.contains(first.provenance.agent.first?.who.reference?.value?.string ?? ""))
        #expect(observation.extension?.contains { extensionValue in
            guard extensionValue.url == Canonicals.gatewayDevice,
                  case .reference(let reference) = extensionValue.value else {
                return false
            }
            return fullURLs.contains(reference.reference?.value?.string ?? "")
        } == true)

        guard case .sampledData(let value) = observation.value else {
            Issue.record("Expected valueSampledData")
            return
        }
        #expect(value.dimensions.value?.integer == 3)
        #expect(value.period.value?.decimal == 10)
        #expect(value.data?.value?.string == "0.1 0.2 0.3 0.4 0.5 0.6")
    }

    @Test
    func repositoryIDsAreAppliedOnlyWhenExplicitlyAssigned() throws {
        let base = try Self.context
        let context = SensorConversionContext(
            subject: base.subject,
            converter: base.converter,
            graphIdentifierSystem: base.graphIdentifierSystem,
            recordingDevice: base.recordingDevice,
            recordedAt: base.recordedAt,
            repositoryIDs: SensorRepositoryIDs(
                bundle: try RepositoryID("bundle-1"),
                record: try RepositoryID("observation-1"),
                recordingDevice: try RepositoryID("device-1"),
                converterApplication: try RepositoryID("application-1"),
                provenance: try RepositoryID("provenance-1")
            )
        )
        let conversion = try SensorConverter().convert(
            .sampledData(Self.sampledData()),
            context: context
        )
        guard case .observation(let observation) = conversion.primaryResource else {
            Issue.record("Expected an Observation")
            return
        }

        #expect(conversion.bundle.id?.value?.string == "bundle-1")
        #expect(observation.id?.value?.string == "observation-1")
        #expect(conversion.recordingDevice?.id?.value?.string == "device-1")
        #expect(conversion.converterApplication.id?.value?.string == "application-1")
        #expect(conversion.provenance.id?.value?.string == "provenance-1")
    }

    @Test
    func recordingDocumentPreservesExactlyOnePayloadLocation() throws {
        let conversion = try SensorConverter().convert(
            .recordingDocument(Self.recordingDocument()),
            context: Self.context
        )
        guard case .recordingDocument(let document) = conversion.primaryResource else {
            Issue.record("Expected a recording DocumentReference")
            return
        }
        let attachment = try #require(document.content.first?.attachment)

        #expect(document.meta?.profile == [Profile.groveSensorRecordingDocument])
        #expect(document.id == nil)
        let identifiers = try #require(document.identifier).map(BusinessIdentifier.init)
        #expect(identifiers.map(\.role) == [.sourceRecord, .sourceOutput, .sourceArtifact])
        #expect(document.content.count == 1)
        #expect(attachment.data == nil)
        #expect(attachment.url?.value?.url.absoluteString == "payloads/ambient-light/session-1.json")
        #expect(attachment.contentType?.value?.string == "application/vnd.grovealliance.native+json")
        #expect(attachment.size?.value?.integer == 2)
        #expect(attachment.hash != nil)
        let format = try #require(document.content.first?.format)
        #expect(format.system?.value?.url.absoluteString == SensorKitContract.recordingFormatCodeSystem)
        #expect(format.code?.value?.string == "native-recording")
        #expect(conversion.provenance.meta?.profile == [
            GroveLifecycleContract.conversionProvenanceProfile
        ])
        #expect(conversion.graphIdentifiers.provenance.role == .entryNode)
        #expect(conversion.bundle.entry?.count == 5)
    }

    @Test(arguments: SensorRawPayloadAdmission.allCases)
    func rawPayloadAdmissionIsAcceptedButNeverSerialized(
        _ admission: SensorRawPayloadAdmission
    ) throws {
        let conversion = try SensorConverter().convert(
            .recordingDocument(Self.recordingDocument(rawPayloadAdmission: admission)),
            context: Self.context
        )
        let encoded = try JSONEncoder().encode(conversion.bundle)
        let json = try #require(String(data: encoded, encoding: .utf8))

        for value in SensorRawPayloadAdmission.allCases {
            #expect(!json.contains(value.rawValue))
        }
        #expect(!json.contains("callerAuthorizedOpaquePayload"))
        #expect(!json.contains("verifiedSanitizedInput"))
        #expect(!json.contains("rawPayloadAdmission"))
    }

    @Test
    func batchConversionReportsEveryFailureWithoutDroppingInput() throws {
        let base = try Self.context
        let context = SensorConversionContext(
            subject: base.subject,
            converter: base.converter,
            graphIdentifierSystem: base.graphIdentifierSystem,
            recordingDevice: base.recordingDevice,
            recordedAt: base.recordedAt,
            repositoryIDs: SensorRepositoryIDs(
                provenance: try RepositoryID("provenance-1")
            )
        )
        let sampledData = try Self.sampledData()
        let document = try Self.recordingDocument()
        let result = SensorConverter().convert(
            [.sampledData(sampledData), .recordingDocument(document)],
            context: context
        )

        #expect(result.conversions.count == 2)
        #expect(result.failures.isEmpty)
        #expect(Set(result.conversions.map(\.sourceTypeIdentifier)) == Set([
            sampledData.sourceTypeIdentifier,
            document.sourceTypeIdentifier
        ]))
    }

    @Test
    func invalidRecordsFailClosedBeforeSerialization() throws {
        let identifier = try BusinessIdentifier(
            system: "https://study.example.org/fhir/identifiers/sensorkit-record",
            value: "invalid-record"
        )
        let code = try SensorCode(system: "http://loinc.org", code: "8867-4")

        #expect(throws: SensorRecordError.emptySamples) {
            try SensorSampledDataRecord(
                identifier: identifier,
                sourceTypeIdentifier: "SRSensor.heartRate",
                code: code,
                start: Self.start,
                samples: [],
                periodMilliseconds: 1_000,
                unitCode: "/min"
            )
        }
        #expect(throws: SensorRecordError.sampleCountNotDivisibleByDimensions(
            sampleCount: 2,
            dimensions: 3
        )) {
            try SensorSampledDataRecord(
                identifier: identifier,
                sourceTypeIdentifier: "SRSensor.accelerometer",
                code: code,
                start: Self.start,
                samples: [1, 2],
                dimensions: 3,
                periodMilliseconds: 10,
                unitCode: "m/s2"
            )
        }
        #expect(throws: SensorRecordError.nonFiniteSample(index: 1)) {
            try SensorECGChannel(lead: code, millivolts: [0, .infinity])
        }
        #expect(throws: SensorRecordError.invalidSidecarPath("../outside.json")) {
            try SensorRecordingDocument(
                identifier: identifier,
                sourceTypeIdentifier: "SRSensor.ambientLightSensor",
                type: code,
                title: "Invalid",
                format: .nativeRecording,
                payload: .sidecar(path: "../outside.json", bytes: Data("{}".utf8)),
                rawPayloadAdmission: .callerAuthorizedOpaquePayload
            )
        }
        #expect(throws: SensorRecordError.rawPayloadAdmissionRequired) {
            try SensorRecordingDocument(
                identifier: identifier,
                sourceTypeIdentifier: "SRSensor.ambientLightSensor",
                type: code,
                title: "Unreviewed native payload",
                format: .nativeRecording,
                payload: .inline(Data("{}".utf8)),
                rawPayloadAdmission: nil
            )
        }
    }
}
