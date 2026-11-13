//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


private let groveFHIRRoot: URL = {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let candidates = [
        repositoryRoot.appendingPathComponent(".fhir/grove-fhir", isDirectory: true),
        repositoryRoot.deletingLastPathComponent().appendingPathComponent("grove-fhir", isDirectory: true)
    ]
    return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("catalog").path) } ?? candidates[0]
}()

private let groveFHIRIsAvailable = FileManager.default.fileExists(
    atPath: groveFHIRRoot.appendingPathComponent("catalog/exchange-protocol.json").path
)


/// Every optional parameter defaults the same way on every platform.
@Suite
struct ProducerDefaultsTests {
    @Test("Device facts default to nothing beyond what identifies the device")
    func deviceDefaults() throws {
        let application = try ApplicationDevice(name: "Grove", bundleIdentifier: "org.grovealliance.app", version: "1.0")
        #expect(application.build == nil)

        let host = try HostDevice(operatingSystemVersion: "26.0")
        #expect(host.name == nil && host.manufacturer == nil && host.productType == nil)
        let current = HostDevice.current()
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #expect(current.operatingSystemVersion == "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
        #expect(current.name == nil && current.manufacturer == nil)

        let recording = RecordingDevice()
        #expect(recording.stableUnitToken == nil && recording.name == nil && recording.manufacturer == nil && recording.model == nil)
    }

    @Test("HealthKit metadata defaults to preservation and other disclosures remain explicit")
    func healthKitOptionDefaults() {
        let options = HealthKitFHIRExporter.Options()
        guard case .omit = options.writer else {
            Issue.record("the default writer policy is \(options.writer)")
            return
        }
        guard case .localIdentifier = options.unitToken else {
            Issue.record("the default unit-token policy is \(options.unitToken)")
            return
        }
        #expect(options.role == .assembler)
        #expect(options.metadata == .authorized)
        #expect(options.route == .omit)
        #expect(options.nativeIdentifier == .omit)
    }

    @Test("Optional identifiers default to nil")
    func identifierDefaults() throws {
        guard case .authorized(_, let type) = GovernedSourceIdentifierDisclosurePolicy.authorized(system: "https://store.example.org") else {
            Issue.record("An authorized policy keeps its shape")
            return
        }
        #expect(type == nil)

        let scope = TestDeployment.test().identityScope
        let record = try scope.sourceRecord(
            adapterID: "healthkit",
            sourceType: "HKQuantityTypeIdentifierHeartRate",
            repositoryScope: TestDeployment.test().repositoryScope,
            nativeRecordID: "record-1"
        )
        let output = try record.output(role: "primary", discriminator: "0")
        let target = try RetractionRecord.Target(identifier: output, resourceType: .observation, role: .primaryOutput)
        #expect(target.nativeRecordIdentifier == nil)
    }
}


/// A warning is one registered `mobile-omission.*` row, and only those rows carry the warning severity.
@Suite
struct ProducerWarningTests {
    private static let effectiveDateTimeOffsetUnavailable = ExchangeGraphRule.mobileOmissionSourceOffset.diagnostic(at: "Observation.effectiveDateTime")
    private static let unmodeledMetadataWithheld = ExchangeGraphRule.mobileOmissionUnmodeledMetadata.diagnostic(at: "HKSample.metadata")
    private static let recordingMethodOmitted = ExchangeGraphRule.mobileOmissionRecordingMethod.diagnostic(at: "Observation.extension")

    private static let warnings = [effectiveDateTimeOffsetUnavailable, unmodeledMetadataWithheld, recordingMethodOmitted]

    private static func heartRate(device: HKDevice, metadata: [String: Any]) -> HKQuantitySample {
        let start = TestDeployment.testInstant
        return HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 72),
            start: start,
            end: start,
            device: device,
            metadata: metadata
        )
    }

    @Test("Each warning is one registry row of severity warning")
    func warningsAreWarningRows() throws {
        let codes = Self.warnings.map(\.code)
        #expect(codes == [
            "mobile-omission.source-offset",
            "mobile-omission.unmodeled-metadata",
            "mobile-omission.recording-method"
        ])
        for warning in Self.warnings {
            let rule = try #require(ExchangeGraphRule(rawValue: warning.code))
            #expect(rule.severity == .warning)
            #expect(warning.reason == rule.reason)
            #expect(warning.severity == .warning)
        }
        #expect(Self.warnings[0].location == "Observation.effectiveDateTime")
        #expect(Self.warnings[1].location == "HKSample.metadata")
        #expect(Self.warnings[2].location == "Observation.extension")
        #expect(Set(ExchangeGraphRule.allCases.filter { $0.severity == .warning }.map(\.rawValue)) == Set(codes))
    }

    @Test("Every error the adapters raise maps to a rule of severity error")
    func errorsAreErrorRows() {
        let errors: [HealthKitConversionError] = [
            .unregisteredSourceType("HKQuantityTypeIdentifierExample"),
            .notYetConvertible(.food),
            .invalidValue(.stepCount, .outsideDomain),
            .ecgEvidence(.evidenceRequired)
        ]
        for error in errors {
            #expect(error.diagnostic.severity == .error)
            #expect(ExchangeGraphRule(rawValue: error.diagnostic.code)?.severity == .error)
        }
    }

    @Test("An export reports exactly what the graph lost")
    func conversionReportsOmissions() async throws {
        let unidentified = HKDevice(
            name: "Example Watch",
            manufacturer: "Example",
            model: "W42",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
        let identified = HKDevice(
            name: "Example Watch",
            manufacturer: "Example",
            model: "W42",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: "unit-42",
            udiDeviceIdentifier: "udi-42"
        )

        let lossy = try await ExporterFixtures.export(Self.heartRate(device: unidentified, metadata: [:]))
        #expect(lossy.warnings == [Self.effectiveDateTimeOffsetUnavailable])

        let withheld = try await ExporterFixtures.export(
            Self.heartRate(
                device: identified,
                metadata: [HKMetadataKeyTimeZone: "America/Los_Angeles", "com.example.zeta": "z", "com.example.custom": "x"]
            )
        )
        #expect(withheld.warnings.isEmpty)

        let complete = try await ExporterFixtures.export(
            Self.heartRate(device: identified, metadata: [HKMetadataKeyTimeZone: "America/Los_Angeles"])
        )
        #expect(complete.warnings.isEmpty)
    }

    @Test("An interval names each effective field that lost its offset", arguments: [
        (HKQuantityTypeIdentifier.stepCount, HKUnit.count()),
        (.heartRate, .count().unitDivided(by: .minute()))
    ])
    func intervalReportsBothBounds(type: HKQuantityTypeIdentifier, unit: HKUnit) async throws {
        let start = TestDeployment.testInstant
        let interval = HKQuantitySample(
            type: HKQuantityType(type),
            quantity: HKQuantity(unit: unit, doubleValue: 120),
            start: start,
            end: start.addingTimeInterval(60)
        )
        let conversion = try await ExporterFixtures.export(interval)
        #expect(conversion.warnings == [
            ExchangeGraphRule.mobileOmissionSourceOffset.diagnostic(at: "Observation.effectivePeriod.start"),
            ExchangeGraphRule.mobileOmissionSourceOffset.diagnostic(at: "Observation.effectivePeriod.end")
        ])
        #expect(conversion.warnings.map(\.location) == ["Observation.effectivePeriod.start", "Observation.effectivePeriod.end"])
    }
}


/// Every effective value takes the source's time zone, else UTC, and never the host's.
@Suite
struct EffectiveTimeZoneTests {
    private static let start = TestDeployment.testInstant
    private static let end = start.addingTimeInterval(600)

    @Test("A stated zone gives every bound its offset and the timezone extension")
    func statedZone() throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let period = try HealthKitEffectiveTime.period(start: Self.start, end: Self.end, zone: zone)
        #expect(period.start?.value?.description == "2026-08-17T16:30:00-07:00")
        #expect(period.end?.value?.description == "2026-08-17T16:40:00-07:00")
        for bound in [period.start, period.end] {
            #expect(bound?.extension?.map(\.url) == [Canonicals.timezone])
            #expect(bound?.extension?.first?.value == .code("America/Los_Angeles".asFHIRStringPrimitive()))
        }
    }

    @Test("Clock instants are UTC whatever zone the sample states, and only the effective time follows it")
    func clockInstantsAreUTC() async throws {
        func conversion(_ zone: String) async throws -> ExportedRecord {
            let sample = HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 72),
                start: Self.start,
                end: Self.start,
                metadata: [HKMetadataKeyTimeZone: zone]
            )
            return try await ExporterFixtures.export(sample)
        }
        let pacific = try await conversion("America/Los_Angeles")
        let tokyo = try await conversion("Asia/Tokyo")
        for graph in [pacific, tokyo] {
            #expect(graph.bundle.timestamp?.value?.description == "2026-08-17T23:30:00Z")
            #expect(graph.provenance.recorded.value?.description == "2026-08-17T23:30:00Z")
            guard case .dateTime(let occurred)? = graph.provenance.occurred else {
                Issue.record("The Provenance lost its occurred time")
                return
            }
            #expect(occurred.value?.description == "2026-08-17T23:30:00Z")
        }
        #expect(pacific.bundle.timestamp == tokyo.bundle.timestamp)
        #expect(pacific.observation.effective != tokyo.observation.effective)
    }

    @Test("Without a stated zone every bound is in UTC and carries no timezone extension")
    func unstatedZone() throws {
        let period = try HealthKitEffectiveTime.period(start: Self.start, end: Self.end, zone: nil)
        #expect(period.start?.value?.description == "2026-08-17T23:30:00Z")
        #expect(period.end?.value?.description == "2026-08-17T23:40:00Z")
        #expect(period.start?.extension == nil && period.end?.extension == nil)
        #expect(try HealthKitEffectiveTime.dateTime(Self.start, zone: nil).value?.description == "2026-08-17T23:30:00Z")
    }
}


/// The contract checks that need an adapter or a graph; the identity vectors are `ExchangeProtocolVectorTests`.
@Suite(.enabled(if: groveFHIRIsAvailable, "Requires the grove-fhir checkout used by FHIR Output Conformance"))
struct ProducerContractVectorTests {
    @Test("An identity fault reports the same registry code on every platform")
    func identityFaultCodes() {
        let path = "source-artifact.part-index"
        let table: [(ProducerDiagnostic, ProducerDiagnostic)] = [
            (ExchangeIdentityError.emptyComponent(path).diagnostic, ExchangeGraphRule.mobileInputRequiredMetadataMissing.diagnostic(at: path)),
            (ExchangeIdentityError.nonCanonicalPartIndex(path).diagnostic, ExchangeGraphRule.mobileInputUnclassified.diagnostic(at: path)),
            (ExchangeIdentityError.keyTooShort(actualBytes: 16).diagnostic, ExchangeGraphRule.mobileInputUnclassified.diagnostic),
            (ExchangeIdentityError.invalidKeyID("").diagnostic, ExchangeGraphRule.mobileInputUnclassified.diagnostic),
            (ExchangeIdentityError.invalidIdentifierSystem("x").diagnostic, ExchangeGraphRule.mobileInputUnclassified.diagnostic)
        ]
        for (actual, expected) in table {
            #expect(actual == expected, "\(expected.code)")
        }
        let fault = ExchangeIdentityError.emptyComponent(path)
        #expect(HealthKitConversionError.exchangeIdentity(fault).diagnostic == fault.diagnostic)
    }

    @Test("The study-attribution source Bundle is a complete bundled study context")
    func studyAttributionSourceBundle() throws {
        let path = groveFHIRRoot.appendingPathComponent("Conformance/corpora/study-attribution/source-event.json")
        _ = try ExchangeGraph(validating: Data(contentsOf: path), kind: .active)
    }
}


/// The shared producer surface names every concept the way the other platforms do.
@Suite
struct ProducerSurfaceTests {
    private static let heartRate = HKQuantitySample(
        type: HKQuantityType(.heartRate),
        quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 72),
        start: TestDeployment.testInstant,
        end: TestDeployment.testInstant
    )

    @Test("The writer and its host are graph nodes once the caller classifies an attributed sample's source as an application")
    func writerNodes() async throws {
        let attributed = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xC1), writer: GoldenFixtures.foreignWriter)
        await #expect(try ExporterFixtures.export(attributed).identifiers.writerSnapshot == nil)
        let conversion = try await ExporterFixtures.export(attributed, .applicationWriter)
        #expect(conversion.identifiers.writerSnapshot != nil)
        #expect(conversion.identifiers.writerHostSnapshot != nil)
    }

    @Test("A writer snapshot the converter already states is that entry, and its host goes with it")
    func writerSharingAConverterSnapshot() throws {
        func device(_ name: String, role: OpaqueIdentityScope.NodeRole) throws -> IdentifiedDevice {
            let context = TestDeployment.test()
            var resource = Device()
            resource.deviceName = [DeviceDeviceName(name: name.asFHIRStringPrimitive(), type: FHIRPrimitive(.userFriendlyName))]
            return try IdentifiedDevice(keying: resource, role: role, subject: context.subject.identifier, identityScope: context.identityScope)
        }
        let converterHost = try device("iPhone17,1|26.0.0", role: .host)
        let converterApplication = try device("org.grovealliance.test|1.0|1", role: .application)
        let stated: Set = [converterHost.identity, converterApplication.identity]

        let health = try device("com.apple.Health|26.0", role: .application)
        let sameHost = ExchangeGraphAssembler.writerEntries(
            application: health,
            host: try device("iPhone17,1|26.0.0", role: .host),
            stated: stated
        )
        #expect(sameHost.map(\.identity) == [health.identity])

        let converterItself = ExchangeGraphAssembler.writerEntries(
            application: try device("org.grovealliance.test|1.0|1", role: .application),
            host: try device("iPhone16,2|25.4.0", role: .host),
            stated: stated
        )
        #expect(converterItself.isEmpty)
    }

    @Test("A gateway application is its own snapshot: never the writer and never given a repository id")
    func gatewayApplicationSnapshot() async throws {
        let gateway = ApplicationDevice.test(name: "Cuff Companion", bundleIdentifier: "com.example.cuff", version: "3.1")
        var inputs = ExportInputs()
        inputs.options.role = .gatewayApplication(gateway)
        let conversion = try await ExporterFixtures.export(Self.heartRate, inputs)
        let devices = conversion.bundle.entry?.compactMap { $0.resource?.get(if: Device.self) } ?? []
        let device = try #require(devices.first { $0.deviceName?.first?.name == "Cuff Companion" })
        #expect(device.id == nil)
        #expect(conversion.identifiers.writerSnapshot == nil)
        #expect(conversion.converterApplication.id == nil)
        #expect(conversion.bundle.id == nil)
    }

    @Test("A gateway application that is the converting application states the converter as the gateway")
    func gatewayApplicationEqualToTheConverter() async throws {
        var named = ExportInputs()
        named.options.role = .gatewayApplication(named.converter)
        var gateway = ExportInputs()
        gateway.options.role = .gateway
        let conversion = try await ExporterFixtures.export(Self.heartRate, named)
        await #expect(conversion.record == (try ExporterFixtures.export(Self.heartRate, gateway)).record)
    }

    @Test("The application and host snapshots are keyed by their content, and the application's content holds its host")
    func deviceContentKeysTheSnapshots() async throws {
        let base = try await ExporterFixtures.export(Self.heartRate)
        let again = try await ExporterFixtures.export(Self.heartRate)
        #expect(again.identifiers.hostSnapshot == base.identifiers.hostSnapshot)
        #expect(again.identifiers.applicationSnapshot == base.identifiers.applicationSnapshot)

        var updatedHost = ExportInputs()
        updatedHost.converterHost = try HostDevice(operatingSystemVersion: "20.2", productType: "Phone One")
        let hostChanged = try await ExporterFixtures.export(Self.heartRate, updatedHost)
        #expect(hostChanged.identifiers.hostSnapshot != base.identifiers.hostSnapshot)
        #expect(hostChanged.identifiers.applicationSnapshot != base.identifiers.applicationSnapshot, "Device.parent is part of its content")

        var renamed = ExportInputs()
        renamed.converter = ApplicationDevice.test(name: "Renamed", bundleIdentifier: ApplicationDevice.test.bundleIdentifier, version: "1.0")
        let applicationChanged = try await ExporterFixtures.export(Self.heartRate, renamed)
        #expect(applicationChanged.identifiers.hostSnapshot == base.identifiers.hostSnapshot)
        #expect(applicationChanged.identifiers.applicationSnapshot != base.identifiers.applicationSnapshot)

        var otherSubject = ExportInputs()
        otherSubject.subject = .logical(.test(.patient, "someone-else"))
        let subjectChanged = try await ExporterFixtures.export(Self.heartRate, otherSubject)
        #expect(subjectChanged.identifiers.hostSnapshot != base.identifiers.hostSnapshot, "a snapshot is keyed per subject")
    }

    @Test("A subject states its pseudonym as its identifier however it travels")
    func subjectIdentifier() {
        let pseudonym = BusinessIdentifier.test(.patient, "example")
        #expect(Subject.logical(pseudonym).identifier == pseudonym)
        #expect(Subject.bundled(pseudonym, Patient()).identifier == pseudonym)
    }

    @Test("A study enrollment is flat: study, protocol URL and version, enrollment")
    func flatStudyEnrollment() {
        let enrollment = StudyEnrollment.test("study-1")
        #expect(enrollment.study == .test(.researchStudy, "study-1"))
        #expect(enrollment.protocolURL.value?.url.absoluteString == "https://study.example.org/PlanDefinition/study-1")
        #expect(enrollment.protocolVersion == "1")
        #expect(enrollment.enrollment == .test(.researchSubject, "enrollment-study-1"))
    }

    @Test("A retraction's one target is the source record, and carries the native record identifier only under the disclosure policy")
    func retractionTargets() async throws {
        let deletion = HealthKitFHIRExporter.Deletion(
            uuid: Self.heartRate.uuid,
            sourceType: .heartRate,
            deletedAfter: nil,
            detectedAt: TestDeployment.testInstant
        )
        func targets(_ inputs: ExportInputs) async throws -> [Reference] {
            let graph = try await ExporterFixtures.retraction(deletion, inputs)
            return try #require(graph.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first).target
        }
        func native(_ target: Reference) -> Extension.ValueX? {
            target.extension?.first { $0.url == Canonicals.retractionTargetNativeIdentifier }?.value
        }
        let omitted = try await targets(ExportInputs())
        #expect(omitted.count == 1)
        #expect(omitted.first?.type == nil)
        #expect(omitted.first?.extension?.first { $0.url == Canonicals.retractionTargetRole }?.value == .code("source-record"))
        #expect(omitted.allSatisfy { native($0) == nil })

        let store: IdentifierSystem = "https://study.example.org/fhir/NamingSystem/healthkit-store"
        var inputs = ExportInputs()
        inputs.options.nativeIdentifier = .authorized(system: store)
        let disclosed = try await targets(inputs)
        let nativeIdentifier = try BusinessIdentifier(system: store, value: Self.heartRate.uuid.uuidString.lowercased())
        #expect(disclosed.map(native) == [.identifier(nativeIdentifier.fhirIdentifier)])
        #expect(disclosed.map(\.identifier) == omitted.map(\.identifier))

        let graph = try await ExporterFixtures.retraction(deletion, inputs)
        let provenance = try #require(graph.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        #expect(graph.bundle.timestamp?.value?.description == "2026-08-17T23:30:00Z")
        #expect(provenance.recorded.value?.description == "2026-08-17T23:30:00Z")
        #expect(provenance.occurred == .period(Period(end: FHIRPrimitive(try DateTime("2026-08-17T23:30:00Z")))))

        // A native identifier system the deployment's identity scope reserves is refused when the exporter is configured.
        var reserved = ExportInputs()
        let reservedSystem = reserved.base.identityScope.systems.sourceOutput
        reserved.options.nativeIdentifier = .authorized(system: reservedSystem)
        #expect(throws: HealthKitFHIRExporter.ConfigurationError.reservedNativeIdentifierSystem(reservedSystem)) {
            try ExporterFixtures.exporter(reserved)
        }
    }

    @Test("A deletion reported for a sample type retracts its source record")
    func retractionFromDeletedObject() async throws {
        let type = try #require(HealthKitSourceType(HKQuantityType(.heartRate)))
        #expect(HealthKitSourceType(HKCategoryType(.sleepAnalysis)) == .sleepAnalysis)
        let retraction = try await ExporterFixtures.retraction(HealthKitFHIRExporter.Deletion(
            uuid: Self.heartRate.uuid,
            sourceType: type,
            deletedAfter: nil,
            detectedAt: TestDeployment.testInstant
        ))
        let conversion = try await ExporterFixtures.export(Self.heartRate)
        let provenance = try #require(retraction.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        let targets = try provenance.target.map { try RoledIdentifier(#require($0.identifier)) }
        #expect(targets == [conversion.primary.identifiers.sourceRecord])
        let source = try RoledIdentifier(#require(provenance.entity?.first?.what.identifier))
        #expect(source == conversion.primary.identifiers.sourceRecord)
        #expect(provenance.occurred == .period(Period(end: FHIRPrimitive(try DateTime("2026-08-17T23:30:00Z")))))

        // The exporter drops a lower bound later than the detection; the retraction record itself refuses an inverted
        // period.
        let target = try RetractionRecord.Target(sourceRecord: targets[0])
        #expect(throws: RetractionRecord.ValidationError.invalidOccurrencePeriod) {
            try TestDeployment.test().retraction(
                of: source,
                targets: [target],
                occurred: .period(start: TestDeployment.testInstant, end: TestDeployment.testInstant.addingTimeInterval(-1))
            )
        }
    }
}

#endif
