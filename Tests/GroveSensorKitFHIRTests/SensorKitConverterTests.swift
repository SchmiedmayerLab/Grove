//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// One suite exercises the complete adapter graph surface against the normative catalog.
// swiftlint:disable type_body_length

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

    private static func native(
        admission: SensorRawPayloadAdmission = .verifiedSanitizedInput,
        format: RegisteredRecordingFormat = .nativeRecording
    ) throws -> SensorKitNativeRecording {
        let payload: Data
        switch format {
        case .heartRateSamples:
            payload = Data("timestamp,value,confidence,device\n1787009400,72,3,\"Watch7,1\"\n".utf8)
        default:
            payload = Data(#"{"flags":[0,2,1,0]}"#.utf8)
        }
        return try SensorKitNativeRecording(
            title: "Exact SensorKit native record",
            format: format,
            payload: .inline(payload),
            admission: admission
        )
    }

    /// Builds a 500 Hz ECG record the way `SensorKitECGRecord(session:)` does: batch offsets and the
    /// duration are `Double` intervals from the session's begin marker to each chunk's `Date`.
    private static func ecgRecord(beginMarker: Date, chunkDates: [Date]) throws -> SensorKitECGRecord {
        let batches = chunkDates.map { date in
            SensorKitECGBatch(offsetSeconds: date.timeIntervalSince(beginMarker), millivolts: [0.1, 0.2])
        }
        return SensorKitECGRecord(
            sourceRecordID: try sourceID,
            startDate: beginMarker,
            durationSeconds: (batches.last?.offsetSeconds ?? 0) + 1.0 / 500,
            frequencyHertz: 500,
            lead: .leftArmMinusRightArm,
            guidance: .guided,
            batches: batches,
            nativeRecording: try native()
        )
    }

    @Test(arguments: [
        "sampled-data",
        "native-recording",
        "on-wrist",
        "device-usage-summary",
        "ecg-waveform",
        "visit-summary",
        "messages-usage-summary",
        "phone-usage-summary",
        "keyboard-metrics-summary",
        "sleep-session",
        "accelerometer-recording-summary",
        "ppg-recording-summary"
    ])
    func outputIdentityIsDeploymentScopedAndDoesNotDiscloseItsSource(discriminator: String) throws {
        let sourceID = try Self.sourceID
        let record = try SensorFHIRIdentityTestSupport.identityScope.sourceRecord(
            adapterID: "sensorkit",
            sourceType: "SRSensor.rotationRate",
            repositoryScope: SensorFHIRIdentityTestSupport.repositoryScope,
            nativeRecordID: sourceID.value
        )
        let identifier = try record.output(role: RetractionEvent.Target.Role.primaryOutput.rawValue, discriminator: discriminator)
        #expect(identifier.systemValue ==
            "https://grovealliance.org/fhir/testing/identifiers/pseudonym/source-output/test/1")
        #expect(identifier.role == .sourceOutput)
        #expect(identifier.value.hasPrefix("v0:test:1:"))
        #expect(!identifier.value.contains(sourceID.value))
        #expect(!identifier.value.contains(discriminator))
    }

    @Test("Clock instants are UTC while effective bounds keep the source zone")
    func clockInstantsAreUTC() throws {
        let record = SensorKitRotationRateRecord(
            sourceRecordID: try Self.sourceID,
            samples: [
                .init(timestamp: Self.start, x: 0.01, y: -0.02, z: 0.03),
                .init(timestamp: Self.start.addingTimeInterval(0.01), x: 0.02, y: -0.01, z: 0.04)
            ]
        )
        let graph = try SensorKitExporterFixtures.graph(.rotationRate(record))
        #expect(graph.bundle.timestamp?.value?.description == "2026-08-17T23:31:00Z")
        #expect(try graph.provenance.recorded.value?.description == "2026-08-17T23:31:00Z")
        guard case .dateTime(let occurred)? = try graph.provenance.occurred,
              case .period(let effective)? = graph.observations.first?.effective else {
            Issue.record("The graph lost its Provenance time or its effective period")
            return
        }
        #expect(occurred.value?.description == "2026-08-17T23:31:00Z")
        #expect(effective.start?.value?.description == "2026-08-17T16:30:00-07:00")
    }

    /// Each period starts in the first occurrence of the repeated fall-back hour and ends in the second one.
    @Test("Effective bounds in the repeated DST hour keep their instants", arguments: [
        ("America/Los_Angeles", "2025-11-02T08:55:00Z", "2025-11-02T09:05:00Z", "2025-11-02T01:05:00-08:00"),
        ("Europe/Berlin", "2025-10-26T00:55:00Z", "2025-10-26T01:30:00Z", "2025-10-26T02:30:00+01:00")
    ])
    func repeatedHourBoundsKeepTheirInstants(_ zoneName: String, _ startText: String, _ endText: String, _ endLexical: String) throws {
        let zone = try #require(TimeZone(identifier: zoneName))
        let start = try #require(ISO8601DateFormatter().date(from: startText))
        let end = try #require(ISO8601DateFormatter().date(from: endText))
        let period = try SensorKitConverter.period(start: start, end: end, timeZone: zone)
        let decoded = try JSONDecoder().decode(Period.self, from: JSONEncoder().encode(period))
        #expect(try #require(decoded.start?.value).asNSDate() == start)
        #expect(try #require(decoded.end?.value).asNSDate() == end)
        #expect(decoded.end?.value?.description == endLexical)
        #expect(try SensorKitConverter.exactDateTime(end, timeZone: zone).asNSDate() == end)
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
        let graph = try SensorKitExporterFixtures.graph(.rotationRate(record))
        let observation = try #require(graph.observations.first)
        let entries = try #require(graph.bundle.entry)

        #expect(observation.id == nil)
        #expect(observation.issued == nil)
        #expect(observation.meta?.profile == [
            Profile.groveSensorSampledDataObservation,
            FHIRPrimitive(Canonical(stringLiteral: SensorKitContract.observationProfile))
        ])
        let identifierRoles = try observation.identifier?.map { try RoledIdentifier($0).role }
        #expect(identifierRoles == [
            .sourceRecord,
            .sourceOutput
        ])
        #expect(graph.recordingDocument == nil)
        #expect(try graph.provenance.target.count == 1)
        #expect(entries.count == 5)
        #expect(entries.allSatisfy { $0.fullUrl?.value?.url.absoluteString.hasPrefix("urn:uuid:") == true })

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

    @Test("Governed native record ID is opt-in and appears only on a structured primary")
    func governedNativeIDOnStructuredPrimary() throws {
        let record = SensorKitRotationRateRecord(
            sourceRecordID: try Self.sourceID,
            samples: [
                .init(timestamp: Self.start, x: 0.01, y: 0.02, z: 0.03),
                .init(timestamp: Self.start.addingTimeInterval(0.01), x: 0.02, y: 0.03, z: 0.04)
            ]
        )
        let nativeSystem: IdentifierSystem =
            "https://study.example.org/fhir/identifier/sensorkit-source-record"
        let graph = try SensorKitExporterFixtures.graph(.rotationRate(record), nativeIdentifier: .authorized(
            system: nativeSystem,
            type: GovernedSourceIdentifierDisclosurePolicy.IdentifierType(
                system: "https://study.example.org/fhir/CodeSystem/source-identifier-type",
                code: "sensorkit-record-id"
            )
        ))
        #expect(graph.observations.count == 1)
        let observation = try #require(graph.observations.first)
        let nativeValue = try Self.sourceID.value
        let native = try #require(observation.identifier?.first {
            $0.system?.value?.url.absoluteString == nativeSystem.rawValue
        })

        #expect(native.value?.value?.string == nativeValue)
        #expect(observation.id == nil)
        #expect(graph.recordingDocument == nil)
        let bundleJSON = String(decoding: try JSONEncoder().encode(graph.bundle), as: UTF8.self)
        #expect(graph.bundle.entry?.contains {
            $0.fullUrl?.value?.url.absoluteString.contains(nativeValue) == true
        } != true)
        #expect(bundleJSON.components(separatedBy: nativeValue).count == 2)
    }

    @Test("Visit location is retained exactly under the governed source-store system")
    func visitLocationUsesGovernedNativeIdentity() throws {
        let locationID = try #require(UUID(uuidString: "6f2692c2-7a8e-45db-8f2f-3300157fc0b4"))
        let record = SensorKitVisitRecord(
            sourceRecordID: try Self.sourceID,
            locationCategory: .work,
            distanceFromHomeMeters: 1_250,
            arrivalWindow: DateInterval(start: Self.start, duration: 60),
            departureWindow: DateInterval(start: Self.start.addingTimeInterval(3_600), duration: 60),
            locationID: locationID
        )

        let graph = try SensorKitExporterFixtures.graph(.visit(record))
        #expect(graph.observations.count == 1)
        let observation = try #require(graph.observations.first)
        #expect(observation.focus?.count == 1)
        let focus = try #require(observation.focus?.first)
        let identifier = try #require(focus.identifier)

        #expect(focus.reference == nil)
        #expect(focus.type?.value?.url.absoluteString == ResourceType.location.rawValue)
        #expect(identifier.system?.value?.url.absoluteString ==
            SensorFHIRIdentityTestSupport.visitLocationIdentifierSystem.rawValue)
        #expect(identifier.value?.value?.string == locationID.uuidString.lowercased())
        #expect(identifier.type == nil)
        let encoded = try JSONEncoder().encode(graph.bundle)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(json.contains(locationID.uuidString.lowercased()))
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
        let graph = try SensorKitExporterFixtures.graph(.electrocardiogram(record))
        let observation = try #require(graph.observations.first)
        let document = try #require(graph.recordingDocument)
        let entries = try #require(graph.bundle.entry)

        #expect(observation.meta?.profile == [
            Profile.groveSensorEcgObservation,
            FHIRPrimitive(Canonical(stringLiteral: SensorKitContract.ecgObservationProfile))
        ])
        #expect(document.meta?.profile == [
            Profile.groveSensorRecordingDocument,
            FHIRPrimitive(Canonical(stringLiteral: SensorKitContract.recordingDocumentProfile))
        ])
        let method = try #require(observation.method?.coding?.first)
        #expect(method.system?.value?.url.absoluteString == SensorKitContract.valueCodeSystem)
        #expect(method.code?.value?.string == "guided")
        #expect(method.display?.value?.string == "Guided")
        let format = try #require(document.content.first?.format)
        #expect(format.system?.value?.url.absoluteString == RegisteredRecordingFormat.codeSystem)
        #expect(format.code?.value?.string == "native-recording")
        #expect(observation.derivedFrom?.first?.reference?.value?.string == entries[1].fullUrl?.value?.url.absoluteString)
        #expect(try graph.provenance.target.count == 2)
        #expect(try graph.provenance.meta?.profile == [
            FHIRPrimitive(Canonical(stringLiteral: SensorKitContract.conversionProvenanceProfile))
        ])
        #expect(entries.count == 6)
        #expect(graph.outputIdentifiers == (try SensorFHIRIdentityTestSupport.sensorKitOutputs(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.electrocardiogram",
            structuredDiscriminator: "ecg-waveform",
            includesNativeRecording: true
        )))
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

    @Test("Hybrid graph discloses the governed source ID only on its structured primary")
    func governedNativeIDOnHybridPrimaryOnly() throws {
        let record = SensorKitECGRecord(
            sourceRecordID: try Self.sourceID,
            startDate: Self.start,
            durationSeconds: 0.002,
            frequencyHertz: 500,
            lead: .leftArmMinusRightArm,
            guidance: .guided,
            batches: [.init(offsetSeconds: 0, millivolts: [0.1, 0.2])],
            nativeRecording: try Self.native()
        )
        let nativeSystem: IdentifierSystem =
            "https://study.example.org/fhir/identifier/sensorkit-source-record"
        let graph = try SensorKitExporterFixtures.graph(.electrocardiogram(record), nativeIdentifier: .authorized(system: nativeSystem))

        #expect(graph.observations.count == 1)
        let observation = try #require(graph.observations.first)
        #expect(observation.identifier?.contains {
            $0.system?.value?.url.absoluteString == nativeSystem.rawValue
        } == true)
        #expect(graph.recordingDocument?.identifier?.contains {
            $0.system?.value?.url.absoluteString == nativeSystem.rawValue
        } != true)
        #expect(graph.recordingDocument?.id == nil)
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
        let graph = try SensorKitExporterFixtures.graph(.electrocardiogram(record))
        let codings = try #require(graph.observations.first?.component?.first?.code.coding)

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
            try SensorKitExporterFixtures.graph(.electrocardiogram(record))
        }
    }

    @Test("ECG timing and the waveform start at the first voltage chunk, not the earlier begin marker")
    func ecgBeginMarkerBeforeFirstChunkIsAdmitted() throws {
        let record = try Self.ecgRecord(
            beginMarker: Self.start.addingTimeInterval(-0.375),
            chunkDates: [Self.start, Self.start.addingTimeInterval(0.004)]
        )
        let graph = try SensorKitExporterFixtures.graph(.electrocardiogram(record))
        let observation = try #require(graph.observations.first)
        guard case .period(let effective) = observation.effective else {
            Issue.record("ECG must emit a Period")
            return
        }

        #expect(effective.start?.value?.description == "2026-08-17T16:30:00-07:00")
        #expect(effective.end?.value?.description == "2026-08-17T16:30:00.006-07:00")
    }

    @Test("ECG chunk dates that are not exactly representable as Double still form one uniform series")
    func ecgDoubleRepresentationNoiseIsAdmitted() throws {
        // Each chunk date rounds to `Date`'s 2^-23 s grid, so the offsets miss the exact 4 ms
        // multiples by tens of nanoseconds (0.004 arrives as 0.003999948501586914).
        let firstChunk = Date(timeIntervalSinceReferenceDate: 808_702_200.123_456_7)
        let chunkDates = (0..<5).map { firstChunk.addingTimeInterval(Double($0) * 0.004) }
        let record = try Self.ecgRecord(beginMarker: firstChunk, chunkDates: chunkDates)
        #expect(record.batches[1].offsetSeconds != 0.004)

        let graph = try SensorKitExporterFixtures.graph(.electrocardiogram(record))
        let observation = try #require(graph.observations.first)
        guard case .period(let effective) = observation.effective,
              case .sampledData(let waveform) = observation.component?.first?.value else {
            Issue.record("ECG must emit one SampledData lead over a Period")
            return
        }
        let expectedStart = try SensorKitConverter.exactDateTime(
            firstChunk,
            timeZone: try #require(TimeZone(identifier: "America/Los_Angeles"))
        )

        #expect(effective.start?.value?.description == expectedStart.description)
        #expect(waveform.data?.value?.string.split(separator: " ").count == 10)
    }

    @Test(
        "A missing sample or a sub-period shift still fails closed despite the noise tolerance",
        arguments: [0.010, 0.008_05]
    )
    func ecgRealTimingGapFailsClosed(thirdChunkOffset: TimeInterval) throws {
        let firstChunk = Date(timeIntervalSinceReferenceDate: 808_702_200.123_456_7)
        let record = try Self.ecgRecord(
            beginMarker: firstChunk.addingTimeInterval(-0.375),
            chunkDates: [0, 0.004, thirdChunkOffset].map { firstChunk.addingTimeInterval($0) }
        )

        #expect(throws: SensorKitConversionError.invalidRecord(.nonUniformTiming(index: 4))) {
            try SensorKitExporterFixtures.graph(.electrocardiogram(record))
        }
    }

    @Test(arguments: SensorRawPayloadAdmission.allCases)
    func rawAdmissionIsConsumedButNeverSerialized(_ admission: SensorRawPayloadAdmission) throws {
        let record = try SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.heartRate",
            effectivePeriod: DateInterval(start: Self.start, duration: 1),
            nativeRecording: try Self.native(admission: admission, format: .heartRateSamples)
        )
        let graph = try SensorKitExporterFixtures.graph(.raw(record))
        let json = try #require(String(data: JSONEncoder().encode(graph.bundle), encoding: .utf8))

        for value in SensorRawPayloadAdmission.allCases {
            #expect(!json.contains(value.rawValue))
        }
        #expect(graph.observations.isEmpty)
        #expect(graph.recordingDocument?.content.first?.format?.code?.value?.string == "heart-rate-samples")
        #expect(graph.recordingDocument?.content.first?.format?.version == nil)
        #expect(graph.recordingDocument?.context?.period?.start != nil)
        #expect(graph.recordingDocument?.context?.period?.end != nil)
        #expect(graph.recordingDocument?.context?.related == nil)
        #expect(try graph.provenance.target.count == 1)
    }

    @Test("A one-instant raw acquisition retains exact point coverage")
    func rawPointCoverageIsAdmitted() throws {
        let record = try SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.heartRate",
            effectivePeriod: DateInterval(start: Self.start, duration: 0),
            nativeRecording: try Self.native(format: .heartRateSamples)
        )
        let graph = try SensorKitExporterFixtures.graph(.raw(record))
        let period = try #require(graph.recordingDocument?.context?.period)

        #expect(period.start == period.end)
    }

    /// The catalog names every raw representation the logical `native-recording` output, with no fallback
    /// (sensorkit-adapter.json, `raw.outputDiscriminator`), raw-only records included.
    @Test("A raw-only record's sole output is the native-recording output")
    func rawOnlyOutputIsTheNativeRecording() throws {
        let record = try SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.heartRate",
            effectivePeriod: DateInterval(start: Self.start, duration: 1),
            nativeRecording: try Self.native(format: .heartRateSamples)
        )
        let graph = try SensorKitExporterFixtures.graph(.raw(record))
        #expect(graph.outputIdentifiers == (try SensorFHIRIdentityTestSupport.sensorKitOutputs(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.heartRate",
            structuredDiscriminator: nil,
            includesNativeRecording: true
        )))
    }

    /// SensorKit names no gateway: the exporter converts as an assembler, so no Observation states
    /// observation-gatewayDevice and no graph carries a second application snapshot.
    @Test("A SensorKit graph names no gateway")
    func sensorKitGraphNamesNoGateway() throws {
        let ecg = SensorKitECGRecord(
            sourceRecordID: try Self.sourceID,
            startDate: Self.start,
            durationSeconds: 0.006,
            frequencyHertz: 500,
            lead: .leftArmMinusRightArm,
            guidance: .guided,
            batches: [.init(offsetSeconds: 0, millivolts: [0.011, 0.023]), .init(offsetSeconds: 0.004, millivolts: [-0.005, 0.014])],
            nativeRecording: try Self.native()
        )
        let graph = try SensorKitExporterFixtures.graph(.electrocardiogram(ecg))
        let observation = try #require(graph.observations.first)
        #expect(observation.extension?.contains { $0.url == Canonicals.gatewayDevice } == false)
        let devices = graph.bundle.entry?.filter { $0.resource?.get() is Device }
        #expect(devices?.count == 3)
    }

    @Test("A raw-only source discloses its governed ID on the sole DocumentReference")
    func governedNativeIDOnRawOnlyPrimary() throws {
        let record = try SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.heartRate",
            effectivePeriod: DateInterval(start: Self.start, duration: 1),
            nativeRecording: try Self.native(format: .heartRateSamples)
        )
        let nativeSystem: IdentifierSystem =
            "https://study.example.org/fhir/identifier/sensorkit-source-record"
        let graph = try SensorKitExporterFixtures.graph(.raw(record), nativeIdentifier: .authorized(system: nativeSystem))
        let nativeValue = try Self.sourceID.value

        #expect(graph.observations.isEmpty)
        #expect(graph.recordingDocument?.identifier?.contains {
            $0.system?.value?.url.absoluteString == nativeSystem.rawValue
                && $0.value?.value?.string == nativeValue
        } == true)
        #expect(graph.recordingDocument?.id == nil)
    }

    @Test("An exporter refuses a governed native ID under generic or provider opaque namespaces")
    func governedNativeIDRejectsReservedSystem() throws {
        let identityScope = SensorFHIRIdentityTestSupport.identityScope
        for reserved in [
            identityScope.systems.sourceRecord,
            identityScope.systems.providerOutput,
            identityScope.systems.providerArtifact
        ] {
            #expect(throws: SensorKitFHIRExporter.ConfigurationError.reservedIdentifierSystem(reserved)) {
                try SensorKitExporterFixtures.exporter(SensorKitExporterFixtures.producer(), nativeIdentifier: .authorized(system: reserved))
            }
        }
    }

    @Test("An exporter refuses visit locations under provider output or artifact namespaces")
    func visitLocationRejectsProviderOpaqueSystems() throws {
        let identityScope = SensorFHIRIdentityTestSupport.identityScope
        for reserved in [
            identityScope.systems.providerOutput,
            identityScope.systems.providerArtifact
        ] {
            #expect(throws: SensorKitFHIRExporter.ConfigurationError.reservedIdentifierSystem(reserved)) {
                try SensorKitExporterFixtures.exporter(SensorKitExporterFixtures.producer(), visitLocationIdentifierSystem: reserved)
            }
        }
    }

    @Test
    func unregisteredRecordingFormatFailsClosed() throws {
        let record = try SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.heartRate",
            effectivePeriod: DateInterval(start: Self.start, duration: 1),
            nativeRecording: try Self.native(format: .nativeRecording)
        )
        #expect(throws: SensorKitConversionError.invalidRecord(
            .recordingFormatNotAdmitted("native-recording")
        )) {
            try SensorKitExporterFixtures.graph(.raw(record))
        }
    }

    @Test
    func structuredOnlyStreamCannotClaimRawSupport() throws {
        let record = try SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.sleepSessions",
            effectivePeriod: DateInterval(start: Self.start, duration: 1),
            nativeRecording: try Self.native()
        )
        #expect(throws: SensorKitConversionError.invalidRecord(
            .sourceTypeHasNoRawContract("SRSensor.sleepSessions")
        )) {
            try SensorKitExporterFixtures.graph(.raw(record))
        }
    }

    @Test
    func unknownSourceTokenIsNotAdmitted() throws {
        let record = try SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.headphoneMotion",
            effectivePeriod: DateInterval(start: Self.start, duration: 1),
            nativeRecording: try Self.native()
        )
        #expect(throws: SensorKitConversionError.invalidRecord(
            .sourceTypeNotAdmitted("SRSensor.headphoneMotion")
        )) {
            try SensorKitExporterFixtures.graph(.raw(record))
        }
    }
}
