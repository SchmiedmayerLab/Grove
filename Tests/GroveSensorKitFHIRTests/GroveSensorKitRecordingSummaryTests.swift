//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
@testable import GroveSensorKitFHIR
import ModelsR4
import Testing


@Suite
struct GroveSensorKitRecordingSummaryTests {
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
                        value: "sensor-conformance|0.3.0"
                    ),
                    name: "Sensor Conformance",
                    version: "0.3.0"
                ),
                graphIdentifierSystem: "https://study.example.org/fhir/identifiers/sensor-graph",
                sourceTimeZone: try #require(TimeZone(identifier: "America/Los_Angeles")),
                issuedAt: start.addingTimeInterval(30),
                recordedAt: start.addingTimeInterval(60)
            )
        }
    }

    private static func accelerometerRecord(format: String = "grove-csv-1") throws -> GroveSensorKitAccelerometerRecord {
        GroveSensorKitAccelerometerRecord(
            sourceRecordID: try Self.sourceID,
            coverage: DateInterval(start: Self.start, duration: 60),
            sampleCount: 18_000,
            batchCount: 3,
            nativeRecording: try GroveSensorKitNativeRecording(
                title: "Exact SensorKit accelerometer batch",
                contentType: "text/csv",
                format: format,
                payload: .inline(Data("timestamp,identifier,x,y,z,device\n1787009400,1,0.1,0.2,0.3,Watch\n".utf8)),
                admission: .verifiedSanitizedInput
            )
        )
    }

    private static func profile(_ id: String) -> FHIRPrimitive<Canonical> {
        FHIRPrimitive(Canonical(stringLiteral: "\(GroveSensorKitContract.canonicalRoot)/StructureDefinition/\(id)"))
    }

    private static func componentCounts(_ observation: Observation) -> [String: Decimal] {
        Dictionary(uniqueKeysWithValues: (observation.component ?? []).compactMap { component -> (String, Decimal)? in
            guard let code = component.code.coding?.first?.code?.value?.string,
                  case .quantity(let quantity) = component.value,
                  let value = quantity.value?.value?.decimal else {
                return nil
            }
            return (code, value)
        })
    }

    @Test
    func sleepSessionAssertsOnlyTheSessionInterval() throws {
        let record = GroveSensorKitSleepSessionRecord(
            sourceRecordID: try Self.sourceID,
            session: DateInterval(start: Self.start.addingTimeInterval(-28_800), end: Self.start)
        )
        let conversion = try GroveSensorKitFHIRConverter().convert(.sleepSession(record), context: Self.context)
        let observation = try #require(conversion.observations.first)

        #expect(observation.meta?.profile == [Self.profile("sensorkit-sleep-session-observation")])
        #expect(observation.value == nil)
        #expect(observation.component == nil)
        #expect(observation.derivedFrom == nil)
        #expect(conversion.recordingDocument == nil)
        #expect(conversion.outputIdentifiers.map(\.value) == ["67449c45-a0d7-5aa8-ba59-96be3c4c52e4"])
        #expect(conversion.bundle.entry?.count == 3)
        guard case .period(let effective) = observation.effective else {
            Issue.record("A sleep session must span its exact session Period")
            return
        }
        #expect(effective.start?.value?.description == "2026-08-17T08:30:00-07:00")
        #expect(effective.end?.value?.description == "2026-08-17T16:30:00-07:00")
    }

    @Test
    func accelerometerSummaryLinksTheMandatoryRecording() throws {
        let conversion = try GroveSensorKitFHIRConverter().convert(
            .accelerometer(Self.accelerometerRecord()),
            context: Self.context
        )
        let observation = try #require(conversion.observations.first)
        let document = try #require(conversion.recordingDocument)
        let entries = try #require(conversion.bundle.entry)

        #expect(observation.meta?.profile == [Self.profile("sensorkit-accelerometer-observation")])
        #expect(observation.value == nil)
        #expect(Self.componentCounts(observation) == ["sample-count": 18_000, "batch-count": 3])
        #expect(observation.derivedFrom?.first?.reference?.value?.string == entries[1].fullUrl?.value?.url.absoluteString)
        let format = try #require(document.content.first?.format)
        #expect(format.system?.value?.url.absoluteString == GroveSensorKitContract.recordingFormatCodeSystem)
        #expect(format.code?.value?.string == "grove-csv-1")
        #expect(conversion.outputIdentifiers.map(\.value) == [
            "c503c596-3df1-5430-81c0-d4bad76f1033",
            "70246b31-e681-5149-8002-d515b8611713"
        ])
        #expect(conversion.provenance.target.count == 2)
    }

    @Test
    func ppgSummaryLinksTheMandatoryRecording() throws {
        let record = GroveSensorKitPPGRecord(
            sourceRecordID: try Self.sourceID,
            coverage: DateInterval(start: Self.start, duration: 30),
            recordCount: 2,
            opticalSampleCount: 512,
            accelerometerSampleCount: 256,
            nativeRecording: try GroveSensorKitNativeRecording(
                title: "Exact SensorKit PPG batch",
                contentType: "application/octet-stream",
                format: "grove-ppg-1",
                payload: .inline(Data([0x02, 0x41, 0xDA, 0x9E, 0x9F, 0x8C, 0xE3, 0x60, 0x00])),
                admission: .callerAuthorizedOpaquePayload
            )
        )
        let conversion = try GroveSensorKitFHIRConverter().convert(.ppg(record), context: Self.context)
        let observation = try #require(conversion.observations.first)
        let document = try #require(conversion.recordingDocument)
        let entries = try #require(conversion.bundle.entry)

        #expect(observation.meta?.profile == [Self.profile("sensorkit-ppg-observation")])
        #expect(observation.value == nil)
        #expect(Self.componentCounts(observation) == [
            "record-count": 2,
            "optical-sample-count": 512,
            "accelerometer-sample-count": 256
        ])
        #expect(observation.derivedFrom?.first?.reference?.value?.string == entries[1].fullUrl?.value?.url.absoluteString)
        #expect(document.content.first?.format?.code?.value?.string == "grove-ppg-1")
        #expect(document.identifier?.first == observation.identifier?.first)
        #expect(conversion.outputIdentifiers.map(\.value) == [
            "8a67dbdf-8085-5d15-a739-6e363db3d0e6",
            "70246b31-e681-5149-8002-d515b8611713"
        ])
        #expect(conversion.provenance.target.count == 2)
    }

    @Test
    func summaryRecordingRejectsAnUnregisteredFormat() throws {
        let record = try Self.accelerometerRecord(format: "native-json-1")

        #expect(throws: GroveSensorKitFHIRConversionError.invalidRecord(
            .recordingFormatNotAdmitted("native-json-1")
        )) {
            try GroveSensorKitFHIRConverter().convert(.accelerometer(record), context: Self.context)
        }
    }
}
