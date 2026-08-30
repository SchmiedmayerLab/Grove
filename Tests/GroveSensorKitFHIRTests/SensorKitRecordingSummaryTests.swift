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
                subject: SensorFHIRIdentityTestSupport.subject,
                subjectIdentity: try SensorFHIRIdentityTestSupport.subjectIdentity,
                converter: SensorApplication(
                    sourceDeviceToken: "org.grovealliance.sensor-conformance",
                    name: "Sensor Conformance",
                    version: "0.5.0"
                ),
                converterHost: SensorFHIRIdentityTestSupport.converterHost,
                eventIdentifier: try SensorFHIRIdentityTestSupport.event(),
                entryNodeIdentifierSystem: SensorFHIRIdentityTestSupport.entryNodeIdentifierSystem,
                identityScope: try SensorFHIRIdentityTestSupport.identityScope,
                repositoryScope: try SensorFHIRIdentityTestSupport.repositoryScope,
                visitLocationIdentifierSystem: SensorFHIRIdentityTestSupport.visitLocationIdentifierSystem,
                sourceTimeZone: try #require(TimeZone(identifier: "America/Los_Angeles")),
                recordedAt: start.addingTimeInterval(60)
            )
        }
    }

    private static func accelerometerRecord(format: RegisteredRecordingFormat = .triaxialAccelerationSamples) throws -> SensorKitAccelerometerRecord {
        let payload = switch format {
        case .nativeRecording:
            Data("{}".utf8)
        default:
            Data("timestamp,identifier,x,y,z,device\n1787009400,1,0.1,0.2,0.3,Watch\n".utf8)
        }
        return try SensorKitAccelerometerRecord(
            sourceRecordID: try Self.sourceID,
            nativeRecording: try SensorKitNativeRecording(
                title: "Exact SensorKit accelerometer batch",
                format: format,
                payload: .inline(payload),
                admission: .verifiedSanitizedInput
            )
        )
    }

    private static func profile(_ id: String) -> FHIRPrimitive<Canonical> {
        FHIRPrimitive(Canonical(stringLiteral: "\(SensorKitContract.canonicalRoot)/StructureDefinition/\(id)"))
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
    func sleepSessionAssertsItsIntervalAndLength() throws {
        let record = SensorKitSleepSessionRecord(
            sourceRecordID: try Self.sourceID,
            session: DateInterval(start: Self.start.addingTimeInterval(-28_800), end: Self.start)
        )
        let conversion = try SensorKitConverter().convert(.sleepSession(record), context: Self.context)
        let observation = try #require(conversion.observations.first)

        #expect(observation.meta?.profile == [Self.profile("sensorkit-sleep-session-observation")])
        guard case .quantity(let value) = observation.value else {
            Issue.record("A sleep session must carry the exact length of its interval")
            return
        }
        #expect(value.value?.value?.decimal == 28_800)
        #expect(value.code?.value?.string == "s")
        #expect(value.system?.value?.url.absoluteString == "http://unitsofmeasure.org")
        #expect(observation.component == nil)
        #expect(observation.derivedFrom == nil)
        #expect(conversion.recordingDocument == nil)
        #expect(conversion.outputIdentifiers == (try SensorFHIRIdentityTestSupport.sensorKitOutputs(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.sleepSessions",
            structuredDiscriminator: "sleep-session",
            includesNativeRecording: false
        )))
        #expect(conversion.bundle.entry?.count == 4)
        guard case .period(let effective) = observation.effective else {
            Issue.record("A sleep session must span its exact session Period")
            return
        }
        #expect(effective.start?.value?.description == "2026-08-17T08:30:00-07:00")
        #expect(effective.end?.value?.description == "2026-08-17T16:30:00-07:00")
    }

    @Test
    func accelerometerSummaryLinksTheMandatoryRecording() throws {
        let conversion = try SensorKitConverter().convert(
            .accelerometer(Self.accelerometerRecord()),
            context: Self.context
        )
        let observation = try #require(conversion.observations.first)
        let document = try #require(conversion.recordingDocument)
        let entries = try #require(conversion.bundle.entry)

        #expect(observation.meta?.profile == [Self.profile("sensorkit-accelerometer-observation")])
        #expect(observation.value == nil)
        #expect(Self.componentCounts(observation) == ["sample-count": 1, "batch-count": 1])
        #expect(observation.derivedFrom?.first?.reference?.value?.string == entries[1].fullUrl?.value?.url.absoluteString)
        let format = try #require(document.content.first?.format)
        #expect(format.system?.value?.url.absoluteString == SensorKitContract.recordingFormatCodeSystem)
        #expect(format.code?.value?.string == "triaxial-acceleration-samples")
        #expect(conversion.outputIdentifiers == (try SensorFHIRIdentityTestSupport.sensorKitOutputs(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.accelerometer",
            structuredDiscriminator: "accelerometer-recording-summary",
            includesNativeRecording: true
        )))
        #expect(conversion.provenance.target.count == 2)
    }

    @Test
    func ppgSummaryLinksTheMandatoryRecording() throws {
        let payload = try SensorKitPPGTestSupport.recording(start: Self.start).encoded()
        let record = try SensorKitPPGRecord(
            sourceRecordID: try Self.sourceID,
            nativeRecording: try SensorKitNativeRecording(
                title: "Exact SensorKit PPG batch",
                format: .photoplethysmogramSamples,
                payload: .inline(payload),
                admission: .callerAuthorizedOpaquePayload
            )
        )
        let conversion = try SensorKitConverter().convert(.ppg(record), context: Self.context)
        let observation = try #require(conversion.observations.first)
        let document = try #require(conversion.recordingDocument)
        let entries = try #require(conversion.bundle.entry)

        #expect(observation.meta?.profile == [Self.profile("sensorkit-ppg-observation")])
        #expect(observation.value == nil)
        #expect(Self.componentCounts(observation) == [
            "record-count": 2,
            "optical-sample-count": 2,
            "accelerometer-sample-count": 2
        ])
        #expect(observation.derivedFrom?.first?.reference?.value?.string == entries[1].fullUrl?.value?.url.absoluteString)
        #expect(document.content.first?.format?.code?.value?.string == "photoplethysmogram-samples")
        #expect(document.identifier?.first == observation.identifier?.first)
        let identifiers = try #require(document.identifier).map(BusinessIdentifier.init)
        #expect(identifiers.map(\.role) == [.sourceRecord, .sourceOutput, .sourceArtifact])
        #expect(document.content.count == 1)
        #expect(conversion.outputIdentifiers == (try SensorFHIRIdentityTestSupport.sensorKitOutputs(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.photoplethysmogram",
            structuredDiscriminator: "ppg-recording-summary",
            includesNativeRecording: true
        )))
        #expect(conversion.provenance.target.count == 2)
    }

    @Test
    func summaryRecordingRejectsAnUnregisteredFormat() throws {
        #expect(throws: SensorKitRecordError.invalidRecordingFormat) {
            _ = try Self.accelerometerRecord(format: .nativeRecording)
        }
    }
}
