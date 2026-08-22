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
struct GroveSensorKitUsageSummaryTests {
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

    private static func native(format: String = "native-json-1") throws -> GroveSensorKitNativeRecording {
        try GroveSensorKitNativeRecording(
            title: "Exact SensorKit native report",
            contentType: "application/json",
            format: format,
            payload: .inline(Data(#"[{"complete":true}]"#.utf8)),
            admission: .verifiedSanitizedInput
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

    private static func messagesUsage(nativeRecording: GroveSensorKitNativeRecording?) throws -> GroveSensorKitMessagesUsageRecord {
        GroveSensorKitMessagesUsageRecord(
            sourceRecordID: try Self.sourceID,
            timestamp: Self.start,
            durationSeconds: 3_600,
            totalIncomingMessages: 12,
            totalOutgoingMessages: 8,
            totalUniqueContacts: 3,
            nativeRecording: nativeRecording
        )
    }

    @Test
    func messagesUsageBuildsACountOnlySummaryLinkedToItsRecording() throws {
        let record = try Self.messagesUsage(nativeRecording: Self.native())
        let conversion = try GroveSensorKitFHIRConverter().convert(.messagesUsage(record), context: Self.context)
        let observation = try #require(conversion.observations.first)
        let document = try #require(conversion.recordingDocument)
        let entries = try #require(conversion.bundle.entry)

        #expect(observation.meta?.profile == [Self.profile("sensorkit-messages-usage-observation")])
        #expect(observation.value == nil)
        #expect(Self.componentCounts(observation) == [
            "incoming-messages": 12,
            "outgoing-messages": 8,
            "unique-contacts": 3
        ])
        #expect(observation.derivedFrom?.first?.reference?.value?.string == entries[1].fullUrl?.value?.url.absoluteString)
        #expect(document.content.first?.format?.code?.value?.string == "native-json-1")
        #expect(conversion.outputIdentifiers.map(\.value) == [
            "4e40f7f3-3328-55ac-a4e9-c001db429ae8",
            "70246b31-e681-5149-8002-d515b8611713"
        ])
        #expect(conversion.provenance.target.count == 2)
        guard case .period(let effective) = observation.effective else {
            Issue.record("Messages usage must span the exact report interval")
            return
        }
        #expect(effective.start?.value?.description == "2026-08-17T16:30:00-07:00")
        #expect(effective.end?.value?.description == "2026-08-17T17:30:00-07:00")
    }

    @Test
    func messagesUsageWithoutARecordingOmitsTheDocumentAndLink() throws {
        let record = try Self.messagesUsage(nativeRecording: nil)
        let conversion = try GroveSensorKitFHIRConverter().convert(.messagesUsage(record), context: Self.context)
        let observation = try #require(conversion.observations.first)

        #expect(conversion.recordingDocument == nil)
        #expect(observation.derivedFrom == nil)
        #expect(conversion.outputIdentifiers.map(\.value) == ["4e40f7f3-3328-55ac-a4e9-c001db429ae8"])
        #expect(conversion.provenance.target.count == 1)
        #expect(conversion.bundle.entry?.count == 3)
    }

    @Test
    func phoneUsageEmitsTheTotalCallDurationAsItsValue() throws {
        let record = GroveSensorKitPhoneUsageRecord(
            sourceRecordID: try Self.sourceID,
            timestamp: Self.start,
            durationSeconds: 3_600,
            totalIncomingCalls: 2,
            totalOutgoingCalls: 5,
            totalPhoneCallDurationSeconds: 42.5,
            totalUniqueContacts: 4,
            nativeRecording: try Self.native()
        )
        let conversion = try GroveSensorKitFHIRConverter().convert(.phoneUsage(record), context: Self.context)
        let observation = try #require(conversion.observations.first)
        let entries = try #require(conversion.bundle.entry)

        #expect(observation.meta?.profile == [Self.profile("sensorkit-phone-usage-observation")])
        #expect(Self.componentCounts(observation) == [
            "incoming-calls": 2,
            "outgoing-calls": 5,
            "unique-contacts": 4
        ])
        #expect(observation.derivedFrom?.first?.reference?.value?.string == entries[1].fullUrl?.value?.url.absoluteString)
        #expect(conversion.outputIdentifiers.first?.value == "8c3100f5-2dff-5cbd-a0e9-22c1e813fe0f")
        guard case .quantity(let value) = observation.value else {
            Issue.record("Phone usage must emit the total call duration as a Quantity")
            return
        }
        #expect(value.value?.value?.decimal == 42.5)
        #expect(value.code?.value?.string == "s")
    }

    @Test
    func keyboardMetricsSummaryAlwaysLinksItsMandatoryRecording() throws {
        let record = GroveSensorKitKeyboardMetricsRecord(
            sourceRecordID: try Self.sourceID,
            timestamp: Self.start,
            durationSeconds: 3_600,
            totalTypingDurationSeconds: 125.5,
            totalWords: 240,
            totalAlteredWords: 12,
            totalTaps: 1_050,
            totalDeletes: 33,
            totalEmojis: 7,
            totalAutocorrections: 19,
            totalPauses: 41,
            totalTypingEpisodes: 6,
            typingSpeed: 3.5,
            nativeRecording: try Self.native()
        )
        let conversion = try GroveSensorKitFHIRConverter().convert(.keyboardMetrics(record), context: Self.context)
        let observation = try #require(conversion.observations.first)
        let entries = try #require(conversion.bundle.entry)

        #expect(observation.meta?.profile == [Self.profile("sensorkit-keyboard-metrics-observation")])
        #expect(Self.componentCounts(observation) == [
            "total-words": 240,
            "total-altered-words": 12,
            "total-taps": 1_050,
            "total-deletes": 33,
            "total-emojis": 7,
            "total-autocorrections": 19,
            "total-pauses": 41,
            "total-typing-episodes": 6,
            "typing-speed": 3.5
        ])
        #expect(observation.derivedFrom?.first?.reference?.value?.string == entries[1].fullUrl?.value?.url.absoluteString)
        #expect(conversion.outputIdentifiers.first?.value == "7624eaa1-44a0-5374-b40f-9bd7078df3fa")
        let typingSpeed = observation.component?.first { $0.code.coding?.first?.code?.value?.string == "typing-speed" }
        guard case .quantity(let speed) = typingSpeed?.value,
              case .quantity(let value) = observation.value else {
            Issue.record("Keyboard metrics must emit Quantity typing values")
            return
        }
        #expect(speed.code?.value?.string == "/s")
        #expect(value.value?.value?.decimal == 125.5)
        #expect(value.code?.value?.string == "s")
    }

    @Test
    func invalidUsageSummariesFailClosed() throws {
        let converter = GroveSensorKitFHIRConverter()
        let zeroDuration = GroveSensorKitMessagesUsageRecord(
            sourceRecordID: try Self.sourceID,
            timestamp: Self.start,
            durationSeconds: 0,
            totalIncomingMessages: 1,
            totalOutgoingMessages: 1,
            totalUniqueContacts: 1
        )
        let negativeCount = GroveSensorKitMessagesUsageRecord(
            sourceRecordID: try Self.sourceID,
            timestamp: Self.start,
            durationSeconds: 3_600,
            totalIncomingMessages: -1,
            totalOutgoingMessages: 1,
            totalUniqueContacts: 1
        )

        #expect(throws: GroveSensorKitFHIRConversionError.invalidRecord(.invalidReportDuration(field: "duration"))) {
            try converter.convert(.messagesUsage(zeroDuration), context: Self.context)
        }
        #expect(throws: GroveSensorKitFHIRConversionError.invalidRecord(
            .invalidReportCount(field: "incoming-messages", value: -1)
        )) {
            try converter.convert(.messagesUsage(negativeCount), context: Self.context)
        }
    }
}
