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
    private static var sourceID: GroveSensorKitSourceRecordID {
        get throws {
            GroveSensorKitSourceRecordID(try #require(
                UUID(uuidString: "879d9ea2-21cb-4527-b59b-2831dc4c84ab")
            ))
        }
    }

    private static var context: GroveSensorKitFHIRConversionContext {
        get throws {
            GroveSensorKitFHIRConversionContext(
                subject: Reference(reference: "Patient/example"),
                converter: GroveSensorFHIRApplication(
                    identifier: try GroveFHIRBusinessIdentifier(
                        system: "https://study.example.org/fhir/identifiers/application",
                        value: "sensor-conformance|0.2.0"
                    ),
                    name: "Sensor Conformance",
                    version: "0.2.0"
                ),
                graphIdentifierSystem: "https://study.example.org/fhir/identifiers/sensor-graph",
                recordingDevice: GroveSensorFHIRRecordingDevice(
                    identifier: try GroveFHIRBusinessIdentifier(
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
        admission: GroveSensorRawPayloadAdmission = .verifiedSanitizedInput
    ) throws -> GroveSensorKitNativeRecording {
        try GroveSensorKitNativeRecording(
            title: "Exact SensorKit native record",
            contentType: "application/json",
            payload: .inline(Data(#"{"flags":[0,2,1,0]}"#.utf8)),
            admission: admission
        )
    }

    @Test(arguments: [
        ("sampled-data", "746739c0-630c-581d-8808-f12114c2adf9"),
        ("native-recording", "70246b31-e681-5149-8002-d515b8611713"),
        ("on-wrist", "b1b6d7c7-b185-50ea-8426-241fd27f02dc"),
        ("device-usage-summary", "db96cf40-07cd-57c5-9b00-db0be8090ffc"),
        ("ecg-waveform", "5d856ae1-3d82-5056-b21a-5700476b122a"),
        ("visit-summary", "f632b780-1a6f-541d-8c73-ff1e76ce4204")
    ])
    func outputIdentityMatchesCatalogVector(testCase: (String, String)) throws {
        let identifier = try GroveSensorKitOutputIdentity.businessIdentifier(
            source: Self.sourceID,
            discriminator: testCase.0
        )
        #expect(identifier.system == GroveSensorKitContract.outputIdentifierSystem)
        #expect(identifier.value == testCase.1)
    }

    @Test
    func rotationRateBuildsExactStructuredGraph() throws {
        let record = GroveSensorKitRotationRateRecord(
            sourceRecordID: try Self.sourceID,
            samples: [
                .init(timestamp: Self.start, x: 0.01, y: -0.02, z: 0.03),
                .init(timestamp: Self.start.addingTimeInterval(0.01), x: 0.02, y: -0.01, z: 0.04),
                .init(timestamp: Self.start.addingTimeInterval(0.02), x: 0.01, y: -0.01, z: 0.02)
            ]
        )
        let conversion = try GroveSensorKitFHIRConverter().convert(.rotationRate(record), context: Self.context)
        let observation = try #require(conversion.observations.first)
        let entries = try #require(conversion.bundle.entry)

        #expect(observation.id == nil)
        #expect(observation.meta?.profile == [
            GroveFHIRProfile.groveSensorSampledDataObservation,
            FHIRPrimitive(Canonical(stringLiteral: GroveSensorKitContract.observationProfile))
        ])
        #expect(observation.identifier?.map { $0.system?.value?.url.absoluteString } == [
            GroveSensorKitContract.sourceRecordIdentifierSystem,
            GroveSensorKitContract.outputIdentifierSystem
        ])
        #expect(conversion.recordingDocument == nil)
        #expect(conversion.provenance.target.count == 1)
        #expect(entries.count == 4)
        #expect(entries.allSatisfy { $0.fullUrl?.value?.url.absoluteString.hasPrefix("urn:uuid:") == true })
        try GroveFHIRExchangeIdentity.validate(entries: entries)

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
        let record = GroveSensorKitECGRecord(
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
        let conversion = try GroveSensorKitFHIRConverter().convert(.electrocardiogram(record), context: Self.context)
        let observation = try #require(conversion.observations.first)
        let document = try #require(conversion.recordingDocument)
        let entries = try #require(conversion.bundle.entry)

        #expect(observation.meta?.profile == [
            GroveFHIRProfile.groveSensorEcgObservation,
            FHIRPrimitive(Canonical(stringLiteral: GroveSensorKitContract.ecgObservationProfile))
        ])
        #expect(document.meta?.profile == [
            FHIRPrimitive(Canonical(stringLiteral: GroveSensorKitContract.sensorRecordingDocumentProfile)),
            FHIRPrimitive(Canonical(stringLiteral: GroveSensorKitContract.recordingDocumentProfile))
        ])
        #expect(observation.derivedFrom?.first?.reference?.value?.string == entries[1].fullUrl?.value?.url.absoluteString)
        #expect(conversion.provenance.target.count == 2)
        #expect(conversion.provenance.meta?.profile == [FHIRPrimitive(Canonical(
            stringLiteral: GroveSensorKitContract.conversionProvenanceProfile
        ))])
        #expect(entries.count == 5)
        #expect(conversion.outputIdentifiers.map(\.value) == [
            "5d856ae1-3d82-5056-b21a-5700476b122a",
            "70246b31-e681-5149-8002-d515b8611713"
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
        let record = GroveSensorKitECGRecord(
            sourceRecordID: try Self.sourceID,
            startDate: Self.start,
            durationSeconds: 0.002,
            frequencyHertz: 500,
            lead: .rightArmMinusLeftArm,
            guidance: .unguided,
            batches: [.init(offsetSeconds: 0, millivolts: [0.1, 0.2])],
            nativeRecording: try Self.native()
        )
        let conversion = try GroveSensorKitFHIRConverter().convert(.electrocardiogram(record), context: Self.context)
        let codings = try #require(conversion.observations.first?.component?.first?.code.coding)

        #expect(codings.contains { $0.system?.value?.url.absoluteString == GroveSensorKitContract.ecgLeadCodeSystem })
        #expect(!codings.contains {
            $0.system?.value?.url.absoluteString == "urn:iso:std:iso:11073:10101"
                && $0.code?.value?.string == "131329"
        })
    }

    @Test
    func nonuniformECGFailsClosed() throws {
        let record = GroveSensorKitECGRecord(
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
        #expect(throws: GroveSensorKitFHIRConversionError.invalidRecord(.nonUniformTiming(index: 2))) {
            try GroveSensorKitFHIRConverter().convert(.electrocardiogram(record), context: Self.context)
        }
    }

    @Test(arguments: GroveSensorRawPayloadAdmission.allCases)
    func rawAdmissionIsConsumedButNeverSerialized(_ admission: GroveSensorRawPayloadAdmission) throws {
        let record = GroveSensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.photoplethysmogram",
            nativeRecording: try Self.native(admission: admission)
        )
        let conversion = try GroveSensorKitFHIRConverter().convert(.raw(record), context: Self.context)
        let json = try #require(String(data: JSONEncoder().encode(conversion.bundle), encoding: .utf8))

        for value in GroveSensorRawPayloadAdmission.allCases {
            #expect(!json.contains(value.rawValue))
        }
        #expect(conversion.observations.isEmpty)
        #expect(conversion.recordingDocument != nil)
        #expect(conversion.provenance.target.count == 1)
    }

    @Test
    func deferredPlatformAdditionCannotClaimRawSupport() throws {
        let record = GroveSensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.sleepSessions",
            nativeRecording: try Self.native()
        )
        #expect(throws: GroveSensorKitFHIRConversionError.invalidRecord(
            .sourceTypeHasNoRawContract("SRSensor.sleepSessions")
        )) {
            try GroveSensorKitFHIRConverter().convert(.raw(record), context: Self.context)
        }
    }

    @Test
    func unknownSourceTokenIsNotAdmitted() throws {
        let record = GroveSensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.headphoneMotion",
            nativeRecording: try Self.native()
        )
        #expect(throws: GroveSensorKitFHIRConversionError.invalidRecord(
            .sourceTypeNotAdmitted("SRSensor.headphoneMotion")
        )) {
            try GroveSensorKitFHIRConverter().convert(.raw(record), context: Self.context)
        }
    }
}
