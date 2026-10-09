//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CoreLocation
import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// The three HealthKit sources the guide admits as recordings rather than results.
///
/// `HKHeartbeatSeriesSample` and `HKWorkoutRoute` have no public synthetic initializer, so the stored-sample
/// fixtures build the series and the route each record carries beside the beats or fixes the caller supplies.
@Suite
struct HealthKitRecordingDocumentTests {
    private static let seriesStart = Date(timeIntervalSince1970: 1_755_624_000)
    private static let heartbeats = [
        HealthKitFHIRExporter.Record.Heartbeat(timeSinceSeriesStart: 0, precededByGap: false),
        HealthKitFHIRExporter.Record.Heartbeat(timeSinceSeriesStart: 0.84, precededByGap: false),
        HealthKitFHIRExporter.Record.Heartbeat(timeSinceSeriesStart: 1.71, precededByGap: true)
    ]

    private static let locations = [
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.4275, longitude: -122.1697),
            altitude: 30.5,
            horizontalAccuracy: 5,
            verticalAccuracy: 3,
            course: 91.5,
            courseAccuracy: 10,
            speed: 2.25,
            speedAccuracy: 0.5,
            timestamp: seriesStart
        ),
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.4276, longitude: -122.1698),
            altitude: 0,
            horizontalAccuracy: 65,
            verticalAccuracy: -1,
            course: -1,
            courseAccuracy: -1,
            speed: -1,
            speedAccuracy: -1,
            timestamp: seriesStart.addingTimeInterval(1)
        )
    ]

    private static let clinicalDocumentXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ClinicalDocument xmlns="urn:hl7-org:v3">
          <typeId root="2.16.840.1.113883.1.3" extension="POCD_HD000040"/>
          <id root="2.16.840.1.113883.19.5" extension="grove-example-1"/>
          <code code="34133-9" codeSystem="2.16.840.1.113883.6.1" displayName="Summarization of Episode Note"/>
          <title>Grove Example Summary</title>
          <effectiveTime value="20260819100500"/>
          <confidentialityCode code="N" codeSystem="2.16.840.1.113883.5.25"/>
          <languageCode code="en-US"/>
          <recordTarget><patientRole><id root="2.16.840.1.113883.19.5" extension="p-1"/>\
        <patient><name><given>Example</given><family>Participant</family></name></patient></patientRole></recordTarget>
          <author><time value="20260819100500"/><assignedAuthor><id root="2.16.840.1.113883.19.5" extension="a-1"/>\
        <assignedPerson><name><given>Ada</given><family>Clinician</family></name></assignedPerson></assignedAuthor></author>
          <custodian><assignedCustodian><representedCustodianOrganization>\
        <id root="2.16.840.1.113883.19.5" extension="c-1"/><name>Example Hospital</name>\
        </representedCustodianOrganization></assignedCustodian></custodian>
          <component><structuredBody><component><section><title>Notes</title><text>Example.</text></section>\
        </component></structuredBody></component>
        </ClinicalDocument>
        """

    /// The facts of a stored series or route sample: when it starts and how long it lasts.
    private static func facts(duration: TimeInterval) -> StoredSampleFixtures.SampleFacts {
        StoredSampleFixtures.SampleFacts(
            uuid: GoldenFixtures.uuid(0xF1),
            start: seriesStart,
            end: seriesStart.addingTimeInterval(duration),
            device: nil,
            metadata: nil,
            writer: .unattributed
        )
    }

    /// The heartbeat series of the guide's example, with its beats.
    private static func heartbeatSeries() throws -> HealthKitFHIRExporter.Record {
        let series = try StoredSampleFixtures.seriesSample(HKHeartbeatSeriesSample.self, sampleType: HKSeriesType.heartbeat(), facts: facts(duration: 2))
        return .heartbeatSeries(series, beats: heartbeats)
    }

    /// A workout route with `locations`.
    private static func workoutRoute(_ locations: [CLLocation]) throws -> HealthKitFHIRExporter.Record {
        let route = try StoredSampleFixtures.seriesSample(HKWorkoutRoute.self, sampleType: HKSeriesType.workoutRoute(), facts: facts(duration: 1))
        return .workoutRoute(route, locations: locations)
    }

    /// The payload the heartbeat-series plan writes for `heartbeats` from the guide's series start.
    private static func beatIntervals(_ heartbeats: [HealthKitFHIRExporter.Record.Heartbeat]) throws -> Data {
        try HealthKitContentPlan[.heartbeatSeries].recordingDocument().beatIntervals(seriesStart: seriesStart, heartbeats: heartbeats)
    }

    private func inputs(
        route: HealthKitFHIRExporter.Disclosure = .omit,
        studies: [StudyEnrollment] = []
    ) -> ExportInputs {
        var inputs = ExportInputs()
        inputs.converter = ApplicationDevice.test(
            name: "Example Study",
            bundleIdentifier: "org.grovealliance.example-study",
            version: "2.0.0 (42)"
        )
        inputs.graphIdentifierSystem = "https://study.example.org/fhir/identifiers/mobile-graph"
        inputs.instant = Date(timeIntervalSince1970: 1_755_624_060)
        inputs.options.route = route
        inputs.studies = studies
        return inputs
    }

    @Test("A beat series is written in the registry's published bytes")
    func beatIntervalPayloadMatchesThePublishedExample() throws {
        let payload = try Self.beatIntervals(Self.heartbeats)

        #expect(String(decoding: payload, as: UTF8.self) == """
            timestamp,precededByGap
            1755624000,0
            1755624000.84,0
            1755624001.71,1

            """)
        // The exact base64 the guide publishes for its heartbeat-series example.
        #expect(payload.base64EncodedString() == """
            dGltZXN0YW1wLHByZWNlZGVkQnlHYXAKMTc1NTYyNDAwMCwwCjE3NTU2MjQwMDAuODQsMAoxNzU1NjI0MDAxLjcxLDEK
            """)
    }

    @Test("A series with no beats fails closed rather than carrying a header alone")
    func emptyBeatSeriesFailsClosed() {
        #expect(throws: HealthKitConversionError.ValueFailure.emptyRecordingSeries) {
            try Self.beatIntervals([])
        }
    }

    @Test("A beat series is carried as a recording document, not reduced to a value")
    func beatSeriesGraphCarriesThePublishedContract() async throws {
        let payload = try Self.beatIntervals(Self.heartbeats)
        let conversion = try await ExporterFixtures.export(try Self.heartbeatSeries(), inputs())
        let document = conversion.document

        #expect(document.meta?.profile == [
            Profile.groveSensorRecordingDocument,
            Profile.healthkitRecordingDocument
        ])
        #expect(document.status.value == .current)
        #expect(document.subject == .testPatient)
        let identifiers = try #require(document.identifier).map(RoledIdentifier.init)
        #expect(identifiers.map(\.role) == [.sourceRecord, .sourceOutput, .sourceArtifact])
        #expect(document.identifier?[1].value?.value?.string == conversion.identifiers.sourceOutput.value)
        #expect(document.content.count == 1)

        let content = try #require(document.content.first)
        #expect(content.format?.code?.value?.string == "beat-interval-series")
        #expect(content.format?.system?.value?.url.absoluteString
            == "https://grovealliance.org/fhir/sensor/CodeSystem/grove-recording-format")
        #expect(content.format?.version == nil)
        #expect(content.attachment.contentType?.value?.string == "text/csv")
        #expect(content.attachment.title?.value?.string == "Heartbeat series beat intervals")
        #expect(content.attachment.size?.value?.integer == 69)
        #expect(content.attachment.data?.value?.dataString == payload.base64EncodedString())
        #expect(content.attachment.hash?.value?.dataString == "eQkKWi5ACtHFVRcy+yqDrwwrQs0=")
    }

    @Test("The document states its HealthKit source type and its conversion event")
    func documentGraphStatesItsSourceAndProvenance() async throws {
        let conversion = try await ExporterFixtures.export(try Self.heartbeatSeries(), inputs())

        let coding = try #require(conversion.document.type?.coding?.first)
        #expect(coding.system?.value?.url.absoluteString
            == "https://grovealliance.org/fhir/sensor/CodeSystem/grove-recording-format")
        #expect(coding.code?.value?.string == "beat-interval-series")
        let sourceTypes = conversion.document.extension?.filter {
            $0.url == Canonicals.healthKitSourceTypeExtension
        }
        #expect(sourceTypes?.count == 1)
        guard case .code(let sourceType) = sourceTypes?.first?.value else {
            Issue.record("HealthKit source type must use the lineage valueCode extension")
            return
        }
        #expect(sourceType.value?.string == HKDataTypeIdentifierHeartbeatSeries)

        #expect(conversion.provenance.meta?.profile == [
            HealthKitContract.conversionProvenanceProfile
        ])
        let documentURL = try conversion.identifiers.sourceOutput.fullURLString
        #expect(conversion.provenance.target.first?.reference?.value?.string == documentURL)
        #expect(conversion.bundle.entry?.first?.fullUrl?.value?.url.absoluteString == documentURL)
        #expect(conversion.document.author?.last?.reference?.value?.string
            == (try conversion.identifiers.converterApplicationSnapshot.fullURLString))
    }

    @Test("A route is omitted under the default disclosure policy")
    func routeIsOmittedByDefault() async throws {
        await #expect(try ExporterFixtures.exports(try Self.workoutRoute(Self.locations), inputs()).isEmpty)
    }

    @Test("An authorized route is written in the registry's column schema")
    func authorizedRouteIsCarried() async throws {
        let conversion = try await ExporterFixtures.export(try Self.workoutRoute(Self.locations), inputs(route: .authorized))
        let payload = try #require(conversion.document.content.first?.attachment.data?.value?.data())

        // The second fix reports no altitude, speed, or course, and each unavailable reading is an
        // empty field rather than CoreLocation's negative sentinel.
        #expect(String(decoding: payload, as: UTF8.self) == """
            timestamp,latitude,longitude,altitude,horizontalAccuracy,verticalAccuracy,speed,speedAccuracy,course,courseAccuracy
            1755624000,37.4275,-122.1697,30.5,5,3,2.25,0.5,91.5,10
            1755624001,37.4276,-122.1698,0,65,,,,,

            """)
    }

    @Test("An authorized route with no fixes fails closed")
    func emptyAuthorizedRouteFailsClosed() async {
        await #expect(throws: HealthKitConversionError.invalidValue(.workoutRoute, .emptyRecordingSeries)) {
            try await ExporterFixtures.export(try Self.workoutRoute([]), inputs(route: .authorized))
        }
    }

    /// CoreLocation marks a fix whose coordinate is invalid with a negative horizontal accuracy, wherever the fix falls
    /// and whatever its altitude reports. The registry's row states a position and its radius of uncertainty, which
    /// cannot be empty, for every fix, so the route cannot be carried; no registered input rule names that reason, so
    /// it is reported unclassified. An omitted route is never read.
    @Test("An authorized route with an invalid coordinate fails closed")
    func invalidCoordinateFailsClosed() async throws {
        let invalid = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.4275, longitude: -122.1697),
            altitude: 30.5,
            horizontalAccuracy: -1,
            verticalAccuracy: 3,
            timestamp: Self.seriesStart
        )
        let record = try Self.workoutRoute([invalid, Self.locations[1]])
        let refusal = try await #require(throws: HealthKitConversionError.self) {
            try await ExporterFixtures.export(record, inputs(route: .authorized))
        }
        #expect(refusal == HealthKitConversionError(conversionFailure: WorkoutRouteFailure.invalidCoordinate, source: .workoutRoute))
        #expect(refusal.diagnostic == ExchangeGraphRule.mobileInputUnclassified.diagnostic(at: "Bundle"))
        await #expect(try ExporterFixtures.exports(record, inputs()).isEmpty)
    }

    #if !os(watchOS)
    @Test("A CDA document is carried byte for byte under its own media type")
    func clinicalDocumentIsBytePreserved() async throws {
        let bytes = Data(Self.clinicalDocumentXML.utf8)
        let sample = try HKCDADocumentSample(
            data: bytes,
            start: Self.seriesStart,
            end: Self.seriesStart.addingTimeInterval(1),
            metadata: nil
        )

        let conversion = try await ExporterFixtures.export(sample, inputs())
        let content = try #require(conversion.document.content.first)

        #expect(content.format?.code?.value?.string == "clinical-document")
        #expect(content.attachment.contentType?.value?.string == "application/hl7-cda+xml")
        #expect(content.attachment.title?.value?.string == "Grove Example Summary")
        #expect(content.attachment.size?.value?.integer == Int32(bytes.count))
        #expect(content.attachment.data?.value?.dataString == bytes.base64EncodedString())
        #expect(conversion.document.type?.coding?.first?.code?.value?.string == "clinical-document")
        #expect(conversion.document.extension?.contains {
            guard $0.url == Canonicals.healthKitSourceTypeExtension,
                  case .code(let value) = $0.value else {
                return false
            }
            return value.value?.string == sample.sampleType.identifier
        } == true)
    }

    #endif
}


extension HealthKitRecordingDocumentTests {
    @Test("Study relevance preserves recording bytes and identities", arguments: [0, 1, 2])
    func studyRelevancePreservesRecording(studyCount: Int) async throws {
        let record = try Self.heartbeatSeries()
        let studies = (0..<studyCount).map { StudyEnrollment.test("study-\($0)") }
        let baseline = try await ExporterFixtures.export(record, inputs())
        let conversion = try await ExporterFixtures.export(record, inputs(studies: studies))
        #expect(conversion.document.context?.related?.count ?? 0 == studyCount)
        #expect(conversion.document.extension?.contains { $0.url == Canonicals.instantiatesCanonical } != true)
        #expect(conversion.identifiers == baseline.identifiers)
        #expect(conversion.document.content == baseline.document.content)
        #expect(conversion.provenance == baseline.provenance)
        #expect(conversion.bundle.identifier == baseline.bundle.identifier)
        _ = try ExchangeGraph(validating: JSONEncoder().encode(conversion.bundle), kind: .active)
    }
}

#endif
