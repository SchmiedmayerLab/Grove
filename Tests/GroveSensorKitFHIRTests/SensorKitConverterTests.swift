//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Profile arrays are formatted to mirror their normative order in the IG contract.
// swiftlint:disable multiline_literal_brackets

import Foundation
import GroveFHIRContract
@testable import GroveSensorKitFHIR
import ModelsR4
import Testing


@Suite
struct GroveSensorKitFHIRConverterTests {
    private static let start = Date(timeIntervalSince1970: 1_787_009_400)
    private static var sourceID: SensorKitSourceRecordID {
        get throws {
            SensorKitSourceRecordID(try #require(
                UUID(uuidString: "879d9ea2-21cb-4527-b59b-2831dc4c84ab")
            ))
        }
    }

    private static var context: SensorKitConversionContext {
        get throws {
            SensorKitConversionContext(
                subject: Reference(reference: "Patient/example"),
                converter: SensorApplication(
                    identifier: try BusinessIdentifier(
                        system: "https://study.example.org/fhir/identifiers/application",
                        value: "sensor-conformance|0.3.0"
                    ),
                    name: "Sensor Conformance",
                    version: "0.5.0"
                ),
                graphIdentifierSystem: "https://study.example.org/fhir/identifiers/sensor-graph",
                recordingDevice: SensorRecordingDevice(
                    identifier: try BusinessIdentifier(
                        system: "https://study.example.org/fhir/identifiers/device",
                        value: "watch-42"
                    ),
                    name: "Example Watch"
                ),
                converterWasGateway: true,
                sourceTimeZone: try #require(TimeZone(identifier: "America/Los_Angeles")),
                issuedAt: start.addingTimeInterval(30),
                recordedAt: start.addingTimeInterval(60)
            )
        }
    }

    private static func native(
        admission: SensorRawPayloadAdmission = .verifiedSanitizedInput,
        format: RegisteredRecordingFormat = .nativeRecording
    ) throws -> SensorKitNativeRecording {
        try SensorKitNativeRecording(
            title: "Exact SensorKit native record",
            contentType: "application/json",
            format: format,
            payload: .inline(Data(#"{"flags":[0,2,1,0]}"#.utf8)),
            admission: admission
        )
    }

    @Test(arguments: [
        ("sampled-data", "v1:879d9ea2-21cb-4527-b59b-2831dc4c84ab|sampled-data"),
        ("native-recording", "v1:879d9ea2-21cb-4527-b59b-2831dc4c84ab|native-recording"),
        ("on-wrist", "v1:879d9ea2-21cb-4527-b59b-2831dc4c84ab|on-wrist"),
        ("device-usage-summary", "v1:879d9ea2-21cb-4527-b59b-2831dc4c84ab|device-usage-summary"),
        ("ecg-waveform", "v1:879d9ea2-21cb-4527-b59b-2831dc4c84ab|ecg-waveform"),
        ("visit-summary", "v1:879d9ea2-21cb-4527-b59b-2831dc4c84ab|visit-summary"),
        ("messages-usage-summary", "v1:879d9ea2-21cb-4527-b59b-2831dc4c84ab|messages-usage-summary"),
        ("phone-usage-summary", "v1:879d9ea2-21cb-4527-b59b-2831dc4c84ab|phone-usage-summary"),
        ("keyboard-metrics-summary", "v1:879d9ea2-21cb-4527-b59b-2831dc4c84ab|keyboard-metrics-summary"),
        ("sleep-session", "v1:879d9ea2-21cb-4527-b59b-2831dc4c84ab|sleep-session"),
        ("accelerometer-recording-summary", "v1:879d9ea2-21cb-4527-b59b-2831dc4c84ab|accelerometer-recording-summary"),
        ("ppg-recording-summary", "v1:879d9ea2-21cb-4527-b59b-2831dc4c84ab|ppg-recording-summary")
    ])
    func outputIdentityMatchesCatalogVector(testCase: (String, String)) throws {
        let identifier = try SensorKitOutputIdentity.businessIdentifier(
            source: Self.sourceID,
            discriminator: testCase.0
        )
        #expect(identifier.systemValue == SensorKitContract.outputIdentifierSystem)
        #expect(identifier.value == testCase.1)
    }

    @Test
    func rotationRateBuildsExactStructuredGraph() throws {
        let record = SensorKitRotationRateRecord(
            sourceRecordID: try Self.sourceID,
            samples: [
                .init(timestamp: Self.start, x: 0.01, y: -0.02, z: 0.03),
                .init(timestamp: Self.start.addingTimeInterval(0.01), x: 0.02, y: -0.01, z: 0.04),
                .init(timestamp: Self.start.addingTimeInterval(0.02), x: 0.01, y: -0.01, z: 0.02)
            ]
        )
        let conversion = try SensorKitConverter().convert(.rotationRate(record), context: Self.context)
        let observation = try #require(conversion.observations.first)
        let entries = try #require(conversion.bundle.entry)

        #expect(observation.id == nil)
        #expect(observation.meta?.profile == [
            Profile.groveSensorSampledDataObservation,
            FHIRPrimitive(Canonical(stringLiteral: SensorKitContract.observationProfile))
        ])
        #expect(observation.identifier?.map { $0.system?.value?.url.absoluteString } == [
            SensorKitContract.sourceRecordIdentifierSystem,
            SensorKitContract.outputIdentifierSystem
        ])
        #expect(conversion.recordingDocument == nil)
        #expect(conversion.provenance.target.count == 1)
        #expect(entries.count == 4)
        #expect(entries.allSatisfy { $0.fullUrl?.value?.url.absoluteString.hasPrefix("urn:uuid:") == true })
        try ExchangeIdentity.validate(entries: entries)

        guard case .sampledData(let sampled) = observation.value,
              case .period(let effective) = observation.effective else {
            Issue.record("Rotation rate must emit SampledData over a Period")
            return
        }
        #expect(sampled.period.value?.decimal == 10)
        #expect(sampled.dimensions.value?.integer == 3)
        #expect(sampled.data?.value?.string == "0.01 -0.02 0.03 0.02 -0.01 0.04 0.01 -0.01 0.02")
        #expect(effective.start?.value?.description == "2026-08-17T16:30:00-07:00")
        #expect(effective.end?.value?.description == "2026-08-17T16:30:00.02-07:00")
    }

    @Test
    func ecgBuildsLosslessHybridGraphWithOneAuditTargetPerOutput() throws {
        let record = SensorKitECGRecord(
            sourceRecordID: try Self.sourceID,
            startDate: Self.start,
            durationSeconds: 0.006,
            frequencyHertz: 500,
            lead: .leftArmMinusRightArm,
            guidance: .guided,
            batches: [
                .init(offsetSeconds: 0, millivolts: [0.011, 0.023]),
                .init(offsetSeconds: 0.004, millivolts: [-0.005, 0.014])
            ],
            nativeRecording: try Self.native()
        )
        let conversion = try SensorKitConverter().convert(.electrocardiogram(record), context: Self.context)
        let observation = try #require(conversion.observations.first)
        let document = try #require(conversion.recordingDocument)
        let entries = try #require(conversion.bundle.entry)

        #expect(observation.meta?.profile == [
            Profile.groveSensorEcgObservation,
            FHIRPrimitive(Canonical(stringLiteral: SensorKitContract.ecgObservationProfile))
        ])
        #expect(document.meta?.profile == [
            FHIRPrimitive(Canonical(stringLiteral: SensorKitContract.sensorRecordingDocumentProfile)),
            FHIRPrimitive(Canonical(stringLiteral: SensorKitContract.recordingDocumentProfile))
        ])
        let format = try #require(document.content.first?.format)
        #expect(format.system?.value?.url.absoluteString == SensorKitContract.recordingFormatCodeSystem)
        #expect(format.code?.value?.string == "native-recording")
        #expect(observation.derivedFrom?.first?.reference?.value?.string == entries[1].fullUrl?.value?.url.absoluteString)
        #expect(conversion.provenance.target.count == 2)
        #expect(conversion.provenance.meta?.profile == [FHIRPrimitive(Canonical(
            stringLiteral: SensorKitContract.conversionProvenanceProfile
        ))])
        #expect(entries.count == 5)
        #expect(conversion.outputIdentifiers.map(\.value) == [
            "v1:879d9ea2-21cb-4527-b59b-2831dc4c84ab|ecg-waveform",
            "v1:879d9ea2-21cb-4527-b59b-2831dc4c84ab|native-recording"
        ])
        guard case .period(let effective) = observation.effective,
              case .sampledData(let waveform) = observation.component?.first?.value else {
            Issue.record("ECG must emit one SampledData lead over a Period")
            return
        }
        #expect(effective.start?.value?.description == "2026-08-17T16:30:00-07:00")
        #expect(effective.end?.value?.description == "2026-08-17T16:30:00.006-07:00")
        #expect(waveform.period.value?.decimal == 2)
        #expect(waveform.data?.value?.string == "0.011 0.023 -0.005 0.014")
    }

    @Test
    func inverseECGLeadIsNeverMislabeledAsStandardLeadI() throws {
        let record = SensorKitECGRecord(
            sourceRecordID: try Self.sourceID,
            startDate: Self.start,
            durationSeconds: 0.002,
            frequencyHertz: 500,
            lead: .rightArmMinusLeftArm,
            guidance: .unguided,
            batches: [.init(offsetSeconds: 0, millivolts: [0.1, 0.2])],
            nativeRecording: try Self.native()
        )
        let conversion = try SensorKitConverter().convert(.electrocardiogram(record), context: Self.context)
        let codings = try #require(conversion.observations.first?.component?.first?.code.coding)

        #expect(codings.contains { $0.system?.value?.url.absoluteString == SensorKitContract.ecgLeadCodeSystem })
        #expect(!codings.contains {
            $0.system?.value?.url.absoluteString == "urn:iso:std:iso:11073:10101"
                && $0.code?.value?.string == "131329"
        })
    }

    @Test
    func nonuniformECGFailsClosed() throws {
        let record = SensorKitECGRecord(
            sourceRecordID: try Self.sourceID,
            startDate: Self.start,
            durationSeconds: 0.006,
            frequencyHertz: 500,
            lead: .leftArmMinusRightArm,
            guidance: .guided,
            batches: [
                .init(offsetSeconds: 0, millivolts: [0.1, 0.2]),
                .init(offsetSeconds: 0.005, millivolts: [0.3, 0.4])
            ],
            nativeRecording: try Self.native()
        )
        #expect(throws: SensorKitConversionError.invalidRecord(.nonUniformTiming(index: 2))) {
            try SensorKitConverter().convert(.electrocardiogram(record), context: Self.context)
        }
    }

    @Test(arguments: SensorRawPayloadAdmission.allCases)
    func rawAdmissionIsConsumedButNeverSerialized(_ admission: SensorRawPayloadAdmission) throws {
        let record = SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.heartRate",
            nativeRecording: try Self.native(admission: admission, format: .heartRateSamples)
        )
        let conversion = try SensorKitConverter().convert(.raw(record), context: Self.context)
        let json = try #require(String(data: JSONEncoder().encode(conversion.bundle), encoding: .utf8))

        for value in SensorRawPayloadAdmission.allCases {
            #expect(!json.contains(value.rawValue))
        }
        #expect(conversion.observations.isEmpty)
        #expect(conversion.recordingDocument?.content.first?.format?.code?.value?.string == "heart-rate-samples")
        #expect(conversion.provenance.target.count == 1)
    }

    @Test
    func unregisteredRecordingFormatFailsClosed() throws {
        let record = SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.heartRate",
            nativeRecording: try Self.native(format: .nativeRecording)
        )
        #expect(throws: SensorKitConversionError.invalidRecord(
            .recordingFormatNotAdmitted("native-recording")
        )) {
            try SensorKitConverter().convert(.raw(record), context: Self.context)
        }
    }

    @Test
    func structuredOnlyStreamCannotClaimRawSupport() throws {
        let record = SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.sleepSessions",
            nativeRecording: try Self.native()
        )
        #expect(throws: SensorKitConversionError.invalidRecord(
            .sourceTypeHasNoRawContract("SRSensor.sleepSessions")
        )) {
            try SensorKitConverter().convert(.raw(record), context: Self.context)
        }
    }

    @Test
    func unknownSourceTokenIsNotAdmitted() throws {
        let record = SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.headphoneMotion",
            nativeRecording: try Self.native()
        )
        #expect(throws: SensorKitConversionError.invalidRecord(
            .sourceTypeNotAdmitted("SRSensor.headphoneMotion")
        )) {
            try SensorKitConverter().convert(.raw(record), context: Self.context)
        }
    }
}
