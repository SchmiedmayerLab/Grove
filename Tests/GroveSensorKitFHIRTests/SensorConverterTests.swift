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
                converter: ApplicationDevice.test(name: "Grove Conformance Fixture", bundleIdentifier: "org.grovealliance.conformance-fixture", version: "0.5.0"),
                graphIdentifierSystem: "https://study.example.org/fhir/identifiers/sensor-graph",
                recordingDevice: RecordingDevice.test(
                    stableUnitToken: "watch-42",
                    name: "Example Watch",
                    manufacturer: "Example",
                    modelNumber: "W42"
                ),
                converterWasGateway: true,
                conversionInstant: Self.start.addingTimeInterval(20)
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
            subject: base.event.subject,
            converter: base.event.application,
            graphIdentifierSystem: base.graphIdentifierSystem,
            recordingDevice: base.recordingDevice,
            conversionInstant: base.conversionInstant,
            repositoryIDs: [
                .bundle: try RepositoryID("bundle-1"),
                .primaryOutput: try RepositoryID("observation-1"),
                .recordingDevice: try RepositoryID("device-1"),
                .applicationDevice: try RepositoryID("application-1"),
                .provenance: try RepositoryID("provenance-1")
            ]
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
        let identifiers = try #require(document.identifier).map(RoledIdentifier.init)
        #expect(identifiers.map(\.role) == [.sourceRecord, .sourceOutput, .sourceArtifact])
        #expect(document.content.count == 1)
        #expect(attachment.data == nil)
        #expect(attachment.url?.value?.url.absoluteString == "payloads/ambient-light/session-1.json")
        #expect(attachment.contentType?.value?.string == RegisteredRecordingFormat.nativeRecording.registeredContentType)
        #expect(attachment.size?.value?.integer == 2)
        #expect(attachment.hash != nil)
        let format = try #require(document.content.first?.format)
        #expect(format.system?.value?.url.absoluteString == RecordingFormatContract.recordingFormatCodeSystem)
        #expect(format.code?.value?.string == "native-recording")
        #expect(format.version == nil)
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
            subject: base.event.subject,
            converter: base.event.application,
            graphIdentifierSystem: base.graphIdentifierSystem,
            recordingDevice: base.recordingDevice,
            conversionInstant: base.conversionInstant,
            repositoryIDs: [.provenance: try RepositoryID("provenance-1")]
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

    @Test("An identity fault reports its own registry code through both sensor adapters")
    func identityFaultsKeepTheirCodes() {
        let opaque = [
            OpaqueIdentityError.emptyComponent("source-record.native-record-id"),
            .nonCanonicalPartIndex("source-artifact.part-index")
        ]
        for fault in opaque {
            #expect(SensorConversionError.opaqueIdentity(fault).diagnostic == fault.diagnostic)
            #expect(SensorKitConversionError.opaqueIdentity(fault).diagnostic == fault.diagnostic)
        }
        #expect(opaque.map(\.diagnostic.code) == ["mobile-input.required-metadata-missing", "mobile-input.unclassified"])
        let malformed = ExchangeIdentityError.invalidEventIdentifier("e0:x")
        #expect(SensorConversionError.exchangeIdentity(malformed).diagnostic.code == "mobile-exchange.event-identity")
        #expect(SensorKitConversionError.exchangeIdentity(malformed).diagnostic == malformed.diagnostic)
    }

    @Test("Effective bounds state the source's zone, else UTC with a warning, never the host's")
    func effectiveBoundsNeverTakeTheHostZone() throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let end = Self.start.addingTimeInterval(600)
        let named = try SensorConverter.period(start: Self.start, end: end, sourceTimeZone: zone)
        #expect(named.start?.value?.description == "2026-08-17T16:30:00-07:00")
        #expect(named.end?.value?.description == "2026-08-17T16:40:00-07:00")
        let unnamed = try SensorConverter.period(start: Self.start, end: end, sourceTimeZone: nil)
        #expect(unnamed.start?.value?.description == "2026-08-17T23:30:00Z")
        #expect(unnamed.end?.value?.description == "2026-08-17T23:40:00Z")

        let context = try Self.context
        let lossy = try SensorConverter().convert(.sampledData(Self.sampledData()), context: context)
        #expect(lossy.warnings == [
            .sourceOffsetUnavailable(field: "Observation.effectivePeriod.start"),
            .sourceOffsetUnavailable(field: "Observation.effectivePeriod.end")
        ])
        #expect(lossy.warnings.map(\.diagnostic.location) == ["Observation.effectivePeriod.start", "Observation.effectivePeriod.end"])
        #expect(lossy.warnings.allSatisfy { $0.diagnostic.code == "mobile-omission.source-offset" && $0.diagnostic.severity == .warning })

        let stated = try SensorConverter().convert(
            .sampledData(Self.sampledData()),
            context: SensorConversionContext(
                event: context.event,
                adapterID: context.adapterID,
                recordingDevice: context.recordingDevice,
                sourceTimeZone: zone
            )
        )
        #expect(stated.warnings.isEmpty)
        guard case .observation(let observation) = stated.primaryResource, case .period(let period)? = observation.effective else {
            Issue.record("The sampled data did not become an Observation with an effective period")
            return
        }
        #expect(period.start?.value?.description == "2026-08-17T16:30:00-07:00")
    }

    @Test("Clock instants are UTC, so the same event yields the same bytes whatever zone the host is in")
    func clockInstantsIgnoreTheHostZone() throws {
        let base = try Self.context
        func bytes(_ zone: String) throws -> Data {
            let context = SensorConversionContext(
                event: base.event,
                adapterID: base.adapterID,
                recordingDevice: base.recordingDevice,
                sourceTimeZone: try #require(TimeZone(identifier: zone))
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return try encoder.encode(SensorConverter().convert(.recordingDocument(Self.recordingDocument()), context: context).bundle)
        }
        #expect(try bytes("America/Los_Angeles") == bytes("Asia/Tokyo"))

        let conversion = try SensorConverter().convert(.recordingDocument(Self.recordingDocument()), context: base)
        #expect(conversion.bundle.timestamp?.value?.description == "2026-08-17T23:30:20Z")
        #expect(conversion.provenance.recorded.value?.description == "2026-08-17T23:30:20Z")
        guard case .dateTime(let occurred)? = conversion.provenance.occurred,
              case .recordingDocument(let document) = conversion.primaryResource else {
            Issue.record("The recording document graph lost its Provenance time or its document")
            return
        }
        #expect(occurred.value?.description == "2026-08-17T23:30:20Z")
        #expect(document.date?.value?.description == "2026-08-17T23:30:20Z")
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
