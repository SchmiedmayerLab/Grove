//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CryptoKit
import Foundation
@testable import GroveFHIRContract
@testable import GroveSensorKitFHIR
import ModelsR4
import Testing


// One suite covers the exporter's whole surface: its records, their devices and their packing.
// swiftlint:disable type_body_length

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
            nativeRecording: try SensorKitNativeRecording(
                title: title,
                format: .heartRateSamples,
                payload: payload,
                admission: .verifiedSanitizedInput
            )
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

    private static func recordingDevices(in graph: ExchangeGraph) -> [(url: String, device: Device)] {
        (graph.bundle.entry ?? []).compactMap { entry in
            guard let device = entry.resource?.get() as? Device,
                  device.meta?.profile?.contains(Profile.groveRecordingDevice) == true,
                  let url = entry.fullUrl?.value?.url.absoluteString else {
                return nil
            }
            return (url, device)
        }
    }

    private static func versionCodes(of device: Device) -> [String?] {
        (device.version ?? []).map { $0.type?.coding?.first?.code?.value?.string }
    }

    private static func values(of device: Device, code: String) -> [String?] {
        (device.version ?? []).filter { $0.type?.coding?.first?.code?.value?.string == code }.map { $0.value.value?.string }
    }

    private static func names(of device: Device) -> [DeviceNameType?: String?] {
        Dictionary(uniqueKeysWithValues: (device.deviceName ?? []).map { ($0.type.value, $0.name.value?.string) })
    }

    @Test("A redelivery at the persisted instant repeats every record, byte for byte, even through a rebuilt exporter")
    func redeliveryRepeatsEveryRecord() async throws {
        let records = [Self.sleep(1), try Self.heartRate(2)]
        let first = try await Fixtures.collect(Fixtures.exporter(Fixtures.producer()), records)
        #expect(first.map(\.source) == [Self.sourceID(1), Self.sourceID(2)])
        let again = try await Fixtures.collect(Fixtures.exporter(Fixtures.producer()), records)
        #expect(first.compactMap(\.record).count == 2)
        #expect(again.map(\.record?.json) == first.map(\.record?.json))
    }

    @Test("A later conversion is a new version of the same source record")
    func laterConversionIsANewVersion() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let first = try #require(try await Fixtures.collect(exporter, [Self.sleep(3)]).first?.record)
        let later = try #require(
            try await Fixtures.collect(exporter, [Self.sleep(3)], at: Fixtures.instant.addingTimeInterval(3_600)).first?.record
        )
        #expect(later.sourceRecord == first.sourceRecord)
        #expect(later.outputFullURLs == first.outputFullURLs)
        #expect(later.version != first.version)
    }

    @Test("A refused record stops nothing and the export continues in input order")
    func refusalsDoNotEndTheExport() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let refused = SensorKitRecord.messagesUsage(SensorKitMessagesUsageRecord(
            sourceRecordID: Self.sourceID(3),
            timestamp: Fixtures.start,
            durationSeconds: 0,
            totalIncomingMessages: 1,
            totalOutgoingMessages: 1,
            totalUniqueContacts: 1
        ))
        let exports = try await Fixtures.collect(exporter, [refused, Self.sleep(4)])
        try #require(exports.count == 2)
        guard case .refused(let reason) = exports[0].outcome else {
            Issue.record("expected a refusal, got \(exports[0].outcome)")
            return
        }
        #expect(reason == .invalidRecord(.invalidReportDuration(field: "duration")))
        #expect(exports[0].source == Self.sourceID(3))
        #expect(exports[0].record == nil)
        #expect(exports[1].record != nil)
    }

    @Test("A record named again in one call is delivered again: exactly, it repeats; with other content, it is a second version")
    func duplicatesInOneCall() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let exact = try await Fixtures.collect(exporter, [Self.sleep(6), Self.sleep(6)])
        #expect(exact[0].record != nil)
        #expect(exact[0].record == exact[1].record)
        let changed = try await Fixtures.collect(exporter, [Self.sleep(5), Self.sleep(5, hours: 7)])
        let first = try #require(changed[0].record)
        let second = try #require(changed[1].record)
        #expect(first.sourceRecord == second.sourceRecord)
        #expect(first.version != second.version)
    }

    @Test("Any content a record states from the source or the call gives it a new version")
    func contentChangesMintNewVersions() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        func record(
            _ input: SensorKitRecord,
            through exporter: SensorKitFHIRExporter = exporter,
            timeZone: TimeZone? = nil,
            recordingDevice: RecordingDevice? = Fixtures.watch,
            sourceDevices: [RecordingDevice] = []
        ) async throws -> ExchangeRecord {
            try #require(try await Fixtures.collect(
                exporter,
                [input],
                timeZone: timeZone,
                recordingDevice: recordingDevice,
                sourceDevices: sourceDevices
            ).first?.record)
        }
        let base = try Self.heartRate(7)
        let otherBytes = Data("timestamp,value,confidence,device\n1787009400,73,3,Watch\n".utf8)
        var tokenized = Fixtures.watch
        tokenized.stableUnitToken = "watch-42"
        tokenized.tokenScope = "org.example.fleet"
        var otherToken = tokenized
        otherToken.stableUnitToken = "watch-43"
        let disclosing = try Fixtures.exporter(Fixtures.producer(), nativeIdentifier: .authorized(system: Fixtures.nativeSystem))
        let otherApplication = try Fixtures.exporter(Fixtures.producer(
            application: .test(name: "Sensor Conformance", bundleIdentifier: "org.grovealliance.sensor-conformance", version: "0.6.0")
        ))
        let records = [
            try await record(base),
            try await record(base, timeZone: TimeZone(identifier: "Europe/Berlin")),
            try await record(Self.heartRate(7, title: "Another title")),
            try await record(Self.heartRate(7, payload: .sidecar(path: "sensorkit/other.csv", bytes: Self.heartRateCSV))),
            try await record(Self.heartRate(7, payload: .inline(Self.heartRateCSV))),
            try await record(Self.heartRate(7, payload: .sidecar(path: "sensorkit/heart-rate.csv", bytes: otherBytes))),
            try await record(base, recordingDevice: .test(name: "Renamed Watch")),
            try await record(base, recordingDevice: .test(systemVersion: "11.3")),
            try await record(base, recordingDevice: tokenized),
            try await record(base, recordingDevice: otherToken),
            try await record(base, recordingDevice: nil),
            try await record(base, sourceDevices: [.testPeripheral()]),
            try await record(base, sourceDevices: [.testPeripheral(firmwareVersion: "5.2")]),
            try await record(base, through: disclosing),
            try await record(base, through: otherApplication)
        ]
        #expect(Set(records.map(\.sourceRecord)).count == 1)
        #expect(Set(records.map(\.version)).count == records.count)
    }

    @Test("A setting the record's bytes do not show leaves its version alone")
    func unstatedSettingsKeepTheVersion() async throws {
        let base = try Self.heartRate(7)
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let otherVisitSystem = try Fixtures.exporter(
            Fixtures.producer(),
            visitLocationIdentifierSystem: "https://study.example.org/fhir/NamingSystem/other-visit-location"
        )
        let first = try await Fixtures.collect(exporter, [base]).first?.record
        let again = try await Fixtures.collect(otherVisitSystem, [base]).first?.record
        #expect(first != nil)
        #expect(first == again)
    }

    @Test("One source-record identifier under two sensors names two source records")
    func sensorsKeepTheirOwnRecords() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let exports = try await Fixtures.collect(exporter, [Self.sleep(12), try Self.heartRate(12)])
        #expect(Set(exports.compactMap(\.record?.sourceRecord)).count == 2)
    }

    @Test("Every converter-clock instant states the conversion's millisecond; `recorded` and the record's timestamp agree")
    func instantsAreTheConversionsMillisecond() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let instant = Fixtures.start.addingTimeInterval(20.123_456_7)
        let exports = try await Fixtures.collect(exporter, [try Self.heartRate(9)], at: instant)
        let graph = try #require(exports.first?.record).graph
        let provenance = try graph.provenance
        #expect(graph.bundle.timestamp?.value?.description == "2026-08-17T23:30:20.123Z")
        #expect(graph.recordingDocument?.date?.value?.description == "2026-08-17T23:30:20.123Z")
        #expect(provenance.recorded.value?.description == "2026-08-17T23:30:20.123Z")
        guard case .dateTime(let occurred)? = provenance.occurred else {
            Issue.record("The Provenance lost its occurred time")
            return
        }
        #expect(occurred.value?.description == "2026-08-17T23:30:20.123Z")
    }

    @Test("Study references follow an Observation's own statements; the wrist-temperature algorithm version follows them")
    func studyContextOrder() async throws {
        let studies: [StudyEnrollment] = try [.test("study-a"), .test("study-b")]
        let exporter = try Fixtures.exporter(Fixtures.producer(studies: studies))
        let exports = try await Fixtures.collect(exporter, [try Self.wristTemperature(10)], recordingDevice: nil)
        let graph = try #require(exports.first?.record).graph
        let observation = try #require(graph.observations.first)
        #expect(observation.extension?.map(\.url.value?.url.absoluteString) == [
            SensorKitContract.sourceTypeExtension,
            Canonicals.researchStudy.value?.url.absoluteString,
            Canonicals.researchStudy.value?.url.absoluteString,
            SensorKitContract.wristTemperatureAlgorithmVersionExtension
        ])
        let related = try #require(graph.recordingDocument?.context?.related)
        #expect(related.count == 1, "a hybrid document relates exactly to its Observation")
        #expect(related.first?.reference?.value?.string == graph.bundle.entry?.first?.fullUrl?.value?.url.absoluteString)
    }

    @Test("A document with no Observation states the study references itself")
    func rawDocumentStatesTheStudies() async throws {
        let studies: [StudyEnrollment] = try [.test("study-a"), .test("study-b")]
        let exporter = try Fixtures.exporter(Fixtures.producer(studies: studies))
        let raw = try SensorKitRawRecord(
            sourceRecordID: SensorKitSourceRecordID(try #require(UUID(uuidString: "248b854a-8d64-4308-9ee0-d220e7d747d3"))),
            sourceToken: "SRSensor.heartRate",
            effectivePeriod: DateInterval(start: Fixtures.start, duration: 1),
            nativeRecording: try SensorKitNativeRecording(
                title: "Exact SensorKit heart rate batch",
                format: .heartRateSamples,
                payload: .inline(Data("timestamp,value,confidence,device\n1787009400,72,3,Watch\n".utf8)),
                admission: .verifiedSanitizedInput
            )
        )
        let exports = try await Fixtures.collect(exporter, [.raw(raw)], recordingDevice: nil)
        let record = try #require(exports.first?.record)
        let related = try #require(record.graph.recordingDocument?.context?.related)
        #expect(related.count == 2)
        #expect(related.allSatisfy { $0.type?.value?.url.absoluteString == "ResearchStudy" })
    }

    @Test("An error in the receiver ends the call")
    func receiverErrorsPropagate() async throws {
        struct Stop: Error {}
        let exporter = try Fixtures.exporter(Fixtures.producer())
        await #expect(throws: Stop.self) {
            try await exporter.export(
                [Self.sleep(11)],
                sourceTimeZone: Fixtures.timeZone,
                recordingDevice: nil,
                at: Fixtures.instant
            ) { _ in throw Stop() }
        }
    }

    @Test("An instant no FHIR instant can state ends the call before any record")
    func unstatableInstantsEndTheCall() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        await #expect(throws: ExchangeIdentityError.invalidInstant) {
            try await exporter.export(
                [Self.sleep(11)],
                sourceTimeZone: Fixtures.timeZone,
                recordingDevice: nil,
                at: .distantFuture.addingTimeInterval(315_576_000_000)
            ) { _ in Issue.record("The call delivered a record") }
        }
    }

    @Test("Every conversion failure narrows to the refusal domain by its type")
    func failuresNarrowToTheRefusalDomain() {
        struct Unmodelled: Error {}
        #expect(SensorKitConversionError(conversionFailure: SensorKitConversionError.payloadTooLarge(byteCount: 1)) == .payloadTooLarge(byteCount: 1))
        #expect(SensorKitConversionError(conversionFailure: SensorKitRecordError.emptySamples) == .invalidRecord(.emptySamples))
        #expect(SensorKitConversionError(conversionFailure: ExchangeIdentityError.invalidInstant) == .exchangeIdentity(.invalidInstant))
        #expect(SensorKitConversionError(conversionFailure: ExchangeGraphError.missingTimestamp) == .exchangeGraph(.missingTimestamp))
        #expect(SensorKitConversionError(conversionFailure: Unmodelled()) == .unexpectedConversionFailure(String(reflecting: Unmodelled.self)))
    }

    @Test("An identity fault reports its own registry code")
    func identityFaultsKeepTheirCodes() {
        let faults = [
            ExchangeIdentityError.emptyComponent("source-record.native-record-id"),
            .nonCanonicalPartIndex("source-artifact.part-index")
        ]
        for fault in faults {
            #expect(SensorKitConversionError.exchangeIdentity(fault).diagnostic == fault.diagnostic)
        }
        #expect(faults.map(\.diagnostic.code) == ["mobile-input.required-metadata-missing", "mobile-input.unclassified"])
    }

    @Test("Every output names the recording Device of its SRDevice, which states each fact SensorKit exposes")
    func recordingDeviceStatesEveryFact() async throws {
        let graph = try await Fixtures.graph(try Self.wristTemperature(13))
        let devices = Self.recordingDevices(in: graph)
        try #require(devices.count == 1)
        let device = devices[0].device
        #expect(Self.names(of: device) == [.userFriendlyName: "Example Watch", .modelName: "Apple Watch"])
        #expect(device.modelNumber?.value?.string == "Watch7,1")
        #expect(Self.values(of: device, code: "os-name") == ["watchOS"])
        #expect(Self.values(of: device, code: "os-version") == ["11.2"])
        #expect(Self.versionCodes(of: device).count == 2)
        #expect(device.serialNumber == nil)
        let roles = (device.identifier ?? []).compactMap { try? RoledIdentifier($0).role }
        #expect(roles == [.deviceSnapshot], "SensorKit states no per-unit token, so the snapshot is the Device's only key")
        #expect(graph.observations.first?.device?.reference?.value?.string == devices[0].url)
        #expect(graph.recordingDocument?.author?.first?.reference?.value?.string == devices[0].url)
    }

    @Test("A governed per-unit token adds the unit identity beside the snapshot")
    func unitTokenAddsTheUnitIdentity() async throws {
        var device = Fixtures.watch
        device.stableUnitToken = "watch-42"
        device.tokenScope = "org.example.fleet"
        let graph = try await Fixtures.graph(Self.sleep(14), recordingDevice: device)
        let identifiers = try #require(Self.recordingDevices(in: graph).first?.device.identifier)
        #expect(identifiers.compactMap { try? RoledIdentifier($0).role } == [.deviceSnapshot, .recordingDevice])
    }

    @Test("A peripheral is a recording Device of its own, which the source entity names and no output references")
    func peripheralIsARecordingDeviceOfItsOwn() async throws {
        let record = try await Fixtures.record(try Self.wristTemperature(15), sourceDevices: [.testPeripheral()])
        let graph = try record.graph
        let devices = Self.recordingDevices(in: graph)
        try #require(devices.count == 2)
        let (watch, peripheral) = (devices[0], devices[1])
        #expect(graph.observations.first?.device?.reference?.value?.string == watch.url)
        #expect(graph.recordingDocument?.author?.map(\.reference?.value?.string).contains(peripheral.url) == false)

        #expect(peripheral.device.manufacturer?.value?.string == "Example Audio")
        #expect(peripheral.device.modelNumber?.value?.string == "Ear One")
        #expect(peripheral.device.deviceName == nil)
        #expect(Self.values(of: peripheral.device, code: "531974") == ["2"])
        #expect(Self.values(of: peripheral.device, code: "531976") == ["5.1"])
        let scope = SensorFHIRIdentityTestSupport.identityScope
        let local = try #require(peripheral.device.identifier?.first {
            $0.system?.value?.url.absoluteString == scope.systems.deviceLocalIdentifier.rawValue
        })
        #expect(local.value?.value?.string == "peripheral-7")
        #expect(local.type?.coding?.first?.code?.value?.string == "device-local-identifier")
        #expect(local.type?.coding?.first?.system == Canonicals.groveDeviceIdentifierType)

        let agents = try #require(try graph.provenance.entity?.first?.agent)
        #expect(agents.map(\.who.reference?.value?.string) == [peripheral.url])
        #expect(agents.first?.type?.coding?.first?.code?.value?.string == "performer")
        #expect(record.sharedNodeFullURLs.isSuperset(of: [watch.url, peripheral.url]))
        try record.verifyVersion(in: scope)
    }

    @Test("Without a peripheral the source entity names no agent")
    func noPeripheralNoAgent() async throws {
        let graph = try await Fixtures.graph(Self.sleep(16))
        #expect(try graph.provenance.entity?.first?.agent == nil)
        #expect(Self.recordingDevices(in: graph).count == 1)
    }

    @Test("A peripheral named twice, or stating the recording Device's content, stays one entry")
    func repeatedPeripheralsCollapse() async throws {
        let peripheral = RecordingDevice.testPeripheral()
        let other = RecordingDevice.testPeripheral(localIdentifier: "peripheral-8")
        let graph = try await Fixtures.graph(Self.sleep(17), sourceDevices: [peripheral, other, peripheral])
        #expect(Self.recordingDevices(in: graph).count == 3)
        #expect(try graph.provenance.entity?.first?.agent?.count == 2)

        let same = try await Fixtures.graph(Self.sleep(17), recordingDevice: peripheral, sourceDevices: [peripheral])
        #expect(Self.recordingDevices(in: same).count == 1)
        #expect(try same.provenance.entity?.first?.agent == nil)
    }

    @Test("A peripheral survives packing: read back from its Bundle, a record keeps both recording Devices and its version")
    func peripheralSurvivesPacking() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let exports = try await Fixtures.collect(exporter, [Self.sleep(18), Self.sleep(19)], sourceDevices: [.testPeripheral()])
        let records = exports.compactMap(\.record)
        var packer = ExchangeBundlePacker(kind: .active)
        for record in records {
            #expect(try packer.add(record) == .added)
        }
        let packed = try packer.bundle(packedAt: Fixtures.instant.addingTimeInterval(60))
        #expect(Self.recordingDevices(in: packed).count == 2, "Both records share one Device entry each")
        let readBack = try packed.records()
        #expect(readBack.map(\.version) == records.map(\.version))
        #expect(readBack.map(\.sharedNodeFullURLs) == records.map(\.sharedNodeFullURLs))
    }

    @Test("The application Device states its Apple bundle identifier")
    func applicationDeviceStatesItsBundleIdentifier() async throws {
        let graph = try await Fixtures.graph(Self.sleep(20))
        let application = try #require(graph.devices.first { $0.meta?.profile?.contains(Profile.groveApplicationDevice) == true })
        let bundleIdentifier = try #require(application.identifier?.first {
            $0.type?.coding?.first?.code?.value?.string == HealthKitContract.appleBundleIdentifierTypeCode
        })
        #expect(bundleIdentifier.system == HealthKitContract.appleBundleIdentifierSystem)
        #expect(bundleIdentifier.value?.value?.string == Fixtures.application.bundleIdentifier)
    }

    @Test("A call's records pack into one Bundle stating each shared node once, and read back unchanged")
    func recordsPackIntoOneBundle() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let exports = try await Fixtures.collect(exporter, [Self.sleep(21), try Self.heartRate(22), try Self.wristTemperature(23)])
        let records = exports.compactMap(\.record)
        try #require(records.count == 3)
        #expect(Set(records.map(\.sourceRecord)).count == 3)
        let shared = Set(records.flatMap(\.sharedNodeFullURLs))
        #expect(shared.count == records[0].sharedNodeFullURLs.count, "The records of one call state the same shared nodes")

        var packer = ExchangeBundlePacker(kind: .active)
        for record in records {
            #expect(try packer.add(record) == .added)
        }
        let packed = try packer.bundle(packedAt: Fixtures.instant.addingTimeInterval(60))
        let provenances = records.count
        let outputs = records.reduce(0) { $0 + $1.outputFullURLs.count }
        #expect(packed.bundle.entry?.count == shared.count + provenances + outputs)
        #expect(packed.bundle.timestamp?.value?.description == "2026-08-17T23:32:00Z")
        let readBack = try packed.records()
        #expect(readBack.map(\.version) == records.map(\.version))
        for record in readBack {
            try record.verifyVersion(in: SensorFHIRIdentityTestSupport.identityScope)
        }
    }

    @Test("Every record reads back from its own bytes, and its version only recomputes under the identity key")
    func recordsReadBackFromTheirBytes() async throws {
        let record = try await Fixtures.record(try Self.wristTemperature(24))
        let readBack = try ExchangeRecord(validating: record.json)
        #expect(readBack == record)
        try readBack.verifyVersion(in: SensorFHIRIdentityTestSupport.identityScope)
        let otherKey = try OpaqueIdentityScope(
            systems: SensorFHIRIdentityTestSupport.identityScope.systems,
            keyID: "test",
            epoch: KeyEpoch(1),
            key: SymmetricKey(data: Data(repeating: 0x43, count: 32))
        )
        #expect(throws: ExchangeGraphError.invalidRecordVersion) {
            try readBack.verifyVersion(in: otherKey)
        }
    }

    @Test("Every identity system of the deployment stays reserved, the record-version and context-snapshot systems too")
    func newSystemsAreReserved() throws {
        let systems = SensorFHIRIdentityTestSupport.identityScope.systems
        for system in [systems.recordVersion, systems.recordRetraction, systems.contextSnapshot] {
            #expect(throws: SensorKitFHIRExporter.ConfigurationError.reservedIdentifierSystem(system)) {
                try Fixtures.exporter(Fixtures.producer(), visitLocationIdentifierSystem: system)
            }
        }
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
