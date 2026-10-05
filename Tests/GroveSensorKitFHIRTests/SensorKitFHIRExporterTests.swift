//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
@testable import GroveSensorKitFHIR
import ModelsR4
import Testing


@Suite
struct SensorKitFHIRExporterTests {
    private typealias Fixtures = SensorKitExporterFixtures

    private static let heartRateCSV = Data("timestamp,value,confidence,device\n1787009400,72,3,Watch\n".utf8)

    private static func sourceID(_ ordinal: UInt8) -> SensorKitSourceRecordID {
        SensorKitSourceRecordID(UUID(uuid: (0x87, 0x9d, 0x9e, 0xa2, 0x21, 0xcb, 0x45, 0x27, 0xb5, 0x9b, 0x28, 0x31, 0xdc, 0x4c, 0x84, ordinal)))
    }

    private static func sleep(_ ordinal: UInt8, hours: Double = 8) -> SensorKitRecord {
        .sleepSession(SensorKitSleepSessionRecord(
            sourceRecordID: sourceID(ordinal),
            session: DateInterval(start: Fixtures.start.addingTimeInterval(-hours * 3_600), end: Fixtures.start)
        ))
    }

    private static func heartRate(
        _ ordinal: UInt8,
        title: String = "Exact SensorKit heart rate batch",
        payload: SensorKitNativeRecording.Payload = .sidecar(path: "sensorkit/heart-rate.csv", bytes: heartRateCSV)
    ) throws -> SensorKitRecord {
        .raw(try SensorKitRawRecord(
            sourceRecordID: sourceID(ordinal),
            sourceToken: "SRSensor.heartRate",
            effectivePeriod: DateInterval(start: Fixtures.start, duration: 1),
            nativeRecording: try SensorKitNativeRecording(title: title, format: .heartRateSamples, payload: payload, admission: .verifiedSanitizedInput)
        ))
    }

    private static func wristTemperature(_ ordinal: UInt8) throws -> SensorKitRecord {
        .wristTemperature(try SensorKitWristTemperatureRecord(
            sourceRecordID: sourceID(ordinal),
            algorithmVersion: "2",
            nativeRecording: try SensorKitNativeRecording(
                title: "Exact SensorKit wrist temperature session",
                format: .wristTemperatureSamples,
                payload: .inline(Data("timestamp,value,errorEstimate,condition\n1787009400,33.5,0.1,\n1787009460,33.6,0.1,offWrist\n".utf8)),
                admission: .verifiedSanitizedInput
            )
        ))
    }

    private static func sequences(_ exports: [SensorKitFHIRExporter.Export]) -> [String?] {
        exports.map { $0.graph?.eventIdentifier.sequence.rawValue }
    }

    @Test("One call reserves one event per record; a redelivery before release restates it even from a rebuilt producer")
    func redeliveryReproducesEvents() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let exporter = try Fixtures.exporter(Fixtures.producer(storage: storage))
        let records = [Self.sleep(1), try Self.heartRate(2)]
        let (first, receipt) = try Fixtures.collect(exporter, records)
        #expect(Set(Self.sequences(first)) == ["1", "2"])
        #expect(first.map(\.source) == [Self.sourceID(1), Self.sourceID(2)])

        // Another application and an enrollment later, the reserved events still state the facts they froze.
        let rebuilt = try Fixtures.exporter(Fixtures.producer(
            application: .test(name: "Sensor Conformance", bundleIdentifier: "org.grovealliance.sensor-conformance", version: "0.6.0"),
            studies: [.test("study-a")],
            storage: storage
        ))
        let (again, againReceipt) = try Fixtures.collect(rebuilt, records, at: Fixtures.instant.addingTimeInterval(3_600))
        #expect(again.map(\.graph?.json) == first.map(\.graph?.json))

        receipt.release()
        againReceipt.release()
        let (afterRelease, _) = try Fixtures.collect(rebuilt, [records[0]])
        #expect(Self.sequences(afterRelease) == ["3"])
    }

    @Test("A refused record reserves nothing and the export continues in input order")
    func refusalsDoNotEndTheExport() throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let refused = SensorKitRecord.messagesUsage(SensorKitMessagesUsageRecord(
            sourceRecordID: Self.sourceID(3),
            timestamp: Fixtures.start,
            durationSeconds: 0,
            totalIncomingMessages: 1,
            totalOutgoingMessages: 1,
            totalUniqueContacts: 1
        ))
        let (exports, _) = try Fixtures.collect(exporter, [refused, Self.sleep(4)])
        try #require(exports.count == 2)
        guard case .refused(let reason) = exports[0].outcome else {
            Issue.record("expected a refusal, got \(exports[0].outcome)")
            return
        }
        #expect(reason == .invalidRecord(.invalidReportDuration(field: "duration")))
        #expect(exports[0].source == Self.sourceID(3))
        #expect(Self.sequences(exports) == [nil, "1"])
    }

    @Test("A record named again with other content in one call is refused; named again exactly, it shares the event")
    func duplicatesInOneCall() throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let (conflicting, _) = try Fixtures.collect(exporter, [Self.sleep(5), Self.sleep(5, hours: 7)])
        guard case .refused(.conflictingDuplicate) = conflicting[1].outcome else {
            Issue.record("expected a conflicting duplicate, got \(conflicting[1].outcome)")
            return
        }
        #expect(Self.sequences(conflicting) == ["1", nil])
        let (exact, _) = try Fixtures.collect(exporter, [Self.sleep(6), Self.sleep(6)])
        #expect(exact[0].graph?.json == exact[1].graph?.json)
        #expect(Self.sequences(exact) == ["2", "2"])
    }

    @Test("Any content a graph states from the record or the call mints a new event under a held key")
    func contentChangesMintNewEvents() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let exporter = try Fixtures.exporter(Fixtures.producer(storage: storage))
        var receipts: [ExchangeProducer.Receipt] = []
        func sequence(
            _ record: SensorKitRecord,
            through exporter: SensorKitFHIRExporter = exporter,
            timeZone: TimeZone? = nil,
            recordingDevice: RecordingDevice? = Fixtures.watch
        ) throws -> String? {
            let (exports, receipt) = try Fixtures.collect(exporter, [record], timeZone: timeZone, recordingDevice: recordingDevice)
            receipts.append(receipt)
            return exports.first?.graph?.eventIdentifier.sequence.rawValue
        }
        let base = try Self.heartRate(7)
        #expect(try sequence(base) == "1")
        #expect(try sequence(base) == "1")
        #expect(try sequence(base, timeZone: TimeZone(identifier: "Europe/Berlin")) == "2")
        #expect(try sequence(Self.heartRate(7, title: "Another title")) == "3")
        #expect(try sequence(Self.heartRate(7, payload: .sidecar(path: "sensorkit/other.csv", bytes: Self.heartRateCSV))) == "4")
        #expect(try sequence(Self.heartRate(7, payload: .inline(Self.heartRateCSV))) == "5")
        let otherBytes = Data("timestamp,value,confidence,device\n1787009400,73,3,Watch\n".utf8)
        #expect(try sequence(Self.heartRate(7, payload: .sidecar(path: "sensorkit/heart-rate.csv", bytes: otherBytes))) == "6")
        #expect(try sequence(base, recordingDevice: .test(stableUnitToken: "watch-42", name: "Renamed Watch")) == "7")
        #expect(try sequence(base, recordingDevice: .test(stableUnitToken: "watch-43", name: "Example Watch")) == "8")
        #expect(try sequence(base, recordingDevice: nil) == "9")
        // Each setting changes alone against the step before it, so no other change masks it.
        let otherVisitSystem = try Fixtures.exporter(
            Fixtures.producer(storage: storage),
            visitLocationIdentifierSystem: "https://study.example.org/fhir/NamingSystem/other-visit-location"
        )
        #expect(try sequence(base, through: otherVisitSystem, recordingDevice: nil) == "10", "a setting the record's bytes do not show")
        #expect(try sequence(base, recordingDevice: nil) == "11", "the key keeps only its latest content's event")
        let disclosing = try Fixtures.exporter(Fixtures.producer(storage: storage), nativeIdentifier: .authorized(system: Fixtures.nativeSystem))
        #expect(try sequence(base, through: disclosing, recordingDevice: nil) == "12")
    }

    @Test("One source-record identifier under two sensors names two records, each with its own event")
    func sensorsKeepTheirOwnEvents() throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let (exports, _) = try Fixtures.collect(exporter, [Self.sleep(12), try Self.heartRate(12)])
        #expect(Set(Self.sequences(exports)) == ["1", "2"])
    }

    @Test("The request's content parts name every stored property of the drafts, and its context every option")
    func fingerprintCoversEveryProperty() throws {
        let sourceRecord = try SensorFHIRIdentityTestSupport.identityScope.sourceRecord(
            adapterID: SensorKitConverter.adapterID,
            sourceType: "SRSensor.wristTemperature",
            repositoryScope: SensorFHIRIdentityTestSupport.repositoryScope,
            nativeRecordID: Self.sourceID(8).value
        )
        let outputs = try SensorKitConverter.outputs(
            of: Self.wristTemperature(8),
            sourceRecord: sourceRecord,
            nativeIdentifier: GovernedSourceIdentifierDisclosurePolicy.authorized(system: Fixtures.nativeSystem).identifier(for: Self.sourceID(8).value),
            context: SensorKitConverter.ContentContext(
                sourceTimeZone: Fixtures.timeZone,
                visitLocationIdentifierSystem: SensorFHIRIdentityTestSupport.visitLocationIdentifierSystem
            )
        )
        try #require(outputs.count == 2)
        #expect(outputs[0].trailingExtensions.count == 1)
        for output in outputs {
            #expect(try output.contentParts.map(\.property) == Mirror(reflecting: output).children.map { $0.label ?? "" })
        }
        let device = SensorKitConverter.recordingDevice(Fixtures.watch)
        #expect(try device.contentParts.map(\.property) == Mirror(reflecting: device).children.map { $0.label ?? "" })
        #expect(Mirror(reflecting: Fixtures.watch).children.map(\.label) == ["stableUnitToken", "name", "manufacturer", "modelNumber"])

        var options = SensorKitFHIRExporter.Options()
        for policy in [GovernedSourceIdentifierDisclosurePolicy.omit, .authorized(system: Fixtures.nativeSystem)] {
            options.nativeIdentifier = policy
            let stored = Mirror(reflecting: options).children.map { child in
                (property: child.label ?? "", parts: (child.value as? any ExchangeContextFingerprinted)?.fingerprintParts ?? [])
            }
            #expect(options.fingerprintParts.map(\.property) == stored.map(\.property))
            #expect(options.fingerprintParts.map(\.parts) == stored.map(\.parts))
        }
    }

    /// A reservation keeps the fingerprint it was made under, and every later export compares against it, across launches
    /// and app updates: a build that derives the same request's fingerprint differently gives every pending reservation a
    /// new sequence on redelivery, so the derivation, call parts and record parts alike, changes only on purpose, as
    /// with an output revision.
    @Test("A fixed record's request fingerprints to a known answer")
    func requestFingerprintIsAKnownAnswer() throws {
        try #require(ExchangeGraphAssembler.outputRevision == 1 && SensorKitConverter.outputRevision == 1, "a revision bump restates the answer")
        let exporter = try Fixtures.exporter(Fixtures.producer(), nativeIdentifier: .authorized(system: Fixtures.nativeSystem))
        let plan = SensorKitFHIRExporter.Plan(
            try Self.wristTemperature(8),
            content: SensorKitConverter.ContentContext(
                sourceTimeZone: try Fixtures.timeZone,
                visitLocationIdentifierSystem: SensorFHIRIdentityTestSupport.visitLocationIdentifierSystem
            ),
            recordingDevice: SensorKitConverter.recordingDevice(Fixtures.watch),
            exporter: exporter
        )
        let request = try plan.content.get().request
        #expect(request.fingerprint == "PNvoLV5fSCGtYfNmnKkauM15zWRYxnKfHBirLjcUDR8")
    }

    @Test("Every converter-clock instant states the reservation's millisecond, kept on a redelivery")
    func instantsAreTheReservationsMillisecond() throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let instant = Fixtures.start.addingTimeInterval(20.123_456_7)
        let record = try Self.heartRate(9)
        let (exports, _) = try Fixtures.collect(exporter, [record], at: instant)
        let graph = try #require(exports.first?.graph)
        let provenance = try graph.provenance
        #expect(graph.bundle.timestamp?.value?.description == "2026-08-17T23:30:20.123Z")
        #expect(graph.recordingDocument?.date?.value?.description == "2026-08-17T23:30:20.123Z")
        #expect(provenance.recorded.value?.description == "2026-08-17T23:30:20.123Z")
        guard case .dateTime(let occurred)? = provenance.occurred else {
            Issue.record("The Provenance lost its occurred time")
            return
        }
        #expect(occurred.value?.description == "2026-08-17T23:30:20.123Z")
        let (again, _) = try Fixtures.collect(exporter, [record], at: instant.addingTimeInterval(60))
        #expect(again.first?.graph?.json == graph.json)
    }

    @Test("Study references follow an output's own statements; the wrist-temperature algorithm version follows them")
    func studyContextOrder() throws {
        let studies: [StudyEnrollment] = try [.test("study-a"), .test("study-b")]
        let exporter = try Fixtures.exporter(Fixtures.producer(studies: studies))
        let (exports, _) = try Fixtures.collect(exporter, [try Self.wristTemperature(10)], recordingDevice: nil)
        let graph = try #require(exports.first?.graph)
        let observation = try #require(graph.observations.first)
        #expect(observation.extension?.map(\.url.value?.url.absoluteString) == [
            SensorKitContract.sourceTypeExtension,
            Canonicals.researchStudy.value?.url.absoluteString,
            Canonicals.researchStudy.value?.url.absoluteString,
            SensorKitContract.wristTemperatureAlgorithmVersionExtension
        ])
        let related = try #require(graph.recordingDocument?.context?.related)
        #expect(related.count == 3)
        #expect(related[0].reference?.value?.string == graph.bundle.entry?.first?.fullUrl?.value?.url.absoluteString)
        #expect(related.dropFirst().allSatisfy { $0.type?.value?.url.absoluteString == "ResearchStudy" })
    }

    @Test("An error in the receiver ends the call with the reservations kept")
    func receiverErrorsPropagate() throws {
        struct Stop: Error {}
        let exporter = try Fixtures.exporter(Fixtures.producer())
        #expect(throws: Stop.self) {
            try exporter.export([Self.sleep(11)], sourceTimeZone: Fixtures.timeZone) { _ in throw Stop() }
        }
        let (again, _) = try Fixtures.collect(exporter, [Self.sleep(11)], recordingDevice: nil)
        #expect(Self.sequences(again) == ["1"])
    }

    @Test("Every conversion failure narrows to the refusal domain by its type")
    func failuresNarrowToTheRefusalDomain() {
        struct Unmodelled: Error {}
        #expect(SensorKitConversionError(conversionFailure: SensorKitConversionError.conflictingDuplicate) == .conflictingDuplicate)
        #expect(SensorKitConversionError(conversionFailure: SensorKitRecordError.emptySamples) == .invalidRecord(.emptySamples))
        #expect(SensorKitConversionError(conversionFailure: ExchangeIdentityError.invalidInstant) == .exchangeIdentity(.invalidInstant))
        #expect(SensorKitConversionError(conversionFailure: ExchangeGraphError.missingTimestamp) == .exchangeGraph(.missingTimestamp))
        #expect(SensorKitConversionError(conversionFailure: Unmodelled()) == .unexpectedConversionFailure(String(reflecting: Unmodelled.self)))
    }
}


extension StudyEnrollment {
    static func test(_ id: String) throws -> StudyEnrollment {
        try StudyEnrollment(
            study: BusinessIdentifier(system: "https://grovealliance.org/fhir/testing/identifiers/researchstudy", value: id),
            protocolURL: FHIRPrimitive(Canonical(stringLiteral: "https://study.example.org/PlanDefinition/\(id)")),
            protocolVersion: "1",
            enrollment: BusinessIdentifier(system: "https://grovealliance.org/fhir/testing/identifiers/researchsubject", value: "enrollment-\(id)")
        )
    }
}
